// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'peer_device.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class PeerDeviceAdapter extends TypeAdapter<PeerDevice> {
  @override
  final int typeId = 1;

  @override
  PeerDevice read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return PeerDevice(
      deviceId: fields[0] as String,
      displayName: fields[1] as String,
      ipAddress: fields[2] as String,
      platform: fields[3] as String,
      appVersion: fields[4] as String,
      avatarColor: fields[5] as String,
      isOnline: fields[6] as bool,
      lastSeen: fields[7] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, PeerDevice obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.deviceId)
      ..writeByte(1)
      ..write(obj.displayName)
      ..writeByte(2)
      ..write(obj.ipAddress)
      ..writeByte(3)
      ..write(obj.platform)
      ..writeByte(4)
      ..write(obj.appVersion)
      ..writeByte(5)
      ..write(obj.avatarColor)
      ..writeByte(6)
      ..write(obj.isOnline)
      ..writeByte(7)
      ..write(obj.lastSeen);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PeerDeviceAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PeerDevice _$PeerDeviceFromJson(Map<String, dynamic> json) => PeerDevice(
      deviceId: json['deviceId'] as String,
      displayName: json['displayName'] as String,
      ipAddress: json['ipAddress'] as String,
      platform: json['platform'] as String,
      appVersion: json['appVersion'] as String,
      avatarColor: json['avatarColor'] as String,
      isOnline: json['isOnline'] as bool,
      lastSeen: DateTime.parse(json['lastSeen'] as String),
    );

Map<String, dynamic> _$PeerDeviceToJson(PeerDevice instance) =>
    <String, dynamic>{
      'deviceId': instance.deviceId,
      'displayName': instance.displayName,
      'ipAddress': instance.ipAddress,
      'platform': instance.platform,
      'appVersion': instance.appVersion,
      'avatarColor': instance.avatarColor,
      'isOnline': instance.isOnline,
      'lastSeen': instance.lastSeen.toIso8601String(),
    };
