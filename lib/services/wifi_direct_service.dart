import 'dart:async';
import 'dart:io';

import 'package:permission_handler/permission_handler.dart';
import 'package:wifi_direct_plugin/wifi_direct_plugin.dart' as native;
// wifi_direct_plugin.dart references these types in its own API but does not
// re-export them, so they must be imported directly.
import 'package:wifi_direct_plugin/wifi_direct_plugin_platform_interface.dart'
    as native_types;

import '../core/utils/app_logger.dart';
import 'discovery_service.dart';

/// A nearby device discovered over WiFi Direct, decoupled from the plugin's
/// own type so it doesn't leak through the app.
class WifiDirectPeer {
  final String deviceName;
  final String deviceAddress;
  final String statusText;

  const WifiDirectPeer({
    required this.deviceName,
    required this.deviceAddress,
    required this.statusText,
  });

  factory WifiDirectPeer.fromNative(native_types.WifiDirectDevice device) {
    return WifiDirectPeer(
      deviceName: device.deviceName.isNotEmpty ? device.deviceName : 'Unknown device',
      deviceAddress: device.deviceAddress,
      statusText: _statusText(device.status),
    );
  }

  /// Pure, unit-tested mapping from the plugin's numeric WifiP2pDevice status
  /// to a readable label (see Android WifiP2pDevice.Status constants).
  static String _statusText(int? status) {
    switch (status) {
      case 0:
        return 'Connected';
      case 1:
        return 'Invited';
      case 2:
        return 'Failed';
      case 3:
        return 'Available';
      case 4:
        return 'Unavailable';
      default:
        return 'Unknown';
    }
  }
}

/// Opt-in WiFi Direct connectivity (Android only), used purely to form a
/// direct P2P network link — NOT as a messaging channel.
///
/// Design note: the underlying plugin bundles its own text/file messaging
/// protocol, but we deliberately never call into it. Once WiFi Direct forms a
/// group, Android exposes it as a normal IP network interface (the `p2p0`
/// interface, typically on the 192.168.49.x subnet). Kylan Connect's existing
/// per-interface UDP broadcast discovery (DiscoveryService) already reaches
/// every local interface; [onConnected] below just nudges it to rescan
/// immediately (via [DiscoveryService.refreshInterfacesAndBroadcast]) instead
/// of waiting for the next periodic broadcast. From there, discovery, TOFU key
/// pinning, encryption, and messaging are 100% the existing, already-tested
/// pipeline — this service only ever establishes the link.
///
/// This plugin has very low adoption (few pub.dev likes, unverified
/// publisher) and its own peer/connection info fields are used internally for
/// its bundled protocol rather than documented as a stable public contract —
/// so this service treats everything it returns as best-effort and never
/// depends on it for anything security- or delivery-critical.
class WifiDirectService {
  static final WifiDirectService _instance = WifiDirectService._internal();
  static WifiDirectService get instance => _instance;

  WifiDirectService._internal();

  bool _initialized = false;
  bool _permissionsGranted = false;
  StreamSubscription<native_types.WifiDirectConnectionInfo>?
      _connectionSubscription;
  StreamSubscription<List<native_types.WifiDirectDevice>>? _peersSubscription;

  final StreamController<List<WifiDirectPeer>> _peersController =
      StreamController.broadcast();
  final StreamController<bool> _connectionController =
      StreamController.broadcast();

  /// True only on Android — WiFi Direct has no equivalent on this app's other
  /// supported platforms.
  bool get isSupported => Platform.isAndroid;

  Stream<List<WifiDirectPeer>> get onPeersUpdated => _peersController.stream;

  /// Emits the current WiFi Direct connection state (true = connected).
  Stream<bool> get onConnectionChanged => _connectionController.stream;

  bool get isInitialized => _initialized;

  /// Requests the runtime permissions WiFi Direct needs. The native plugin
  /// does not request these itself, so the app must before calling any other
  /// method here. Returns false if the user denies them.
  Future<bool> requestPermissions() async {
    if (!isSupported) return false;
    try {
      final results = await [
        Permission.locationWhenInUse,
        Permission.nearbyWifiDevices,
      ].request();

      _permissionsGranted = results.values.every(
        (status) => status.isGranted || status.isLimited,
      );
      return _permissionsGranted;
    } catch (e, stackTrace) {
      AppLogger.instance
          .error('Failed to request WiFi Direct permissions', e, stackTrace);
      return false;
    }
  }

  Future<bool> initialize() async {
    if (!isSupported) return false;
    if (_initialized) return true;

    if (!_permissionsGranted && !await requestPermissions()) {
      AppLogger.instance.warning('WiFi Direct permissions not granted');
      return false;
    }

    try {
      final ok = await native.WifiDirectPlugin.initialize();
      if (!ok) return false;

      await _peersSubscription?.cancel();
      _peersSubscription = native.WifiDirectPlugin.peersStream.listen((devices) {
        _peersController.add(devices.map(WifiDirectPeer.fromNative).toList());
      });

      _connectionSubscription =
          native.WifiDirectPlugin.connectionStream.listen((info) {
        _connectionController.add(info.isConnected);
        if (info.isConnected) {
          // A new network interface may have just appeared — rescan and
          // broadcast immediately so the peer is found without delay.
          unawaited(DiscoveryService.instance.refreshInterfacesAndBroadcast());
        }
      });

      _initialized = true;
      AppLogger.instance.info('WiFi Direct initialized');
      return true;
    } catch (e, stackTrace) {
      AppLogger.instance.warning('WiFi Direct unavailable: $e');
      AppLogger.instance.debug('WiFi Direct init error: $stackTrace');
      return false;
    }
  }

  Future<bool> startDiscovery() async {
    if (!_initialized) return false;
    try {
      // Android's WifiP2pManager needs the system Location Services toggle
      // on (separate from the app's own location permission, already
      // granted at this point) to return scan results. On many OEMs
      // discoverPeers() still calls onSuccess with this off -- it just never
      // reports any peers -- so this has to be checked explicitly rather
      // than inferred from a discovery failure.
      if (await Permission.location.serviceStatus != ServiceStatus.enabled) {
        AppLogger.instance
            .warning('WiFi Direct: system Location Services is off');
        return false;
      }
      return await native.WifiDirectPlugin.startDiscovery();
    } catch (e) {
      AppLogger.instance.debug('WiFi Direct startDiscovery failed: $e');
      return false;
    }
  }

  Future<bool> stopDiscovery() async {
    if (!_initialized) return false;
    try {
      return await native.WifiDirectPlugin.stopDiscovery();
    } catch (e) {
      AppLogger.instance.debug('WiFi Direct stopDiscovery failed: $e');
      return false;
    }
  }

  Future<bool> connect(String deviceAddress) async {
    if (!_initialized) return false;
    try {
      return await native.WifiDirectPlugin.connect(deviceAddress);
    } catch (e) {
      AppLogger.instance.debug('WiFi Direct connect failed: $e');
      return false;
    }
  }

  Future<bool> disconnect() async {
    if (!_initialized) return false;
    try {
      return await native.WifiDirectPlugin.disconnect();
    } catch (e) {
      AppLogger.instance.debug('WiFi Direct disconnect failed: $e');
      return false;
    }
  }

  void dispose() {
    _connectionSubscription?.cancel();
    _connectionSubscription = null;
    _peersSubscription?.cancel();
    _peersSubscription = null;
    if (_initialized) {
      try {
        native.WifiDirectPlugin.dispose();
      } catch (_) {}
    }
    _initialized = false;
  }
}
