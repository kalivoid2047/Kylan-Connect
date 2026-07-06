import 'package:hive/hive.dart';
import 'package:json_annotation/json_annotation.dart';

part 'user_profile.g.dart';

@HiveType(typeId: 0)
@JsonSerializable()
class UserProfile {
  @HiveField(0)
  final String deviceId;
  
  @HiveField(1)
  final String displayName;
  
  @HiveField(2)
  final String avatarColor;
  
  @HiveField(3)
  final DateTime createdAt;
  
  @HiveField(4)
  final DateTime lastUpdated;
  
  UserProfile({
    required this.deviceId,
    required this.displayName,
    required this.avatarColor,
    required this.createdAt,
    required this.lastUpdated,
  });
  
  factory UserProfile.fromJson(Map<String, dynamic> json) =>
      _$UserProfileFromJson(json);
  
  Map<String, dynamic> toJson() => _$UserProfileToJson(this);
  
  UserProfile copyWith({
    String? deviceId,
    String? displayName,
    String? avatarColor,
    DateTime? createdAt,
    DateTime? lastUpdated,
  }) {
    return UserProfile(
      deviceId: deviceId ?? this.deviceId,
      displayName: displayName ?? this.displayName,
      avatarColor: avatarColor ?? this.avatarColor,
      createdAt: createdAt ?? this.createdAt,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }
}
