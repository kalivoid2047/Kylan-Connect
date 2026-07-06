import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/notification_service.dart';

final notificationProvider = StateNotifierProvider<NotificationNotifier, NotificationState>((ref) {
  return NotificationNotifier();
});

class NotificationNotifier extends StateNotifier<NotificationState> {
  NotificationNotifier() : super(NotificationState()) {
    _init();
  }
  
  void _init() {
    NotificationService.instance.onNotification.listen((notification) {
      state = NotificationState(
        notifications: [notification, ...state.notifications],
        unreadCount: state.unreadCount + 1,
      );
    });
  }
  
  void markAsRead(String notificationId) {
    final notifications = state.notifications.map((n) {
      if (n.id == notificationId) {
        // Mark as read (you'd add an isRead field to AppNotification in production)
        return n;
      }
      return n;
    }).toList();
    
    state = NotificationState(
      notifications: notifications,
      unreadCount: state.unreadCount > 0 ? state.unreadCount - 1 : 0,
    );
  }
  
  void clearAll() {
    state = NotificationState();
    NotificationService.instance.clearNotifications();
  }
  
  void setEnabled(bool enabled) {
    NotificationService.instance.setEnabled(enabled);
  }
}

class NotificationState {
  final List<AppNotification> notifications;
  final int unreadCount;
  
  NotificationState({
    List<AppNotification>? notifications,
    this.unreadCount = 0,
  }) : notifications = notifications ?? [];
}
