import 'dart:convert';

import 'package:json_annotation/json_annotation.dart';

part 'discovery_packet.g.dart';

@JsonSerializable()
class DiscoveryPacket {
  final String deviceId;
  final String deviceName;
  final String ipAddress;
  final String platform;
  final String appVersion;
  final String avatarColor;
  final DateTime timestamp;

  /// Base64 X25519 public key used to derive the E2E session key. Nullable so
  /// packets from older builds (which omit it) still deserialize.
  final String? publicKey;

  DiscoveryPacket({
    required this.deviceId,
    required this.deviceName,
    required this.ipAddress,
    required this.platform,
    required this.appVersion,
    required this.avatarColor,
    required this.timestamp,
    this.publicKey,
  });
  
  factory DiscoveryPacket.fromJson(Map<String, dynamic> json) =>
      _$DiscoveryPacketFromJson(json);
  
  Map<String, dynamic> toJson() => _$DiscoveryPacketToJson(this);
  
  String toJsonString() => jsonEncode(toJson());
}
