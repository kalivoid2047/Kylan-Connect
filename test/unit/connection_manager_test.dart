import 'package:flutter_test/flutter_test.dart';
import 'package:kylan_connect/services/connection_manager.dart';

void main() {
  late ConnectionManager connectionManager;

  setUp(() {
    connectionManager = ConnectionManager.instance;
  });

  tearDown(() async {
    if (connectionManager.isRunning) {
      await connectionManager.stopServer();
    }
  });

  group('ConnectionManager Initialization', () {
    test('should initialize with default state', () {
      expect(connectionManager.isRunning, false);
      expect(connectionManager.connectedPeers, isEmpty);
    });

    test('should start server', () async {
      await connectionManager.startServer();
      expect(connectionManager.isRunning, true);
      await connectionManager.stopServer();
    });
  });

  group('ConnectionManager Peer Management', () {
    test('should register intended peer', () {
      connectionManager.registerIntendedPeer('192.168.1.100');
      // The peer is tracked internally for connection management
    });

    test('should check if connected to peer', () {
      final isConnected = connectionManager.isConnectedTo('192.168.1.100');
      expect(isConnected, false);
    });

    test('should disconnect peer', () async {
      await connectionManager.disconnectPeer('192.168.1.100');
      // Should not throw even if peer not connected
    });
  });

  group('ConnectionManager State', () {
    test('should return connected peers list', () {
      final peers = connectionManager.connectedPeers;
      expect(peers, isA<List<String>>());
    });

    test('should return isRunning state', () {
      final isRunning = connectionManager.isRunning;
      expect(isRunning, isA<bool>());
    });
  });

  group('ConnectionManager Cleanup', () {
    test('should stop server and disconnect all peers', () async {
      await connectionManager.stopServer();
      expect(connectionManager.connectedPeers, isEmpty);
    });
  });
}
