import 'dart:async';
import '../models/message.dart';
import '../core/utils/app_logger.dart';

/// Service for managing typing indicators.
/// Typing indicators are control messages that don't persist in storage
/// and are only shown while the user is actively typing.
class TypingService {
  static final TypingService _instance = TypingService._internal();
  static TypingService get instance => _instance;

  final StreamController<String> _typingStartedController =
      StreamController.broadcast();
  final StreamController<String> _typingStoppedController =
      StreamController.broadcast();

  final Map<String, Timer> _typingTimers = {};
  static const Duration _typingTimeout = Duration(seconds: 3);

  String? _currentUserId;
  bool _isInitialized = false;

  TypingService._internal();

  Stream<String> get onTypingStarted => _typingStartedController.stream;
  Stream<String> get onTypingStopped => _typingStoppedController.stream;

  Future<void> initialize(String userId) async {
    _currentUserId = userId;
    _isInitialized = true;
    AppLogger.instance.info('Typing service initialized for user: $userId');
  }

  /// Send a typing indicator to a peer.
  /// This should be called when the user starts typing in a conversation.
  Future<void> sendTypingIndicator(String receiverId) async {
    if (!_isInitialized || _currentUserId == null) {
      AppLogger.instance.warning('Typing service not initialized');
      return;
    }

    try {
      final typingMessage = Message.createTypingIndicator(
        senderId: _currentUserId!,
        receiverId: receiverId,
      );

      // Send directly through messaging service without storing
      // Typing indicators are ephemeral control messages
      await _sendControlMessage(typingMessage, receiverId);

      AppLogger.instance.debug('Sent typing indicator to: $receiverId');
    } catch (e, stackTrace) {
      AppLogger.instance
          .error('Failed to send typing indicator', e, stackTrace);
    }
  }

  /// Handle a received typing indicator.
  void handleTypingIndicator(Message message) {
    if (!message.isControlMessage || message.type != 'typing') {
      return;
    }

    final senderId = message.senderId;

    // Cancel existing timer for this sender
    _typingTimers[senderId]?.cancel();

    // Emit typing started event
    _typingStartedController.add(senderId);
    AppLogger.instance.debug('Peer started typing: $senderId');

    // Set timeout to clear typing indicator
    _typingTimers[senderId] = Timer(_typingTimeout, () {
      _typingStoppedController.add(senderId);
      _typingTimers.remove(senderId);
      AppLogger.instance.debug('Peer stopped typing: $senderId');
    });
  }

  /// Stop typing indicator for a specific peer.
  void stopTyping(String senderId) {
    _typingTimers[senderId]?.cancel();
    _typingTimers.remove(senderId);
    _typingStoppedController.add(senderId);
  }

  /// Check if a peer is currently typing.
  bool isPeerTyping(String senderId) {
    return _typingTimers.containsKey(senderId);
  }

  Future<void> _sendControlMessage(Message message, String receiverIp) async {
    // This would typically go through ConnectionManager directly
    // since control messages shouldn't be stored
    // For now, we'll use a simplified approach
    AppLogger.instance.debug('Control message would be sent to $receiverIp');
  }

  void dispose() {
    for (final timer in _typingTimers.values) {
      timer.cancel();
    }
    _typingTimers.clear();
    _typingStartedController.close();
    _typingStoppedController.close();
  }
}
