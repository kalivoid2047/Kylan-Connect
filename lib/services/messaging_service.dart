import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:uuid/uuid.dart';
import '../core/constants/app_constants.dart';
import '../core/security/crypto_service.dart';
import '../core/errors/exceptions.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../models/message_packet.dart';
import '../services/connection_manager.dart';
import '../services/discovery_service.dart';
import '../services/file_service.dart';
import '../services/image_service.dart';
import '../services/notification_service.dart';
import '../services/storage_service.dart';
import '../services/typing_service.dart';
import '../core/utils/app_logger.dart';

/// Reassembly state for an attachment (image or file) arriving in chunks.
class _IncomingTransfer {
  final String senderId;
  final bool isImage;
  String? fileName;
  int? total;
  final Map<int, Uint8List> chunks = {};

  _IncomingTransfer(this.senderId, {required this.isImage});
}

class MessagingService {
  static final MessagingService _instance = MessagingService._internal();
  static MessagingService get instance => _instance;

  final StreamController<Message> _messageReceivedController =
      StreamController.broadcast();
  final StreamController<Message> _messageStatusController =
      StreamController.broadcast();

  /// Emits a transferId when an attachment has finished downloading to disk so
  /// the chat can refresh and show/enable the full file.
  final StreamController<String> _transferReadyController =
      StreamController.broadcast();
  StreamSubscription<MessagePacket>? _connectionSubscription;

  /// In-flight incoming attachment transfers, keyed by transferId.
  final Map<String, _IncomingTransfer> _incomingTransfers = {};

  String? _currentUserId;
  bool _isInitialized = false;

  MessagingService._internal();

  Stream<Message> get onMessageReceived => _messageReceivedController.stream;
  Stream<Message> get onMessageStatusChanged => _messageStatusController.stream;
  Stream<String> get onTransferReady => _transferReadyController.stream;
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

  /// Sends an image: persists a bubble carrying only a thumbnail + metadata,
  /// then streams the full image to the peer in encrypted chunks. The full
  /// file is written to the sender's own disk too, so it can be reopened.
  Future<Message> sendImage({
    required String receiverId,
    required String receiverIp,
    required File imageFile,
  }) async {
    if (!_isInitialized) {
      throw const MessagingException('Messaging service not initialized');
    }
    if (!CryptoService.instance.canEncryptFor(receiverId)) {
      throw const MessagingException(
          'No public key for peer — cannot send image');
    }

    final bytes = await imageFile.readAsBytes();
    final thumbnail = ImageService.instance.generateThumbnailBase64(bytes);
    if (thumbnail == null) {
      throw const MessagingException('Selected file is not a valid image');
    }
    final dims = ImageService.instance.imageDimensions(bytes);
    final transferId = const Uuid().v4();
    final fileName = imageFile.path.split(RegExp(r'[/\\]')).last;

    // Keep our own copy on disk so the sender can reopen the full image.
    await ImageService.instance.saveImageBytes(transferId, fileName, bytes);

    final message = Message.createImageMessage(
      senderId: _currentUserId!,
      receiverId: receiverId,
      transferId: transferId,
      thumbnailBase64: thumbnail,
      fileName: fileName,
      fileSize: bytes.length,
      width: dims.width,
      height: dims.height,
    );
    final conversationId =
        Conversation.generateConversationId(_currentUserId!, receiverId);

    try {
      await StorageService.instance.saveMessage(conversationId, message);
      await _updateConversation(
        peerId: receiverId,
        peerIp: receiverIp,
        lastMessage: '📷 Photo',
        isIncoming: false,
      );

      // Send the bubble (thumbnail + metadata) first, then the chunks.
      await _sendToPeer(receiverIp, message, receiverId);
      await _sendTransferChunks(receiverId, receiverIp, transferId, bytes);

      final sent = message.copyWith(status: AppConstants.messageStatusSent);
      await StorageService.instance.updateMessageStatus(
          conversationId, message.id, AppConstants.messageStatusSent);
      _messageStatusController.add(sent);
      AppLogger.instance.info('Image sent to $receiverId: $transferId');
      return sent;
    } catch (e, stackTrace) {
      await StorageService.instance.updateMessageStatus(
          conversationId, message.id, AppConstants.messageStatusFailed);
      _messageStatusController
          .add(message.copyWith(status: AppConstants.messageStatusFailed));
      AppLogger.instance.error('Failed to send image', e, stackTrace);
      throw MessagingException('Failed to send image', e);
    }
  }

