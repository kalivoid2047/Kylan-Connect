import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:kylan_connect/services/discovery_service.dart';
import 'package:kylan_connect/services/connection_manager.dart';
import 'package:kylan_connect/services/messaging_service.dart';
import 'package:kylan_connect/services/storage_service.dart';
import 'package:kylan_connect/models/message.dart';
import 'package:kylan_connect/core/constants/app_constants.dart';

/// Integration test that simulates two instances of the app
/// discovering each other and exchanging messages.
void main() {
  late DiscoveryService discoveryService1;
  late DiscoveryService discoveryService2;
  late ConnectionManager connectionManager1;
  late MessagingService messagingService1;
  late MessagingService messagingService2;
  late Directory tempDir;

  setUpAll(() async {
    // Peer services now ensure an X25519 keypair on init, backed by Hive.
    tempDir = Directory.systemTemp.createTempSync('kylan_two_instance_test');
    await StorageService.instance.initializeForTest(tempDir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  setUp(() {
    discoveryService1 = DiscoveryService.instance;
    discoveryService2 = DiscoveryService.instance;
    connectionManager1 = ConnectionManager.instance;
    messagingService1 = MessagingService.instance;
    messagingService2 = MessagingService.instance;
  });

  tearDown(() async {
    await discoveryService1.stopDiscovery();
    await connectionManager1.stopServer();
    messagingService1.dispose();
  });

  group('Two Instance Integration', () {
    test('should initialize both instances', () async {
      // Instance 1
      await discoveryService1.initialize(
        deviceId: 'device-1',
        deviceName: 'Device One',
        avatarColor: '#FF6B6B',
      );

      await messagingService1.initialize('device-1');

      // Instance 2 would be a separate instance in a real scenario
      // For testing, we simulate the initialization
      await discoveryService2.initialize(
        deviceId: 'device-2',
        deviceName: 'Device Two',
        avatarColor: '#4ECDC4',
      );

      await messagingService2.initialize('device-2');

      expect(discoveryService1.isRunning, false);
      expect(messagingService1.isInitialized, true);
      expect(messagingService2.isInitialized, true);
    });

    test('should create and validate messages between instances', () async {
      await messagingService1.initialize('device-1');
      await messagingService2.initialize('device-2');

      // Create a message from instance 1 to instance 2
      final message = Message.createTextMessage(
        senderId: 'device-1',
        receiverId: 'device-2',
        text: 'Hello from device 1',
      );

      expect(message.senderId, equals('device-1'));
      expect(message.receiverId, equals('device-2'));
      expect(message.textContent, equals('Hello from device 1'));

      // Create delivery ACK from instance 2
      final ack = Message.createDeliveryAck(
        senderId: 'device-2',
        receiverId: 'device-1',
        originalMessageId: message.id,
      );

      expect(ack.type, equals(AppConstants.messageTypeDeliveryAck));
      expect(ack.originalMessageId, equals(message.id));

      // Create read receipt from instance 2
      final readReceipt = Message.createReadReceipt(
        senderId: 'device-2',
        receiverId: 'device-1',
        originalMessageId: message.id,
      );

      expect(readReceipt.type, equals(AppConstants.messageTypeReadReceipt));
      expect(readReceipt.originalMessageId, equals(message.id));
    });

    test('should handle message serialization between instances', () async {
      await messagingService1.initialize('device-1');
      await messagingService2.initialize('device-2');

      final originalMessage = Message.createTextMessage(
        senderId: 'device-1',
        receiverId: 'device-2',
        text: 'Test message',
      );

      // Serialize
      final json = originalMessage.toJson();

      // Deserialize (simulating receiving on instance 2)
      final receivedMessage = Message.fromJson(json);

      expect(receivedMessage.id, equals(originalMessage.id));
      expect(receivedMessage.senderId, equals(originalMessage.senderId));
      expect(receivedMessage.receiverId, equals(originalMessage.receiverId));
      expect(receivedMessage.textContent, equals(originalMessage.textContent));
    });

    test('should manage peer connections', () async {
      await discoveryService1.initialize(
        deviceId: 'device-1',
        deviceName: 'Device One',
        avatarColor: '#FF6B6B',
      );

      await connectionManager1.startServer();

      // Register peer for connection management
      connectionManager1.registerIntendedPeer('192.168.1.100');

      expect(connectionManager1.isRunning, true);
      expect(connectionManager1.isConnectedTo('192.168.1.100'), false);

      await connectionManager1.stopServer();
    });
  });

  group('Message Flow Simulation', () {
    test('should simulate complete message flow', () async {
      // Initialize both instances
      await messagingService1.initialize('device-1');
      await messagingService2.initialize('device-2');

      // Step 1: Device 1 sends a message
      final sentMessage = Message.createTextMessage(
        senderId: 'device-1',
        receiverId: 'device-2',
        text: 'Hello!',
      );

      expect(sentMessage.status, equals(AppConstants.messageStatusSending));

      // Step 2: Message is sent (status updated)
      final sentUpdated = sentMessage.copyWith(
        status: AppConstants.messageStatusSent,
      );
      expect(sentUpdated.status, equals(AppConstants.messageStatusSent));

      // Step 3: Device 2 receives message (status delivered)
      final deliveredMessage = sentUpdated.copyWith(
        status: AppConstants.messageStatusDelivered,
      );
      expect(deliveredMessage.status, equals(AppConstants.messageStatusDelivered));

      // Step 4: Device 2 sends delivery ACK
      final ack = Message.createDeliveryAck(
        senderId: 'device-2',
        receiverId: 'device-1',
        originalMessageId: sentMessage.id,
      );
      expect(ack.isControlMessage, isTrue);

      // Step 5: Device 1 reads message
      final readReceipt = Message.createReadReceipt(
        senderId: 'device-1',
        receiverId: 'device-2',
        originalMessageId: sentMessage.id,
      );
      expect(readReceipt.isControlMessage, isTrue);
    });
  });
}
