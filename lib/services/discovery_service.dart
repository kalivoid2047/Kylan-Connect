import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../core/constants/app_constants.dart';
import '../core/constants/network_constants.dart';
import '../core/errors/exceptions.dart';
import '../core/security/crypto_service.dart';
import '../models/discovery_packet.dart';
import '../models/peer_device.dart';
import '../services/storage_service.dart';
import '../core/utils/app_logger.dart';

class DiscoveryService {
  static final DiscoveryService _instance = DiscoveryService._internal();
  static DiscoveryService get instance => _instance;

  RawDatagramSocket? _socket;
  Timer? _broadcastTimer;
  Timer? _cleanupTimer;
  StreamSubscription<RawSocketEvent>? _socketSubscription;

  final Map<String, PeerDevice> _activePeers = {};
  final StreamController<PeerDevice> _peerDiscoveredController =
      StreamController.broadcast();
  final StreamController<String> _peerLeftController =
      StreamController.broadcast();

  List<String> _localIpAddresses = [];
  String? _deviceId;
  String? _deviceName;
  String? _avatarColor;

  bool _isRunning = false;

  DiscoveryService._internal();

  Stream<PeerDevice> get onPeerDiscovered => _peerDiscoveredController.stream;
  Stream<String> get onPeerLeft => _peerLeftController.stream;
  List<PeerDevice> get activePeers => _activePeers.values.toList();
  bool get isRunning => _isRunning;

  Future<void> initialize({
    required String deviceId,
    required String deviceName,
    required String avatarColor,
  }) async {
    _deviceId = deviceId;
    _deviceName = deviceName;
    _avatarColor = avatarColor;

    try {
      // Make sure our X25519 identity keypair exists before we broadcast it.
      await CryptoService.instance.ensureIdentityKeys();

      _localIpAddresses = await _getLocalIpAddresses();

      if (_localIpAddresses.isEmpty) {
        throw const DiscoveryException('Could not determine local IP address');
      }

      AppLogger.instance
          .info('Discovery service initialized with IPs: $_localIpAddresses');
    } catch (e, stackTrace) {
      AppLogger.instance
          .error('Failed to initialize discovery service', e, stackTrace);
      throw DiscoveryException('Failed to initialize discovery service', e);
    }
  }

