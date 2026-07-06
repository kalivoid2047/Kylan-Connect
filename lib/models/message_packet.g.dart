// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'message_packet.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MessagePacket _$MessagePacketFromJson(Map<String, dynamic> json) =>
    MessagePacket(
      id: json['id'] as String,
      type: json['type'] as String,
      senderId: json['senderId'] as String,
      receiverId: json['receiverId'] as String,
      payload: json['payload'] as Map<String, dynamic>,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );

Map<String, dynamic> _$MessagePacketToJson(MessagePacket instance) =>
    <String, dynamic>{
      'id': instance.id,
      'type': instance.type,
      'senderId': instance.senderId,
      'receiverId': instance.receiverId,
      'payload': instance.payload,
      'timestamp': instance.timestamp.toIso8601String(),
    };
