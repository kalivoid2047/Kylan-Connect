import 'dart:async';
import '../core/constants/app_constants.dart';
import '../core/security/encryption_service.dart';
import '../core/errors/exceptions.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../models/message_packet.dart';
import '../services/connection_manager.dart';
import '../services/discovery_service.dart';
import '../services/notification_service.dart';
import '../services/storage_service.dart';
import '../services/typing_service.dart';
import '../core/utils/app_logger.dart';

class MessagingService {
  static final MessagingService _instance = MessagingService._internal();
  static MessagingService get instance => _instance;

  final StreamController<Message> _messageReceivedController =
      StreamController.broadcast();
  final StreamController<Message> _messageStatusController =
      StreamController.broadcast();
  StreamSubscription<MessagePacket>? _connectionSubscription;

  String? _currentUserId;
  bool _isInitialized = false;

  MessagingService._internal();

  Stream<Message> get onMessageReceived => _messageReceivedController.stream;
  Stream<Message> get onMessageStatusChanged => _messageStatusController.stream;
  bool get isInitialized => _isInitialized;

  Future<void> initialize(String userId) async {
    if (_isInitialized && _currentUserId == userId) return;

    _currentUserId = userId;

    await _connectionSubscription?.cancel();
    _connectionSubscription = ConnectionManager.instance.onMessageReceived
        .listen(_handleIncomingPacket);

    _isInitialized = true;
    AppLogger.instance.info('Messaging service initialized for user: $userId');
  }

  Future<Message> sendMessage({
    required String receiverId,
    required String receiverIp,
    required String text,
  }) async {
    if (!_isInitialized) {
      throw const MessagingException('Messaging service not initialized');
    }

    final message = Message.createTextMessage(
      senderId: _currentUserId!,
      receiverId: receiverId,
      text: text,
    );
    final conversationId =
        Conversation.generateConversationId(_currentUserId!, receiverId);

    try {
      await StorageService.instance.saveMessage(conversationId, message);
      await _updateConversation(
        peerId: receiverId,
        peerIp: receiverIp,
        lastMessage: text,
        isIncoming: false,
      );

      try {
        await _sendToPeer(receiverIp, message, receiverId);

        final sentMessage =
            message.copyWith(status: AppConstants.messageStatusSent);
        await StorageService.instance.updateMessageStatus(
            conversationId, message.id, AppConstants.messageStatusSent);
        _messageStatusController.add(sentMessage);

        AppLogger.instance.info('Message sent to $receiverId: ${message.id}');
        return sentMessage;
      } catch (sendError) {
        // Peer not reachable, enqueue for offline delivery
        AppLogger.instance.warning(
            'Peer not reachable, enqueuing for offline delivery: $receiverId');
        await enqueueMessageForOfflineDelivery(message);

        final queuedMessage =
            message.copyWith(status: AppConstants.messageStatusSending);
        _messageStatusController.add(queuedMessage);

        return queuedMessage;
      }
    } catch (e, stackTrace) {
      await StorageService.instance.updateMessageStatus(
          conversationId, message.id, AppConstants.messageStatusFailed);
      _messageStatusController
          .add(message.copyWith(status: AppConstants.messageStatusFailed));
      AppLogger.instance.error('Failed to send message', e, stackTrace);
      throw MessagingException('Failed to send message', e);
    }
  }

  Future<void> _sendToPeer(
      String ipAddress, Message message, String receiverId) async {
    // Mark this peer so the reconnect timer keeps the connection alive.
    ConnectionManager.instance.registerIntendedPeer(ipAddress);

    // Derive a shared key — computed identically on both devices.
    final key = EncryptionService.instance
        .getConversationKey(_currentUserId!, receiverId);
    final encryptedData =
        EncryptionService.instance.encryptJsonWithKey(message.toJson(), key);

    final packet = MessagePacket(
      id: message.id,
      type: message.type,
      senderId: message.senderId,
      receiverId: message.receiverId,
      payload: {'encrypted': encryptedData},
      timestamp: message.timestamp,
    );

    // Retry up to maxRetries times with exponential back-off.
    Exception? lastError;
    for (int attempt = 0; attempt < AppConstants.maxRetries; attempt++) {
      try {
        if (!ConnectionManager.instance.isConnectedTo(ipAddress)) {
          await ConnectionManager.instance.connectToPeer(ipAddress);
        }
        await ConnectionManager.instance.sendPacket(ipAddress, packet);
        return; // success
      } catch (e) {
        lastError = MessagingException('Send attempt ${attempt + 1} failed', e);
        AppLogger.instance.warning(
            'Send to $ipAddress failed (attempt ${attempt + 1}/${AppConstants.maxRetries}): $e');

        if (attempt < AppConstants.maxRetries - 1) {
          // Exponential back-off: 1 s, 2 s, 4 s …
          await Future<void>.delayed(Duration(
              milliseconds: AppConstants.messageRetryDelayMs * (1 << attempt)));
        }
      }
    }

    AppLogger.instance.error('All send attempts exhausted for $ipAddress');
    throw lastError!;
  }