  Future<List<String>> _getLocalIpAddresses() async {
    try {
      final ipAddresses = <String>[];
      final interfaces = await NetworkInterface.list(
          includeLoopback: false, type: InternetAddressType.IPv4);

      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            ipAddresses.add(addr.address);
          }
        }
      }

      return ipAddresses;
    } catch (e) {
      AppLogger.instance.warning('Failed to get local IP addresses: $e');
      return [];
    }
  }

  Future<void> startDiscovery() async {
    if (_isRunning) {
      AppLogger.instance.warning('Discovery service already running');
      return;
    }

    if (_deviceId == null || _deviceName == null || _avatarColor == null) {
      throw const DiscoveryException(
          'Discovery service not initialized. Call initialize() first.');
    }

    try {
      _socket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4, AppConstants.discoveryPort);
      _socket!.broadcastEnabled = NetworkConstants.enableBroadcast;

      _socketSubscription = _socket!.listen(_handleSocketEvent);

      _broadcastTimer = Timer.periodic(
        const Duration(seconds: AppConstants.broadcastIntervalSeconds),
        (_) => broadcastPresence(),
      );

      _cleanupTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => _cleanupExpiredPeers(),
      );

      _isRunning = true;
      AppLogger.instance.info(
          'Discovery service started on port ${AppConstants.discoveryPort}');

      // Initial broadcast
      broadcastPresence();
    } catch (e, stackTrace) {
      AppLogger.instance
          .error('Failed to start discovery service', e, stackTrace);
      throw DiscoveryException('Failed to start discovery service', e);
    }
  }

  Future<void> stopDiscovery() async {
    if (!_isRunning) return;

    try {
      _broadcastTimer?.cancel();
      _cleanupTimer?.cancel();
      _socketSubscription?.cancel();
      _socket?.close();

      _isRunning = false;
      _activePeers.clear();

      AppLogger.instance.info('Discovery service stopped');
    } catch (e, stackTrace) {
      AppLogger.instance
          .error('Failed to stop discovery service', e, stackTrace);
      throw DiscoveryException('Failed to stop discovery service', e);
    }
  }

  void broadcastPresence() {
    if (_socket == null || !_isRunning) return;

    try {
      final primaryIp =
          _localIpAddresses.isNotEmpty ? _localIpAddresses.first : '0.0.0.0';

      final packet = DiscoveryPacket(
        deviceId: _deviceId!,
        deviceName: _deviceName!,
        ipAddress: primaryIp,
        platform: _getPlatform(),
        appVersion: AppConstants.appVersion,
        avatarColor: _avatarColor!,
        timestamp: DateTime.now(),
        publicKey: CryptoService.instance.isReady
            ? CryptoService.instance.publicKeyBase64
            : null,
      );

      final jsonData = jsonEncode(packet.toJson());
      final data = utf8.encode(jsonData);

      _socket!.send(
        data,
        InternetAddress(NetworkConstants.broadcastAddress),
        AppConstants.discoveryPort,
      );

      AppLogger.instance.debug('Broadcast presence: ${packet.deviceName}');
    } catch (e, stackTrace) {
      AppLogger.instance.error('Failed to broadcast presence', e, stackTrace);
    }
  }

  void _handleSocketEvent(RawSocketEvent event) {
    if (event == RawSocketEvent.read) {
      try {
        final datagram = _socket!.receive();
        if (datagram == null) return;

        final message = utf8.decode(datagram.data);
        final jsonData = jsonDecode(message) as Map<String, dynamic>;
        final packet = DiscoveryPacket.fromJson(jsonData);

        // Ignore our own broadcasts
        if (packet.deviceId == _deviceId) {
          return;
        }

        _handlePeerDiscovered(packet);
      } catch (e, stackTrace) {
        AppLogger.instance
            .error('Failed to handle socket event', e, stackTrace);
      }
    }
  }

  void _handlePeerDiscovered(DiscoveryPacket packet) {
    try {
      final existingPeer = _activePeers[packet.deviceId];

      final peer = PeerDevice(
        deviceId: packet.deviceId,
        displayName: packet.deviceName,
        ipAddress: packet.ipAddress,
        platform: packet.platform,
        appVersion: packet.appVersion,
        avatarColor: packet.avatarColor,
        isOnline: true,
        lastSeen: packet.timestamp,
      );

      _activePeers[packet.deviceId] = peer;

      // Pin the peer's public key on first sighting (trust-on-first-use) so we
      // can derive the E2E session key and detect later key changes.
      if (packet.publicKey != null) {
        final ok = CryptoService.instance
            .pinPeerPublicKey(packet.deviceId, packet.publicKey!);
        if (!ok) {
          AppLogger.instance.warning(
              'Discovered ${packet.deviceName} with a changed public key — '
              'ignoring the new key.');
        }
      }

      // Persist peer so conversations started from history can resolve the IP later.
      StorageService.instance.savePeer(peer);

      if (existingPeer == null) {
        AppLogger.instance.info('New peer discovered: ${packet.deviceName}');
        _peerDiscoveredController.add(peer);
      } else {
        AppLogger.instance.debug('Peer updated: ${packet.deviceName}');
      }
    } catch (e, stackTrace) {
      AppLogger.instance
          .error('Failed to handle peer discovered', e, stackTrace);
    }
  }

  void _cleanupExpiredPeers() {
    try {
      final now = DateTime.now();
      final expiredPeers = <String>[];

      _activePeers.forEach((deviceId, peer) {
        if (now.difference(peer.lastSeen).inSeconds >
            AppConstants.peerTimeoutSeconds) {
          expiredPeers.add(deviceId);
        }
      });

      for (final deviceId in expiredPeers) {
        final peer = _activePeers.remove(deviceId);
        if (peer != null) {
          AppLogger.instance.info('Peer expired: ${peer.displayName}');
          _peerLeftController.add(deviceId);
        }
      }

      if (expiredPeers.isNotEmpty) {
        AppLogger.instance
            .debug('Cleaned up ${expiredPeers.length} expired peers');
      }
    } catch (e, stackTrace) {
      AppLogger.instance
          .error('Failed to cleanup expired peers', e, stackTrace);
    }
  }

  PeerDevice? getPeer(String deviceId) {
    return _activePeers[deviceId];
  }

  void removePeer(String deviceId) {
    final peer = _activePeers.remove(deviceId);
    if (peer != null) {
      AppLogger.instance.info('Peer removed: ${peer.displayName}');
      _peerLeftController.add(deviceId);
    }
  }

  String _getPlatform() {
    if (Platform.isAndroid) return AppConstants.platformAndroid;
    if (Platform.isIOS) return AppConstants.platformIOS;
    if (Platform.isWindows) return AppConstants.platformWindows;
    if (Platform.isMacOS) return AppConstants.platformMacOS;
    if (Platform.isLinux) return AppConstants.platformLinux;
    return 'unknown';
  }

  /// Test-only helper that returns the singleton to its uninitialized state
  /// so each test starts from a clean slate. Do not call from production code.
  @visibleForTesting
  Future<void> resetForTest() async {
    await stopDiscovery();
    _deviceId = null;
    _deviceName = null;
    _avatarColor = null;
    _localIpAddresses = [];
    _activePeers.clear();
  }

  void dispose() {
    _peerDiscoveredController.close();
    _peerLeftController.close();
    stopDiscovery();
  }
}
