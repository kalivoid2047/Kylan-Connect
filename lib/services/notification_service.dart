import 'dart:async';
import '../models/message.dart';
import '../models/peer_device.dart';
import '../core/utils/app_logger.dart';

enum NotificationType {
  newMessage,
  deviceJoined,
  deviceLeft,
  connectionError,
}

class AppNotification {
  final String id;
  final NotificationType type;
  final String title;
  final String body;
  final DateTime timestamp;
  final Map<String, dynamic>? data;

  AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.timestamp,
    this.data,
  });
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  static NotificationService get instance => _instance;

  final StreamController<AppNotification> _notificationController =
      StreamController.broadcast();
  final List<AppNotification> _notifications = [];

  bool _isEnabled = true;

  NotificationService._internal();

  Stream<AppNotification> get onNotification => _notificationController.stream;
  List<AppNotification> get notifications => List.unmodifiable(_notifications);
  bool get isEnabled => _isEnabled;

  void setEnabled(bool enabled) {
    _isEnabled = enabled;
    AppLogger.instance
        .info('Notifications ${enabled ? "enabled" : "disabled"}');
  }

  void showNewMessageNotification(Message message, String senderName) {
    if (!_isEnabled) return;

    final notification = AppNotification(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: NotificationType.newMessage,
      title: senderName,
      body: message.textContent ?? '',
      timestamp: DateTime.now(),
      data: {'messageId': message.id, 'senderId': message.senderId},
    );

    _addNotification(notification);
    AppLogger.instance.debug('New message notification: $senderName');
  }

  void showDeviceJoinedNotification(PeerDevice peer) {
    if (!_isEnabled) return;

    final notification = AppNotification(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: NotificationType.deviceJoined,
      title: 'Device Joined',
      body: '${peer.displayName} has joined the network',
      timestamp: DateTime.now(),
      data: {'deviceId': peer.deviceId},
    );

    _addNotification(notification);
    AppLogger.instance.debug('Device joined notification: ${peer.displayName}');
  }

  void showDeviceLeftNotification(String deviceId, String deviceName) {
    if (!_isEnabled) return;

    final notification = AppNotification(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: NotificationType.deviceLeft,
      title: 'Device Left',
      body: '$deviceName has left the network',
      timestamp: DateTime.now(),
      data: {'deviceId': deviceId},
    );

    _addNotification(notification);
    AppLogger.instance.debug('Device left notification: $deviceName');
  }

  void showConnectionErrorNotification(String message) {
    if (!_isEnabled) return;

    final notification = AppNotification(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: NotificationType.connectionError,
      title: 'Connection Error',
      body: message,
      timestamp: DateTime.now(),
    );

    _addNotification(notification);
    AppLogger.instance.debug('Connection error notification: $message');
  }

  void _addNotification(AppNotification notification) {
    _notifications.insert(0, notification);

    // Keep only last 50 notifications
    if (_notifications.length > 50) {
      _notifications.removeLast();
    }

    _notificationController.add(notification);
  }

  void clearNotifications() {
    _notifications.clear();
    AppLogger.instance.debug('Notifications cleared');
  }

  void removeNotification(String id) {
    _notifications.removeWhere((n) => n.id == id);
    AppLogger.instance.debug('Notification removed: $id');
  }

  void dispose() {
    _notificationController.close();
  }
}
