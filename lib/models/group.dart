import 'package:uuid/uuid.dart';

/// A group conversation's membership and metadata.
///
/// Stored as JSON (no Hive adapter) so it needs no code generation. Group
/// messages reuse the 1:1 pairwise crypto: a sender encrypts a copy per member
/// with that member's key and fans it out, so there is no separate group key to
/// distribute or rotate — membership changes just update [memberIds].
class Group {
  final String groupId;
  final String name;

  /// All member deviceIds, including the creator (and this device when it is a
  /// member). Fan-out skips the local device.
  final List<String> memberIds;

  final String createdBy;
  final String avatarColor;
  final DateTime createdAt;

  Group({
    required this.groupId,
    required this.name,
    required this.memberIds,
    required this.createdBy,
    required this.avatarColor,
    required this.createdAt,
  });

  factory Group.create({
    required String name,
    required List<String> memberIds,
    required String createdBy,
    required String avatarColor,
  }) {
    return Group(
      groupId: const Uuid().v4(),
      name: name,
      memberIds: List.unmodifiable(memberIds),
      createdBy: createdBy,
      avatarColor: avatarColor,
      createdAt: DateTime.now(),
    );
  }

  Group copyWith({
    String? name,
    List<String>? memberIds,
    String? avatarColor,
  }) {
    return Group(
      groupId: groupId,
      name: name ?? this.name,
      memberIds: memberIds ?? this.memberIds,
      createdBy: createdBy,
      avatarColor: avatarColor ?? this.avatarColor,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'groupId': groupId,
        'name': name,
        'memberIds': memberIds,
        'createdBy': createdBy,
        'avatarColor': avatarColor,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Group.fromJson(Map<String, dynamic> json) => Group(
        groupId: json['groupId'] as String,
        name: json['name'] as String,
        memberIds: (json['memberIds'] as List<dynamic>).cast<String>(),
        createdBy: json['createdBy'] as String,
        avatarColor: json['avatarColor'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}
