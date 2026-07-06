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
  
  DiscoveryPacket({
    required this.deviceId,
    required this.deviceName,
    required this.ipAddress,
    required this.platform,
    required this.appVersion,
    required this.avatarColor,
    required this.timestamp,
  });
  
  factory DiscoveryPacket.fromJson(Map<String, dynamic> json) =>
      _$DiscoveryPacketFromJson(json);
  
  Map<String, dynamic> toJson() => _$DiscoveryPacketToJson(this);
  
  String toJsonString() => jsonEncode(toJson());
}