  void _handleIncomingPacket(MessagePacket packet) {
    try {
      final encryptedData = packet.payload['encrypted'] as String?;
      if (encryptedData == null) {
        AppLogger.instance.warning('Received unencrypted message — ignored');
        return;
      }

      // Derive the same shared key the sender used.
      final key = EncryptionService.instance
          .getConversationKey(_currentUserId!, packet.senderId);
      final decryptedJson =
          EncryptionService.instance.decryptJsonWithKey(encryptedData, key);

      final message = Message.fromJson(decryptedJson);

      // Control messages (ACKs, read receipts, typing) are not stored as
      // conversation history — they update state and are routed separately.
      if (message.isControlMessage) {
        _handleControlMessage(message);
        return;
      }

      final deliveredMessage =
          message.copyWith(status: AppConstants.messageStatusDelivered);

      final conversationId = Conversation.generateConversationId(
          _currentUserId!, message.senderId);
      StorageService.instance.saveMessage(conversationId, deliveredMessage);

      // Look up sender's IP from discovery (may be empty if peer is offline).
      final peerIp =
          DiscoveryService.instance.getPeer(message.senderId)?.ipAddress ?? '';

      _updateConversation(
        peerId: message.senderId,
        peerIp: peerIp,
        lastMessage: message.textContent ?? '',
        isIncoming: true,
      );

      // Fire in-app notification.
      final senderName =
          DiscoveryService.instance.getPeer(message.senderId)?.displayName ??
              'Unknown';
      NotificationService.instance
          .showNewMessageNotification(deliveredMessage, senderName);

      _messageReceivedController.add(deliveredMessage);
      AppLogger.instance
          .info('Message received from ${message.senderId}: ${message.id}');

      // Tell the sender we received it so their copy flips to "delivered".
      _sendDeliveryAck(message, peerIp);
    } catch (e, stackTrace) {
      AppLogger.instance
          .error('Failed to handle incoming packet', e, stackTrace);
    }
  }

  /// Routes an incoming control message (delivery ACK, read receipt, typing)
  /// to the appropriate handler. Control messages are never persisted.
  void _handleControlMessage(Message message) {
    switch (message.type) {
      case AppConstants.messageTypeDeliveryAck:
        _applyOutgoingStatus(
          peerId: message.senderId,
          originalMessageId: message.originalMessageId,
          status: AppConstants.messageStatusDelivered,
        );
        break;
      case AppConstants.messageTypeReadReceipt:
        _applyOutgoingStatus(
          peerId: message.senderId,
          originalMessageId: message.originalMessageId,
          status: AppConstants.messageStatusRead,
        );
        break;
      case AppConstants.messageTypeTyping:
        // Receive side of typing indicators; send side lives in TypingService.
        TypingService.instance.handleTypingIndicator(message);
        break;
      default:
        AppLogger.instance
            .warning('Unknown control message type: ${message.type}');
    }
  }

  /// Ranks a status so that late/duplicate control packets can never move a
  /// message backwards (e.g. a delayed delivery ACK overwriting "read").
  int _statusRank(String status) {
    switch (status) {
      case AppConstants.messageStatusSending:
        return 0;
      case AppConstants.messageStatusSent:
        return 1;
      case AppConstants.messageStatusDelivered:
        return 2;
      case AppConstants.messageStatusRead:
        return 3;
      default:
        return -1; // failed / unknown — never advanced over by a receipt
    }
  }

