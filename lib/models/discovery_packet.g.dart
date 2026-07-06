// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'discovery_packet.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DiscoveryPacket _$DiscoveryPacketFromJson(Map<String, dynamic> json) =>
    DiscoveryPacket(
      deviceId: json['deviceId'] as String,
      deviceName: json['deviceName'] as String,
      ipAddress: json['ipAddress'] as String,
      platform: json['platform'] as String,
      appVersion: json['appVersion'] as String,
      avatarColor: json['avatarColor'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );

Map<String, dynamic> _$DiscoveryPacketToJson(DiscoveryPacket instance) =>
    <String, dynamic>{
      'deviceId': instance.deviceId,
      'deviceName': instance.deviceName,
      'ipAddress': instance.ipAddress,
      'platform': instance.platform,
      'appVersion': instance.appVersion,
      'avatarColor': instance.avatarColor,
      'timestamp': instance.timestamp.toIso8601String(),
    };
