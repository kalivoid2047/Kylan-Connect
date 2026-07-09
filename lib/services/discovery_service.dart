import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:nsd/nsd.dart' as nsd;
import '../core/constants/app_constants.dart';
import '../core/constants/network_constants.dart';
import '../core/errors/exceptions.dart';
import '../core/security/crypto_service.dart';
import '../models/discovery_packet.dart';
import '../models/peer_device.dart';
import '../services/mdns_codec.dart';
import '../services/storage_service.dart';
import '../core/utils/app_logger.dart';

class DiscoveryService {
  static final DiscoveryService _instance = DiscoveryService._internal();
  static DiscoveryService get instance => _instance;

  RawDatagramSocket? _socket;
  Timer? _broadcastTimer;
  Timer? _cleanupTimer;
  StreamSubscription<RawSocketEvent>? _socketSubscription;

  // mDNS/Bonjour discovery runs alongside UDP broadcast.
  nsd.Registration? _mdnsRegistration;
  nsd.Discovery? _mdnsDiscovery;

  /// deviceIds currently advertised via mDNS. These are kept alive by explicit
  /// "service lost" events rather than the UDP heartbeat timeout.
  final Set<String> _mdnsPresentPeers = {};

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

      // Start mDNS/Bonjour alongside UDP broadcast (best-effort).
      unawaited(_startMdns());
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
      await _stopMdns();

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
      final publicKey = CryptoService.instance.isReady
          ? CryptoService.instance.publicKeyBase64
          : null;

      if (_localIpAddresses.isEmpty) {
        // No interfaces enumerated — fall back to a single limited broadcast.
        _sendPresence('0.0.0.0', NetworkConstants.broadcastAddress, publicKey);
        return;
      }

      // Send one packet per interface to that subnet's directed broadcast so a
      // multi-homed host reaches peers on every network (a single limited
      // broadcast only egresses one interface). Each packet advertises the
      // sender's IP *on that subnet*, so the address a peer sees is reachable.
      for (final localIp in _localIpAddresses) {
        _sendPresence(localIp, _directedBroadcastFor(localIp), publicKey);
      }

      // Also emit a limited broadcast as a fallback for networks that filter
      // directed broadcasts, advertising the primary interface address.
      _sendPresence(_localIpAddresses.first, NetworkConstants.broadcastAddress,
          publicKey);

      AppLogger.instance
          .debug('Broadcast presence on ${_localIpAddresses.length} interface(s)');
    } catch (e, stackTrace) {
      AppLogger.instance.error('Failed to broadcast presence', e, stackTrace);
    }
  }

  /// Sends a discovery packet advertising [advertisedIp] to [destination].
  void _sendPresence(
      String advertisedIp, String destination, String? publicKey) {
    final packet = DiscoveryPacket(
      deviceId: _deviceId!,
      deviceName: _deviceName!,
      ipAddress: advertisedIp,
      platform: _getPlatform(),
      appVersion: AppConstants.appVersion,
      avatarColor: _avatarColor!,
      timestamp: DateTime.now(),
      publicKey: publicKey,
    );

    final data = utf8.encode(jsonEncode(packet.toJson()));
    _socket!.send(data, InternetAddress(destination), AppConstants.discoveryPort);
  }

  /// The /24 directed broadcast address for [ip] (e.g. 192.168.1.7 → 192.168.1.255).
  /// Dart exposes no netmask, so we assume the common /24; the limited-broadcast
  /// fallback covers other prefix lengths. Malformed input falls back to the
  /// limited broadcast.
  String _directedBroadcastFor(String ip) {
    final octets = ip.split('.');
    if (octets.length != 4) return NetworkConstants.broadcastAddress;
    return '${octets[0]}.${octets[1]}.${octets[2]}.255';
  }

  /// Registers our service and starts browsing via mDNS/Bonjour. Best-effort:
  /// on platforms without support it logs and leaves UDP broadcast as the only
  /// transport.
  Future<void> _startMdns() async {
    try {
      final txt = MdnsCodec.encode(
        deviceId: _deviceId!,
        deviceName: _deviceName!,
        avatarColor: _avatarColor!,
        platform: _getPlatform(),
        appVersion: AppConstants.appVersion,
        publicKey: CryptoService.instance.isReady
            ? CryptoService.instance.publicKeyBase64
            : null,
      );

      _mdnsRegistration = await nsd.register(nsd.Service(
        name: _deviceId,
        type: MdnsCodec.serviceType,
        port: AppConstants.messagingPort,
        txt: txt.map((k, v) => MapEntry(k, Uint8List.fromList(v))),
      ));

      _mdnsDiscovery = await nsd.startDiscovery(
        MdnsCodec.serviceType,
        autoResolve: true,
        ipLookupType: nsd.IpLookupType.v4,
      );
      _mdnsDiscovery!.addServiceListener(_onMdnsService);
      AppLogger.instance
          .info('mDNS discovery started (${MdnsCodec.serviceType})');
    } catch (e, stackTrace) {
      AppLogger.instance.warning('mDNS discovery unavailable: $e');
      AppLogger.instance.debug('mDNS start error: $stackTrace');
    }
  }

  Future<void> _stopMdns() async {
    _mdnsPresentPeers.clear();
    try {
      if (_mdnsDiscovery != null) {
        _mdnsDiscovery!.removeServiceListener(_onMdnsService);
        await nsd.stopDiscovery(_mdnsDiscovery!);
      }
    } catch (e) {
      AppLogger.instance.debug('Failed to stop mDNS discovery: $e');
    }
    _mdnsDiscovery = null;

    try {
      if (_mdnsRegistration != null) {
        await nsd.unregister(_mdnsRegistration!);
      }
    } catch (e) {
      AppLogger.instance.debug('Failed to unregister mDNS service: $e');
    }
    _mdnsRegistration = null;
  }

  void _onMdnsService(nsd.Service service, nsd.ServiceStatus status) {
    try {
      final txt = service.txt?.map<String, List<int>?>((k, v) => MapEntry(k, v));
      final deviceId = MdnsCodec.deviceIdOf(txt, service.name);
      if (deviceId == null || deviceId == _deviceId) return; // self/invalid

      if (status == nsd.ServiceStatus.found) {
        final ipv4 = service.addresses
            ?.where((a) => a.type == InternetAddressType.IPv4);
        final ip = (ipv4 != null && ipv4.isNotEmpty) ? ipv4.first.address : null;
        final packet =
            MdnsCodec.decode(txt, ipAddress: ip, serviceName: service.name);
        if (packet == null) {
          AppLogger.instance
              .debug('mDNS peer $deviceId not yet resolvable (no IPv4)');
          return;
        }
        _mdnsPresentPeers.add(deviceId);
        _handlePeerDiscovered(packet);
      } else if (status == nsd.ServiceStatus.lost) {
        _mdnsPresentPeers.remove(deviceId);
        removePeer(deviceId);
      }
    } catch (e, stackTrace) {
      AppLogger.instance
          .error('Failed to handle mDNS service event', e, stackTrace);
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
        // Peers currently advertised via mDNS are kept alive by explicit
        // "service lost" events, not the UDP heartbeat timeout.
        if (_mdnsPresentPeers.contains(deviceId)) return;
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
    _mdnsPresentPeers.clear();
  }

  void dispose() {
    _peerDiscoveredController.close();
    _peerLeftController.close();
    stopDiscovery();
  }
}