  /// Applies a delivered/read status update to one of our outgoing messages,
  /// identified by [originalMessageId] within the conversation with [peerId].
  Future<void> _applyOutgoingStatus({
    required String peerId,
    required String? originalMessageId,
    required String status,
  }) async {
    if (originalMessageId == null) {
      AppLogger.instance
          .warning('Control message missing originalMessageId — ignored');
      return;
    }

    try {
      final conversationId =
          Conversation.generateConversationId(_currentUserId!, peerId);
      final messages = StorageService.instance.getMessages(conversationId);

      Message? target;
      for (final m in messages) {
        if (m.id == originalMessageId) {
          target = m;
          break;
        }
      }
      if (target == null) return;

      // Don't move a message backwards to an earlier lifecycle stage.
      if (_statusRank(status) <= _statusRank(target.status)) return;

      await StorageService.instance
          .updateMessageStatus(conversationId, originalMessageId, status);
      _messageStatusController.add(target.copyWith(status: status));

      AppLogger.instance
          .debug('Outgoing message $originalMessageId -> $status');
    } catch (e, stackTrace) {
      AppLogger.instance
          .error('Failed to apply outgoing status update', e, stackTrace);
    }
  }

  /// Sends a delivery ACK for a message we just received. Best-effort: if the
  /// peer's IP is unknown or the send fails, the ACK is simply dropped.
  Future<void> _sendDeliveryAck(Message original, String peerIp) async {
    final ack = Message.createDeliveryAck(
      senderId: _currentUserId!,
      receiverId: original.senderId,
      originalMessageId: original.id,
    );
    await _sendControlMessage(ack, original.senderId, peerIp);
  }

  /// Encrypts and sends a control message to a peer without persisting it.
  /// Best-effort and non-retrying — control packets are disposable.
  Future<void> _sendControlMessage(
      Message controlMessage, String receiverId, String receiverIp) async {
    if (receiverIp.isEmpty) {
      AppLogger.instance.debug(
          'No IP for $receiverId — skipping ${controlMessage.type} control message');
      return;
    }

    try {
      final key = EncryptionService.instance
          .getConversationKey(_currentUserId!, receiverId);
      final encryptedData = EncryptionService.instance
          .encryptJsonWithKey(controlMessage.toJson(), key);

      final packet = MessagePacket(
        id: controlMessage.id,
        type: controlMessage.type,
        senderId: controlMessage.senderId,
        receiverId: controlMessage.receiverId,
        payload: {'encrypted': encryptedData},
        timestamp: controlMessage.timestamp,
      );

      if (!ConnectionManager.instance.isConnectedTo(receiverIp)) {
        await ConnectionManager.instance.connectToPeer(receiverIp);
      }
      await ConnectionManager.instance.sendPacket(receiverIp, packet);
      AppLogger.instance
          .debug('Sent ${controlMessage.type} control message to $receiverId');
    } catch (e) {
      // Control messages are disposable — a failure here is not user-facing.
      AppLogger.instance.debug(
          'Failed to send ${controlMessage.type} control message to $receiverId: $e');
    }
  }

  Future<void> _updateConversation({
    required String peerId,
    required String peerIp,
    required String lastMessage,
    required bool isIncoming,
  }) async {
    try {
      final peer = DiscoveryService.instance.getPeer(peerId);
      final peerName = peer?.displayName ?? 'Unknown';
      final peerAvatarColor =
          peer?.avatarColor ?? AppConstants.avatarColors.first;
      final isOnline = peer?.isOnline ?? false;

      final conversationId =
          Conversation.generateConversationId(_currentUserId!, peerId);
      final existing = StorageService.instance.getConversation(conversationId);

      final newUnreadCount = isIncoming ? (existing?.unreadCount ?? 0) + 1 : 0;

      final conversation = Conversation(
        conversationId: conversationId,
        participantId: peerId,
        participantName:
            existing?.participantName != 'Unknown' && existing != null
                ? existing.participantName
                : peerName,
        participantAvatarColor:
            existing?.participantAvatarColor ?? peerAvatarColor,
        lastMessage: lastMessage,
        lastMessageTime: DateTime.now(),
        unreadCount: newUnreadCount,
        isOnline: isOnline,
      );

      await StorageService.instance.saveConversation(conversation);
    } catch (e, stackTrace) {
      AppLogger.instance.error('Failed to update conversation', e, stackTrace);
    }
  }