  /// Sends an arbitrary file: persists a bubble carrying only metadata, then
  /// streams the bytes to the peer in encrypted chunks. The file is written to
  /// the sender's own disk too, so it can be reopened.
  Future<Message> sendFile({
    required String receiverId,
    required String receiverIp,
    required File file,
  }) async {
    if (!_isInitialized) {
      throw const MessagingException('Messaging service not initialized');
    }
    if (!CryptoService.instance.canEncryptFor(receiverId)) {
      throw const MessagingException(
          'No public key for peer — cannot send file');
    }

    final bytes = await file.readAsBytes();
    final transferId = const Uuid().v4();
    final fileName = file.path.split(RegExp(r'[/\\]')).last;

    // Keep our own copy on disk so the sender can reopen the file.
    await FileService.instance.saveBytes(transferId, fileName, bytes);

    final message = Message.createFileMessage(
      senderId: _currentUserId!,
      receiverId: receiverId,
      transferId: transferId,
      fileName: fileName,
      fileSize: bytes.length,
    );
    final conversationId =
        Conversation.generateConversationId(_currentUserId!, receiverId);

    try {
      await StorageService.instance.saveMessage(conversationId, message);
      await _updateConversation(
        peerId: receiverId,
        peerIp: receiverIp,
        lastMessage: '📎 $fileName',
        isIncoming: false,
      );

      await _sendToPeer(receiverIp, message, receiverId);
      await _sendTransferChunks(receiverId, receiverIp, transferId, bytes);

      final sent = message.copyWith(status: AppConstants.messageStatusSent);
      await StorageService.instance.updateMessageStatus(
          conversationId, message.id, AppConstants.messageStatusSent);
      _messageStatusController.add(sent);
      AppLogger.instance.info('File sent to $receiverId: $transferId');
      return sent;
    } catch (e, stackTrace) {
      await StorageService.instance.updateMessageStatus(
          conversationId, message.id, AppConstants.messageStatusFailed);
      _messageStatusController
          .add(message.copyWith(status: AppConstants.messageStatusFailed));
      AppLogger.instance.error('Failed to send file', e, stackTrace);
      throw MessagingException('Failed to send file', e);
    }
  }

  /// Sends a recorded voice message: an audio file streamed like any other
  /// attachment, plus its [durationMs] so the receiver's bubble shows length.
  Future<Message> sendVoice({
    required String receiverId,
    required String receiverIp,
    required File audioFile,
    required int durationMs,
  }) async {
    if (!_isInitialized) {
      throw const MessagingException('Messaging service not initialized');
    }
    if (!CryptoService.instance.canEncryptFor(receiverId)) {
      throw const MessagingException(
          'No public key for peer — cannot send voice message');
    }

    final bytes = await audioFile.readAsBytes();
    final transferId = const Uuid().v4();
    final fileName = audioFile.path.split(RegExp(r'[/\\]')).last;

    await FileService.instance.saveBytes(transferId, fileName, bytes);

    final message = Message.createVoiceMessage(
      senderId: _currentUserId!,
      receiverId: receiverId,
      transferId: transferId,
      fileName: fileName,
      fileSize: bytes.length,
      durationMs: durationMs,
    );
    final conversationId =
        Conversation.generateConversationId(_currentUserId!, receiverId);

    try {
      await StorageService.instance.saveMessage(conversationId, message);
      await _updateConversation(
        peerId: receiverId,
        peerIp: receiverIp,
        lastMessage: '🎤 Voice message',
        isIncoming: false,
      );

      await _sendToPeer(receiverIp, message, receiverId);
      await _sendTransferChunks(receiverId, receiverIp, transferId, bytes);

      final sent = message.copyWith(status: AppConstants.messageStatusSent);
      await StorageService.instance.updateMessageStatus(
          conversationId, message.id, AppConstants.messageStatusSent);
      _messageStatusController.add(sent);
      AppLogger.instance.info('Voice message sent to $receiverId: $transferId');
      return sent;
    } catch (e, stackTrace) {
      await StorageService.instance.updateMessageStatus(
          conversationId, message.id, AppConstants.messageStatusFailed);
      _messageStatusController
          .add(message.copyWith(status: AppConstants.messageStatusFailed));
      AppLogger.instance.error('Failed to send voice message', e, stackTrace);
      throw MessagingException('Failed to send voice message', e);
    }
  }

  Future<void> _sendTransferChunks(String receiverId, String receiverIp,
      String transferId, List<int> bytes) async {
    final chunks =
        FileService.splitIntoChunks(bytes, AppConstants.transferChunkSize);
    for (var i = 0; i < chunks.length; i++) {
      final chunkMessage = Message.createFileChunk(
        senderId: _currentUserId!,
        receiverId: receiverId,
        transferId: transferId,
        index: i,
        total: chunks.length,
        dataBase64: base64.encode(chunks[i]),
      );
      await _sendControlMessage(chunkMessage, receiverId, receiverIp);
    }
    AppLogger.instance
        .debug('Sent ${chunks.length} chunks for $transferId');
  }

