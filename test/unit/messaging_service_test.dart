import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:kylan_connect/services/messaging_service.dart';
import 'package:kylan_connect/services/storage_service.dart';
import 'package:kylan_connect/models/message.dart';
import 'package:kylan_connect/core/constants/app_constants.dart';

void main() {
  late MessagingService messagingService;
  late Directory tempDir;

  setUpAll(() async {
    // Storage-backed operations need an initialized Hive; use a temp dir so
    // no platform channels (path_provider) are required in unit tests.
    tempDir = Directory.systemTemp.createTempSync('kylan_msg_test');
    await StorageService.instance.initializeForTest(tempDir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  setUp(() {
    messagingService = MessagingService.instance;
  });

  tearDown(() async {
    messagingService.dispose();
  });

  group('MessagingService Initialization', () {
    test('should initialize with default state', () {
      expect(messagingService.isInitialized, false);
    });

    test('should initialize with user ID', () async {
      await messagingService.initialize('test-user-1');
      expect(messagingService.isInitialized, true);
    });
  });

  group('MessagingService Streams', () {
    test('should provide message received stream', () {
      final stream = messagingService.onMessageReceived;
      expect(stream, isA<Stream<Message>>());
    });

    test('should provide message status changed stream', () {
      final stream = messagingService.onMessageStatusChanged;
      expect(stream, isA<Stream<Message>>());
    });
  });

  group('Message Model', () {
    test('should create text message', () {
      final message = Message.createTextMessage(
        senderId: 'user-1',
        receiverId: 'user-2',
        text: 'Hello, World!',
      );

      expect(message.type, equals(AppConstants.messageTypeText));
      expect(message.senderId, equals('user-1'));
      expect(message.receiverId, equals('user-2'));
      expect(message.textContent, equals('Hello, World!'));
      expect(message.status, equals(AppConstants.messageStatusSending));
    });

    test('should create delivery ACK message', () {
      final message = Message.createDeliveryAck(
        senderId: 'user-1',
        receiverId: 'user-2',
        originalMessageId: 'msg-123',
      );

      expect(message.type, equals(AppConstants.messageTypeDeliveryAck));
      expect(message.originalMessageId, equals('msg-123'));
      expect(message.isControlMessage, isTrue);
    });

    test('should create read receipt message', () {
      final message = Message.createReadReceipt(
        senderId: 'user-1',
        receiverId: 'user-2',
        originalMessageId: 'msg-456',
      );

      expect(message.type, equals(AppConstants.messageTypeReadReceipt));
      expect(message.originalMessageId, equals('msg-456'));
      expect(message.isControlMessage, isTrue);
    });

    test('should identify control messages', () {
      final textMessage = Message.createTextMessage(
        senderId: 'user-1',
        receiverId: 'user-2',
        text: 'Hello',
      );

      final ackMessage = Message.createDeliveryAck(
        senderId: 'user-1',
        receiverId: 'user-2',
        originalMessageId: 'msg-123',
      );

      expect(textMessage.isControlMessage, isFalse);
      expect(ackMessage.isControlMessage, isTrue);
    });

    test('should copy message with new status', () {
      final message = Message.createTextMessage(
        senderId: 'user-1',
        receiverId: 'user-2',
        text: 'Hello',
      );

      final updated = message.copyWith(status: AppConstants.messageStatusSent);
      expect(updated.status, equals(AppConstants.messageStatusSent));
      expect(updated.id, equals(message.id));
    });

    test('should serialize and deserialize message', () {
      final message = Message.createTextMessage(
        senderId: 'user-1',
        receiverId: 'user-2',
        text: 'Test message',
      );

      final json = message.toJson();
      final deserialized = Message.fromJson(json);

      expect(deserialized.id, equals(message.id));
      expect(deserialized.type, equals(message.type));
      expect(deserialized.senderId, equals(message.senderId));
      expect(deserialized.receiverId, equals(message.receiverId));
      expect(deserialized.textContent, equals(message.textContent));
    });
  });

  group('MessagingService Message Operations', () {
    test('should mark conversation as read', () async {
      await messagingService.initialize('test-user-1');
      // This should not throw
      await messagingService.markAsRead('conv-123');
    });

    test('should delete message', () async {
      await messagingService.initialize('test-user-1');
      // This should not throw even if message doesn't exist
      await messagingService.deleteMessage('conv-123', 'msg-456');
    });
  });
}
