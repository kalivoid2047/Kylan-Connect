import 'package:hive/hive.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:uuid/uuid.dart';
import '../core/constants/app_constants.dart';

part 'message.g.dart';

@HiveType(typeId: 2)
@JsonSerializable()
class Message {
  @HiveField(0)
  final String id;
  
  @HiveField(1)
  final String type;
  
  @HiveField(2)
  final String senderId;
  
  @HiveField(3)
  final String receiverId;
  
  @HiveField(4)
  final Map<String, dynamic> payload;
  
  @HiveField(5)
  final DateTime timestamp;
  
  @HiveField(6)
  final String status;
  
  Message({
    required this.id,
    required this.type,
    required this.senderId,
    required this.receiverId,
    required this.payload,
    required this.timestamp,
    required this.status,
  });
  
  factory Message.fromJson(Map<String, dynamic> json) =>
      _$MessageFromJson(json);
  
  Map<String, dynamic> toJson() => _$MessageToJson(this);
  
  Message copyWith({
    String? id,
    String? type,
    String? senderId,
    String? receiverId,
    Map<String, dynamic>? payload,
    DateTime? timestamp,
    String? status,
  }) {
    return Message(
      id: id ?? this.id,
      type: type ?? this.type,
      senderId: senderId ?? this.senderId,
      receiverId: receiverId ?? this.receiverId,
      payload: payload ?? this.payload,
      timestamp: timestamp ?? this.timestamp,
      status: status ?? this.status,
    );
  }
  
  static Message createTextMessage({
    required String senderId,
    required String receiverId,
    required String text,
  }) {
    return Message(
      id: const Uuid().v4(),
      type: AppConstants.messageTypeText,
      senderId: senderId,
      receiverId: receiverId,
      payload: {'message': text},
      timestamp: DateTime.now(),
      status: AppConstants.messageStatusSending,
    );
  }
  
  String? get textContent => payload['message'] as String?;
}
