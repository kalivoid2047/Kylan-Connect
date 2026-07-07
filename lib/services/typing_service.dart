import 'dart:async';
import '../core/constants/app_constants.dart';
import '../models/message.dart';
import '../core/utils/app_logger.dart';

/// Tracks which peers are currently typing.
///
/// Typing indicators are ephemeral control messages that are never persisted.
/// The receive side lives here: [MessagingService] routes incoming `typing`
/// control packets to [handleTypingIndicator], which emits on the streams and
/// auto-clears after [_typingTimeout] if no fresh indicator arrives. The send
/// side lives in [MessagingService] (it owns encryption and connections).
class TypingService {
  static final TypingService _instance = TypingService._internal();
  static TypingService get instance => _instance;

  final StreamController<String> _typingStartedController =
      StreamController.broadcast();
  final StreamController<String> _typingStoppedController =
      StreamController.broadcast();

  final Map<String, Timer> _typingTimers = {};

  /// A peer is considered "still typing" for this long after their last
  /// indicator. Senders re-emit more frequently than this to keep it alive.
  static const Duration _typingTimeout = Duration(seconds: 4);

  TypingService._internal();

  /// Emits the deviceId of a peer that just started (or is still) typing.
  Stream<String> get onTypingStarted => _typingStartedController.stream;

  /// Emits the deviceId of a peer that stopped typing (timed out).
  Stream<String> get onTypingStopped => _typingStoppedController.stream;

  /// Handles an incoming typing control message: marks the sender as typing
  /// and (re)arms the auto-clear timer.
  void handleTypingIndicator(Message message) {
    if (message.type != AppConstants.messageTypeTyping) return;

    final senderId = message.senderId;
    _typingTimers[senderId]?.cancel();

    _typingStartedController.add(senderId);
    AppLogger.instance.debug('Peer started typing: $senderId');

    _typingTimers[senderId] = Timer(_typingTimeout, () {
      _typingTimers.remove(senderId);
      _typingStoppedController.add(senderId);
      AppLogger.instance.debug('Peer stopped typing: $senderId');
    });
  }

  /// Immediately clears the typing state for a peer (e.g. when a real message
  /// arrives, so the indicator doesn't linger).
  void clearTyping(String senderId) {
    final timer = _typingTimers.remove(senderId);
    if (timer != null) {
      timer.cancel();
      _typingStoppedController.add(senderId);
    }
  }

  bool isPeerTyping(String senderId) => _typingTimers.containsKey(senderId);

  void dispose() {
    for (final timer in _typingTimers.values) {
      timer.cancel();
    }
    _typingTimers.clear();
    _typingStartedController.close();
    _typingStoppedController.close();
  }
}
