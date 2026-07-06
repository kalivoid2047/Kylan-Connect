import 'package:json_annotation/json_annotation.dart';
import 'message.dart';

part 'message_packet.g.dart';

@JsonSerializable()
class MessagePacket {
  final String id;
  final String type;
  final String senderId;
  final String receiverId;
  final Map<String, dynamic> payload;
  final DateTime timestamp;
  
  MessagePacket({
    required this.id,
    required this.type,
    required this.senderId,
    required this.receiverId,
    required this.payload,
    required this.timestamp,
  });
  
  factory MessagePacket.fromJson(Map<String, dynamic> json) =>
      _$MessagePacketFromJson(json);
  
  Map<String, dynamic> toJson() => _$MessagePacketToJson(this);
  
  static MessagePacket fromMessage(Message message) {
    return MessagePacket(
      id: message.id,
      type: message.type,
      senderId: message.senderId,
      receiverId: message.receiverId,
      payload: message.payload,
      timestamp: message.timestamp,
    );
  }
}
