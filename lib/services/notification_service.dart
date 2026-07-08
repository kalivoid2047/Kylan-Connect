import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    hide Message;
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

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _systemReady = false;

  /// The peer whose chat is currently open. Incoming messages from this peer
  /// don't raise an OS notification (the user is already looking at them).
  String? _activePeerId;

  static const String _messagesChannelId = 'messages';
  static const String _messagesChannelName = 'Messages';

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

  /// Marks which conversation is on screen so we can suppress its OS
  /// notifications. Pass null when leaving a chat.
  void setActiveConversation(String? peerId) => _activePeerId = peerId;

  /// Initializes the platform notification plugin and requests permission.
  /// Safe to call on platforms without support — it degrades to in-app only.
  Future<void> initialize() async {
    if (_systemReady) return;
    try {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwin = DarwinInitializationSettings();
      const linux =
          LinuxInitializationSettings(defaultActionName: 'Open');
      const settings = InitializationSettings(
        android: android,
        iOS: darwin,
        macOS: darwin,
        linux: linux,
      );
      await _plugin.initialize(settings);

      final android_ = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android_?.createNotificationChannel(
        const AndroidNotificationChannel(
          _messagesChannelId,
          _messagesChannelName,
          description: 'New message notifications',
          importance: Importance.high,
        ),
      );
      await android_?.requestNotificationsPermission();

      await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);

      _systemReady = true;
      AppLogger.instance.info('Local notifications initialized');
    } catch (e, stackTrace) {
      AppLogger.instance
          .warning('Local notifications unavailable on this platform: $e');
      AppLogger.instance.debug('Notification init error: $stackTrace');
    }
  }

  void showNewMessageNotification(Message message, String senderName) {
    if (!_isEnabled) return;

    final preview = message.previewText;

    final notification = AppNotification(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: NotificationType.newMessage,
      title: senderName,
      body: preview,
      timestamp: DateTime.now(),
      data: {'messageId': message.id, 'senderId': message.senderId},
    );

    _addNotification(notification);
    AppLogger.instance.debug('New message notification: $senderName');

    // Raise an OS notification unless the user is already viewing this chat.
    if (message.senderId != _activePeerId) {
      unawaited(_showSystemNotification(
        message.senderId.hashCode & 0x7fffffff,
        senderName,
        preview,
      ));
    }
  }

  Future<void> _showSystemNotification(int id, String title, String body) async {
    if (!_systemReady) return;
    try {
      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          _messagesChannelId,
          _messagesChannelName,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
        macOS: DarwinNotificationDetails(),
      );
      await _plugin.show(id, title, body, details);
    } catch (e) {
      AppLogger.instance.debug('Failed to show system notification: $e');
    }
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
