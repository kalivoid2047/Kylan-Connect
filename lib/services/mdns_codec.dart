import 'dart:convert';

import '../core/constants/app_constants.dart';
import '../models/discovery_packet.dart';

/// Encodes/decodes peer metadata to and from mDNS TXT records.
///
/// Kept free of any plugin types (works on plain `Map<String, List<int>?>`) so
/// it can be unit-tested without the platform. TXT keys are short (mDNS
/// recommends <= 9 chars) and values are UTF-8 bytes.
class MdnsCodec {
  static const String serviceType = '_kylanconnect._tcp';

  static const String kId = 'id';
  static const String kName = 'name';
  static const String kColor = 'color';
  static const String kPlatform = 'plat';
  static const String kVersion = 'ver';
  static const String kPublicKey = 'pk';

  /// Builds the TXT record map advertised for this device.
  static Map<String, List<int>> encode({
    required String deviceId,
    required String deviceName,
    required String avatarColor,
    required String platform,
    required String appVersion,
    String? publicKey,
  }) {
    final map = <String, List<int>>{
      kId: utf8.encode(deviceId),
      kName: utf8.encode(deviceName),
      kColor: utf8.encode(avatarColor),
      kPlatform: utf8.encode(platform),
      kVersion: utf8.encode(appVersion),
    };
    if (publicKey != null) map[kPublicKey] = utf8.encode(publicKey);
    return map;
  }

  /// The advertised deviceId from a service's TXT (falling back to the service
  /// instance [serviceName], which we register as the deviceId). Used to
  /// identify a peer on both "found" and "lost" events.
  static String? deviceIdOf(Map<String, List<int>?>? txt, String? serviceName) {
    return _string(txt, kId) ?? serviceName;
  }

  /// Builds a [DiscoveryPacket] from a resolved service's TXT and IP. Returns
  /// null if the essentials (deviceId, a reachable IP) are missing.
  static DiscoveryPacket? decode(
    Map<String, List<int>?>? txt, {
    required String? ipAddress,
    String? serviceName,
  }) {
    final deviceId = deviceIdOf(txt, serviceName);
    if (deviceId == null || deviceId.isEmpty) return null;
    if (ipAddress == null || ipAddress.isEmpty) return null;

    return DiscoveryPacket(
      deviceId: deviceId,
      deviceName: _string(txt, kName) ?? 'Unknown',
      ipAddress: ipAddress,
      platform: _string(txt, kPlatform) ?? 'unknown',
      appVersion: _string(txt, kVersion) ?? '',
      avatarColor: _string(txt, kColor) ?? AppConstants.avatarColors.first,
      timestamp: DateTime.now(),
      publicKey: _string(txt, kPublicKey),
    );
  }

  static String? _string(Map<String, List<int>?>? txt, String key) {
    final value = txt?[key];
    if (value == null || value.isEmpty) return null;
    return utf8.decode(value, allowMalformed: true);
  }
}
