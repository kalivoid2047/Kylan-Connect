import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:kylan_connect/models/discovery_packet.dart';
import 'package:kylan_connect/models/peer_device.dart';
import 'package:kylan_connect/services/discovery_service.dart';
import 'package:kylan_connect/services/storage_service.dart';

void main() {
  late DiscoveryService discoveryService;
  late Directory tempDir;

  setUpAll(() async {
    // Discovery now ensures the device's X25519 keypair on init, which needs
    // an initialized Hive keys box.
    tempDir = Directory.systemTemp.createTempSync('kylan_disc_test');
    await StorageService.instance.initializeForTest(tempDir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  setUp(() async {
    discoveryService = DiscoveryService.instance;
    // Return the singleton to a clean, uninitialized state before each test.
    await discoveryService.resetForTest();
  });

  tearDown(() async {
    if (discoveryService.isRunning) {
      await discoveryService.stopDiscovery();
    }
  });

  group('DiscoveryService Initialization', () {
    test('should initialize with valid parameters', () async {
      await discoveryService.initialize(
        deviceId: 'test-device-1',
        deviceName: 'Test Device',
        avatarColor: '#FF6B6B',
      );

      expect(discoveryService.isRunning, false);
    });

    test('should throw exception if not initialized before starting', () async {
      await expectLater(
        discoveryService.startDiscovery(),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('DiscoveryService Peer Management', () {
    test('should return null for non-existent peer', () {
      final peer = discoveryService.getPeer('non-existent-id');
      expect(peer, isNull);
    });

    test('should remove peer', () {
      discoveryService.removePeer('test-id');
      expect(discoveryService.getPeer('test-id'), isNull);
    });
  });

  group('DiscoveryPacket Serialization', () {
    test('should serialize and deserialize correctly', () {
      final packet = DiscoveryPacket(
        deviceId: 'test-device-1',
        deviceName: 'Test Device',
        ipAddress: '192.168.1.100',
        platform: 'ios',
        appVersion: '1.0.0',
        avatarColor: '#FF6B6B',
        timestamp: DateTime(2024, 1, 1, 12, 0, 0),
      );

      final json = packet.toJson();
      final deserialized = DiscoveryPacket.fromJson(json);

      expect(deserialized.deviceId, equals(packet.deviceId));
      expect(deserialized.deviceName, equals(packet.deviceName));
      expect(deserialized.ipAddress, equals(packet.ipAddress));
      expect(deserialized.platform, equals(packet.platform));
      expect(deserialized.appVersion, equals(packet.appVersion));
      expect(deserialized.avatarColor, equals(packet.avatarColor));
    });

    test('should handle JSON encoding/decoding', () {
      final packet = DiscoveryPacket(
        deviceId: 'test-device-1',
        deviceName: 'Test Device',
        ipAddress: '192.168.1.100',
        platform: 'android',
        appVersion: '1.0.0',
        avatarColor: '#4ECDC4',
        timestamp: DateTime(2024, 1, 1, 12, 0, 0),
      );

      final jsonString = jsonEncode(packet.toJson());
      final jsonMap = jsonDecode(jsonString) as Map<String, dynamic>;
      final deserialized = DiscoveryPacket.fromJson(jsonMap);

      expect(deserialized.deviceId, equals(packet.deviceId));
      expect(deserialized.deviceName, equals(packet.deviceName));
    });
  });

  group('PeerDevice Model', () {
    test('should create peer device correctly', () {
      final peer = PeerDevice(
        deviceId: 'peer-1',
        displayName: 'Peer One',
        ipAddress: '192.168.1.101',
        platform: 'ios',
        appVersion: '1.0.0',
        avatarColor: '#45B7D1',
        isOnline: true,
        lastSeen: DateTime.now(),
      );

      expect(peer.deviceId, equals('peer-1'));
      expect(peer.displayName, equals('Peer One'));
      expect(peer.isOnline, isTrue);
    });

    test('should calculate time since last seen correctly', () {
      final now = DateTime.now();
      final peer = PeerDevice(
        deviceId: 'peer-1',
        displayName: 'Peer One',
        ipAddress: '192.168.1.101',
        platform: 'ios',
        appVersion: '1.0.0',
        avatarColor: '#45B7D1',
        isOnline: true,
        lastSeen: now.subtract(const Duration(seconds: 30)),
      );

      final difference = now.difference(peer.lastSeen);
      expect(difference.inSeconds, equals(30));
    });
  });

  group('DiscoveryService Streams', () {
    test('should emit peer discovered event', () async {
      await discoveryService.initialize(
        deviceId: 'test-device-1',
        deviceName: 'Test Device',
        avatarColor: '#FF6B6B',
      );

      final peerStream = discoveryService.onPeerDiscovered;
      expect(peerStream, isA<Stream<PeerDevice>>());
    });

    test('should emit peer left event', () async {
      await discoveryService.initialize(
        deviceId: 'test-device-1',
        deviceName: 'Test Device',
        avatarColor: '#FF6B6B',
      );

      final peerLeftStream = discoveryService.onPeerLeft;
      expect(peerLeftStream, isA<Stream<String>>());
    });
  });
}
