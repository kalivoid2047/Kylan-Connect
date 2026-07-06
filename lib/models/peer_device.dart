import 'package:hive/hive.dart';
import 'package:json_annotation/json_annotation.dart';

part 'peer_device.g.dart';

@HiveType(typeId: 1)
@JsonSerializable()
class PeerDevice {
  @HiveField(0)
  final String deviceId;
  
  @HiveField(1)
  final String displayName;
  
  @HiveField(2)
  final String ipAddress;
  
  @HiveField(3)
  final String platform;
  
  @HiveField(4)
  final String appVersion;
  
  @HiveField(5)
  final String avatarColor;
  
  @HiveField(6)
  final bool isOnline;
  
  @HiveField(7)
  final DateTime lastSeen;
  
  PeerDevice({
    required this.deviceId,
    required this.displayName,
    required this.ipAddress,
    required this.platform,
    required this.appVersion,
    required this.avatarColor,
    required this.isOnline,
    required this.lastSeen,
  });
  
  factory PeerDevice.fromJson(Map<String, dynamic> json) =>
      _$PeerDeviceFromJson(json);
  
  Map<String, dynamic> toJson() => _$PeerDeviceToJson(this);
  
  PeerDevice copyWith({
    String? deviceId,
    String? displayName,
    String? ipAddress,
    String? platform,
    String? appVersion,
    String? avatarColor,
    bool? isOnline,
    DateTime? lastSeen,
  }) {
    return PeerDevice(
      deviceId: deviceId ?? this.deviceId,
      displayName: displayName ?? this.displayName,
      ipAddress: ipAddress ?? this.ipAddress,
      platform: platform ?? this.platform,
      appVersion: appVersion ?? this.appVersion,
      avatarColor: avatarColor ?? this.avatarColor,
      isOnline: isOnline ?? this.isOnline,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }
  
  bool get isExpired {
    return DateTime.now().difference(lastSeen).inSeconds > 15;
  }
}