  Future<void> _sendToPeer(
      String ipAddress, Message message, String receiverId) async {
    // Mark this peer so the reconnect timer keeps the connection alive.
    ConnectionManager.instance.registerIntendedPeer(ipAddress);

    // Seal the message with AES-GCM under the X25519-derived session key.
    // Requires the peer's public key to have been pinned via discovery.
    if (!CryptoService.instance.canEncryptFor(receiverId)) {
      throw MessagingException(
          'No public key for peer $receiverId — cannot encrypt message');
    }
    final encryptedData = await CryptoService.instance
        .encryptFor(receiverId, jsonEncode(message.toJson()));

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

  Future<void> _handleIncomingPacket(MessagePacket packet) async {
    try {
      final encryptedData = packet.payload['encrypted'] as String?;
      if (encryptedData == null) {
        AppLogger.instance.warning('Received unencrypted message — ignored');
        return;
      }

      if (!CryptoService.instance.canEncryptFor(packet.senderId)) {
        AppLogger.instance.warning(
            'No public key for sender ${packet.senderId} — cannot decrypt');
        return;
      }

      // Decrypt with the AES-GCM session key derived from the sender's pinned
      // public key. AES-GCM also authenticates the message.
      final decryptedString = await CryptoService.instance
          .decryptFrom(packet.senderId, encryptedData);
      final decryptedJson = jsonDecode(decryptedString) as Map<String, dynamic>;

      final message = Message.fromJson(decryptedJson);

      // Control messages (ACKs, read receipts, typing) are not stored as
      // conversation history — they update state and are routed separately.
      if (message.isControlMessage) {
        _handleControlMessage(message);
        return;
      }

      // A real message means the peer is no longer typing — clear it now so
      // the indicator doesn't linger until its timeout.
      TypingService.instance.clearTyping(message.senderId);

      // An attachment bubble arrives before its chunks — register the transfer
      // so the chunks that follow can be matched and reassembled.
      if (message.isAttachment && message.transferId != null) {
        _incomingTransfers[message.transferId!] =
            _IncomingTransfer(message.senderId, isImage: message.isImage)
              ..fileName = message.attachmentName;
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
        lastMessage: _conversationPreview(message),
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
      case AppConstants.messageTypeFileChunk:
        _handleTransferChunk(message);
        break;
      default:
        AppLogger.instance
            .warning('Unknown control message type: ${message.type}');
    }
  }

  /// The conversation-list preview text for a message.
  String _conversationPreview(Message message) {
    if (message.isImage) return '📷 Photo';
    if (message.isVoice) return '🎤 Voice message';
    if (message.isFile) return '📎 ${message.attachmentName ?? 'File'}';
    return message.textContent ?? '';
  }

  /// Accumulates one chunk of an incoming attachment; once every chunk has
  /// arrived, reassembles the bytes, writes them to disk, and notifies listeners.
  Future<void> _handleTransferChunk(Message message) async {
    try {
      final transferId = message.payload['transferId'] as String?;
      final index = (message.payload['index'] as num?)?.toInt();
      final total = (message.payload['total'] as num?)?.toInt();
      final data = message.payload['data'] as String?;
      if (transferId == null || index == null || total == null || data == null) {
        return;
      }

      // Guard against an oversized transfer exhausting memory.
      final maxChunks =
          (AppConstants.maxTransferBytes / AppConstants.transferChunkSize)
                  .ceil() +
              1;
      if (total > maxChunks) {
        AppLogger.instance
            .warning('Rejecting transfer $transferId: too large');
        _incomingTransfers.remove(transferId);
        return;
      }

      // Chunks should only ever arrive after the bubble registered the
      // transfer; if not (unexpected), default to treating it as a file.
      final transfer = _incomingTransfers.putIfAbsent(transferId,
          () => _IncomingTransfer(message.senderId, isImage: false));
      transfer.total = total;
      transfer.chunks[index] = base64.decode(data);

      // Still waiting on the bubble (for the file name) or more chunks.
      if (transfer.fileName == null) return;
      if (transfer.chunks.length < total) return;

      final ordered = [
        for (var i = 0; i < total; i++) transfer.chunks[i] ?? Uint8List(0)
      ];
      final bytes = FileService.reassembleChunks(ordered);
      if (transfer.isImage) {
        await ImageService.instance
            .saveImageBytes(transferId, transfer.fileName!, bytes);
      } else {
        await FileService.instance
            .saveBytes(transferId, transfer.fileName!, bytes);
      }
      _incomingTransfers.remove(transferId);

      _transferReadyController.add(transferId);
      AppLogger.instance.info('Transfer complete: $transferId');
    } catch (e, stackTrace) {
      AppLogger.instance.error('Failed to handle transfer chunk', e, stackTrace);
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

  /// Sends a typing indicator to a peer. Ephemeral, best-effort, not persisted.
  /// The chat screen throttles how often this is called while the user types.
  Future<void> sendTypingIndicator(String receiverId, String receiverIp) async {
    if (!_isInitialized) return;
    final typing = Message.createTypingIndicator(
      senderId: _currentUserId!,
      receiverId: receiverId,
    );
    await _sendControlMessage(typing, receiverId, receiverIp);
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

    if (!CryptoService.instance.canEncryptFor(receiverId)) {
      AppLogger.instance.debug(
          'No public key for $receiverId — skipping ${controlMessage.type} control message');
      return;
    }

    try {
      final encryptedData = await CryptoService.instance
          .encryptFor(receiverId, jsonEncode(controlMessage.toJson()));

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
    _transferReadyController.close();
  }
}
