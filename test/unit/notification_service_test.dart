import 'package:flutter_test/flutter_test.dart';
import 'package:kylan_connect/models/message.dart';
import 'package:kylan_connect/services/notification_service.dart';

void main() {
  final service = NotificationService.instance;

  setUp(() {
    service.clearNotifications();
    service.setEnabled(true);
    service.setActiveConversation(null);
  });

  Message text(String body) => Message.createTextMessage(
        senderId: 'peer-1',
        receiverId: 'me',
        text: body,
      );

  test('records a text message notification with the message body', () {
    service.showNewMessageNotification(text('hello there'), 'Alice');

    expect(service.notifications, hasLength(1));
    final n = service.notifications.first;
    expect(n.title, equals('Alice'));
    expect(n.body, equals('hello there'));
    expect(n.type, equals(NotificationType.newMessage));
  });

  test('previews attachments instead of showing an empty body', () {
    service.showNewMessageNotification(
      Message.createImageMessage(
        senderId: 'p',
        receiverId: 'me',
        transferId: 't',
        thumbnailBase64: 'AAAA',
        fileName: 'pic.jpg',
        fileSize: 1,
        width: 1,
        height: 1,
      ),
      'Bob',
    );
    expect(service.notifications.first.body, equals('📷 Photo'));

    service.showNewMessageNotification(
      Message.createVoiceMessage(
        senderId: 'p',
        receiverId: 'me',
        transferId: 't',
        fileName: 'v.m4a',
        fileSize: 1,
        durationMs: 1000,
      ),
      'Bob',
    );
    expect(service.notifications.first.body, equals('🎤 Voice message'));

    service.showNewMessageNotification(
      Message.createFileMessage(
        senderId: 'p',
        receiverId: 'me',
        transferId: 't',
        fileName: 'report.pdf',
        fileSize: 1,
      ),
      'Bob',
    );
    expect(service.notifications.first.body, equals('📎 report.pdf'));
  });

  test('respects the enabled flag', () {
    service.setEnabled(false);
    service.showNewMessageNotification(text('ignored'), 'Alice');
    expect(service.notifications, isEmpty);
  });

  test('setActiveConversation does not throw and still records in-app', () {
    // OS notifications are suppressed for the active chat, but the in-app
    // list should still capture the message.
    service.setActiveConversation('peer-1');
    service.showNewMessageNotification(text('while viewing'), 'Alice');
    expect(service.notifications, hasLength(1));
  });
}