  Future<List<Message>> getMessages(String conversationId) async {
    try {
      return StorageService.instance.getMessages(conversationId);
    } catch (e, stackTrace) {
      AppLogger.instance.error('Failed to get messages', e, stackTrace);
      throw MessagingException('Failed to get messages', e);
    }
  }

  Future<void> markAsRead(String conversationId) async {
    try {
      final conversation =
          StorageService.instance.getConversation(conversationId);
      if (conversation != null && conversation.unreadCount > 0) {
        await StorageService.instance
            .saveConversation(conversation.copyWith(unreadCount: 0));

        // Let the peer know we've read their messages so their copies flip
        // to "read". Only fires when there were genuinely unread messages,
        // which keeps read receipts from being re-sent on every open.
        await _sendReadReceipts(conversation.participantId);
      }
    } catch (e, stackTrace) {
      AppLogger.instance
          .error('Failed to mark conversation as read', e, stackTrace);
    }
  }

  /// Sends read receipts for the incoming messages in this conversation.
  Future<void> _sendReadReceipts(String peerId) async {
    final peerIp = DiscoveryService.instance.getPeer(peerId)?.ipAddress ?? '';
    if (peerIp.isEmpty) return; // Peer offline — receipts are best-effort.

    final conversationId =
        Conversation.generateConversationId(_currentUserId!, peerId);
    final messages = StorageService.instance.getMessages(conversationId);

    for (final message in messages) {
      // Only acknowledge messages the peer sent us (incoming).
      if (message.senderId != peerId) continue;
      if (message.isControlMessage) continue;

      final receipt = Message.createReadReceipt(
        senderId: _currentUserId!,
        receiverId: peerId,
        originalMessageId: message.id,
      );
      await _sendControlMessage(receipt, peerId, peerIp);
    }
  }

  /// Flush offline messages for a peer when they come back online.
  /// Called when discovery service detects a peer.
  Future<void> flushOfflineMessagesForPeer(String peerId, String peerIp) async {
    try {
      final offlineMessages =
          StorageService.instance.getOfflineMessagesForPeer(peerId);

      if (offlineMessages.isEmpty) {
        AppLogger.instance
            .debug('No offline messages to flush for peer: $peerId');
        return;
      }

      AppLogger.instance.info(
          'Flushing ${offlineMessages.length} offline messages for peer: $peerId');

      for (final message in offlineMessages) {
        try {
          await _sendToPeer(peerIp, message, peerId);

          final conversationId =
              Conversation.generateConversationId(_currentUserId!, peerId);
          await StorageService.instance.updateMessageStatus(
              conversationId, message.id, AppConstants.messageStatusSent);

          await StorageService.instance.removeOfflineMessage(message.id);

          AppLogger.instance.debug('Flushed offline message: ${message.id}');
        } catch (e) {
          AppLogger.instance
              .warning('Failed to flush offline message ${message.id}: $e');
          // Keep message in queue for next attempt
        }
      }

      // Clear queue for this peer if all messages were sent
      final remaining =
          StorageService.instance.getOfflineMessagesForPeer(peerId);
      if (remaining.isEmpty) {
        await StorageService.instance.clearOfflineQueueForPeer(peerId);
      }
    } catch (e, stackTrace) {
      AppLogger.instance
          .error('Failed to flush offline messages', e, stackTrace);
    }
  }

  /// Enqueue a message for offline delivery if peer is not reachable.
  Future<void> enqueueMessageForOfflineDelivery(Message message) async {
    try {
      await StorageService.instance.enqueueOfflineMessage(message);
      AppLogger.instance
          .info('Message enqueued for offline delivery: ${message.id}');
    } catch (e, stackTrace) {
      AppLogger.instance.error(
          'Failed to enqueue message for offline delivery', e, stackTrace);
    }
  }

  Future<void> deleteMessage(String conversationId, String messageId) async {
    try {
      final messages = StorageService.instance.getMessages(conversationId);
      final filtered = messages.where((m) => m.id != messageId).toList();
      await StorageService.instance.replaceMessages(conversationId, filtered);
      AppLogger.instance.debug('Message deleted: $messageId');
    } catch (e, stackTrace) {
      AppLogger.instance.error('Failed to delete message', e, stackTrace);
      throw MessagingException('Failed to delete message', e);
    }
  }

  void dispose() {
    _connectionSubscription?.cancel();
    _messageReceivedController.close();
    _messageStatusController.close();
  }
}
