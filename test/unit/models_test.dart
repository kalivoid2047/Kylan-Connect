import 'package:flutter_test/flutter_test.dart';
import 'package:kylan_connect/models/user_profile.dart';
import 'package:kylan_connect/models/peer_device.dart';
import 'package:kylan_connect/models/message.dart';
import 'package:kylan_connect/models/conversation.dart';

void main() {
  group('UserProfile', () {
    test('should create UserProfile with valid data', () {
      final profile = UserProfile(
        deviceId: 'test-id',
        displayName: 'Test User',
        avatarColor: '#FF0000',
        createdAt: DateTime(2024, 1, 1),
        lastUpdated: DateTime(2024, 1, 1),
      );

      expect(profile.deviceId, equals('test-id'));
      expect(profile.displayName, equals('Test User'));
      expect(profile.avatarColor, equals('#FF0000'));
    });

    test('should copy UserProfile with updated values', () {
      final profile = UserProfile(
        deviceId: 'test-id',
        displayName: 'Test User',
        avatarColor: '#FF0000',
        createdAt: DateTime(2024, 1, 1),
        lastUpdated: DateTime(2024, 1, 1),
      );

      final updated = profile.copyWith(displayName: 'Updated User');

      expect(updated.displayName, equals('Updated User'));
      expect(updated.deviceId, equals(profile.deviceId));
    });
  });

  group('PeerDevice', () {
    test('should create PeerDevice with valid data', () {
      final peer = PeerDevice(
        deviceId: 'peer-id',
        displayName: 'Peer User',
        ipAddress: '192.168.1.2',
        platform: 'android',
        appVersion: '1.0.0',
        avatarColor: '#00FF00',
        isOnline: true,
        lastSeen: DateTime.now(),
      );

      expect(peer.deviceId, equals('peer-id'));
      expect(peer.displayName, equals('Peer User'));
      expect(peer.isOnline, isTrue);
    });

    test('should identify expired peer', () {
      final oldTime = DateTime.now().subtract(const Duration(seconds: 20));
      final peer = PeerDevice(
        deviceId: 'peer-id',
        displayName: 'Peer User',
        ipAddress: '192.168.1.2',
        platform: 'android',
        appVersion: '1.0.0',
        avatarColor: '#00FF00',
        isOnline: true,
        lastSeen: oldTime,
      );

      expect(peer.isExpired, isTrue);
    });
  });

  group('Message', () {
    test('should create text message', () {
      final message = Message.createTextMessage(
        senderId: 'sender-id',
        receiverId: 'receiver-id',
        text: 'Hello',
      );

      expect(message.type, equals('text'));
      expect(message.textContent, equals('Hello'));
      expect(message.status, equals('sending'));
    });

    test('should copy Message with updated status', () {
      final message = Message.createTextMessage(
        senderId: 'sender-id',
        receiverId: 'receiver-id',
        text: 'Hello',
      );

      final updated = message.copyWith(status: 'delivered');

      expect(updated.status, equals('delivered'));
      expect(updated.id, equals(message.id));
    });
  });

  group('Conversation', () {
    test('should generate consistent conversation ID', () {
      final id1 = Conversation.generateConversationId('user1', 'user2');
      final id2 = Conversation.generateConversationId('user2', 'user1');

      expect(id1, equals(id2));
    });

    test('should create Conversation with valid data', () {
      final conversation = Conversation(
        conversationId: 'conv-id',
        participantId: 'participant-id',
        participantName: 'Participant',
        participantAvatarColor: '#0000FF',
        lastMessage: 'Last message',
        lastMessageTime: DateTime.now(),
        unreadCount: 5,
      );

      expect(conversation.participantId, equals('participant-id'));
      expect(conversation.unreadCount, equals(5));
    });
  });
}
