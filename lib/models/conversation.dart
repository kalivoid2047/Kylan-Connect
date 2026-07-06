import 'package:hive/hive.dart';
import 'package:json_annotation/json_annotation.dart';

part 'conversation.g.dart';

@HiveType(typeId: 3)
@JsonSerializable()
class Conversation {
  @HiveField(0)
  final String conversationId;
  
  @HiveField(1)
  final String participantId;
  
  @HiveField(2)
  final String participantName;
  
  @HiveField(3)
  final String participantAvatarColor;
  
  @HiveField(4)
  final String? lastMessage;
  
  @HiveField(5)
  final DateTime? lastMessageTime;
  
  @HiveField(6)
  final int unreadCount;
  
  @HiveField(7)
  final bool isOnline;
  
  Conversation({
    required this.conversationId,
    required this.participantId,
    required this.participantName,
    required this.participantAvatarColor,
    this.lastMessage,
    this.lastMessageTime,
    this.unreadCount = 0,
    this.isOnline = false,
  });
  
  factory Conversation.fromJson(Map<String, dynamic> json) =>
      _$ConversationFromJson(json);
  
  Map<String, dynamic> toJson() => _$ConversationToJson(this);
  
  Conversation copyWith({
    String? conversationId,
    String? participantId,
    String? participantName,
    String? participantAvatarColor,
    String? lastMessage,
    DateTime? lastMessageTime,
    int? unreadCount,
    bool? isOnline,
  }) {
    return Conversation(
      conversationId: conversationId ?? this.conversationId,
      participantId: participantId ?? this.participantId,
      participantName: participantName ?? this.participantName,
      participantAvatarColor: participantAvatarColor ?? this.participantAvatarColor,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      unreadCount: unreadCount ?? this.unreadCount,
      isOnline: isOnline ?? this.isOnline,
    );
  }
  
  static String generateConversationId(String userId1, String userId2) {
    final ids = [userId1, userId2]..sort();
    return '${ids[0]}_${ids[1]}';
  }
}
