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

      await _sendToPeer(receiverIp, message, receiverId);

      final sentMessage =
          message.copyWith(status: AppConstants.messageStatusSent);
      await StorageService.instance.updateMessageStatus(
          conversationId, message.id, AppConstants.messageStatusSent);
      _messageStatusController.add(sentMessage);

      AppLogger.instance.info('Message sent to $receiverId: ${message.id}');
      return sentMessage;
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
              milliseconds:
                  AppConstants.messageRetryDelayMs * (1 << attempt)));
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
    } catch (e, stackTrace) {
      AppLogger.instance
          .error('Failed to handle incoming packet', e, stackTrace);
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
        participantAvatarColor: existing?.participantAvatarColor ??
            peerAvatarColor,
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
      }
    } catch (e, stackTrace) {
      AppLogger.instance
          .error('Failed to mark conversation as read', e, stackTrace);
    }
  }

  Future<void> deleteMessage(
      String conversationId, String messageId) async {
    try {
      final messages = StorageService.instance.getMessages(conversationId);
      final filtered =
          messages.where((m) => m.id != messageId).toList();
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
