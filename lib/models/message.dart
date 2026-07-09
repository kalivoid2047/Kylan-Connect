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

  /// A text message addressed to a group. The same logical message is fanned
  /// out to each member (encrypted per-member); [groupId] tells the receiver to
  /// file it under the group conversation.
  static Message createGroupTextMessage({
    required String senderId,
    required String groupId,
    required String text,
  }) {
    return Message(
      id: const Uuid().v4(),
      type: AppConstants.messageTypeText,
      senderId: senderId,
      receiverId: groupId,
      payload: {'message': text, 'groupId': groupId},
      timestamp: DateTime.now(),
      status: AppConstants.messageStatusSending,
    );
  }

  /// A control message announcing group membership. Carries the full group
  /// definition so the recipient can create the group locally.
  static Message createGroupInvite({
    required String senderId,
    required String receiverId,
    required Map<String, dynamic> groupJson,
  }) {
    return Message(
      id: const Uuid().v4(),
      type: AppConstants.messageTypeGroupInvite,
      senderId: senderId,
      receiverId: receiverId,
      payload: {'group': groupJson},
      timestamp: DateTime.now(),
      status: AppConstants.messageStatusSent,
    );
  }

  static Message createDeliveryAck({
    required String senderId,
    required String receiverId,
    required String originalMessageId,
  }) {
    return Message(
      id: const Uuid().v4(),
      type: AppConstants.messageTypeDeliveryAck,
      senderId: senderId,
      receiverId: receiverId,
      payload: {'originalMessageId': originalMessageId},
      timestamp: DateTime.now(),
      status: AppConstants.messageStatusSent,
    );
  }

  static Message createReadReceipt({
    required String senderId,
    required String receiverId,
    required String originalMessageId,
  }) {
    return Message(
      id: const Uuid().v4(),
      type: AppConstants.messageTypeReadReceipt,
      senderId: senderId,
      receiverId: receiverId,
      payload: {'originalMessageId': originalMessageId},
      timestamp: DateTime.now(),
      status: AppConstants.messageStatusSent,
    );
  }

  static Message createTypingIndicator({
    required String senderId,
    required String receiverId,
  }) {
    return Message(
      id: const Uuid().v4(),
      type: AppConstants.messageTypeTyping,
      senderId: senderId,
      receiverId: receiverId,
      payload: {},
      timestamp: DateTime.now(),
      status: AppConstants.messageStatusSent,
    );
  }

  /// An image message. The full image is transferred separately in chunks and
  /// written to disk; only a small [thumbnailBase64] plus metadata live in the
  /// payload (and thus in Hive). The on-disk path is derived deterministically
  /// from [transferId] + [fileName], so it is not stored here.
  static Message createImageMessage({
    required String senderId,
    required String receiverId,
    required String transferId,
    required String thumbnailBase64,
    required String fileName,
    required int fileSize,
    required int width,
    required int height,
  }) {
    return Message(
      id: const Uuid().v4(),
      type: AppConstants.messageTypeImage,
      senderId: senderId,
      receiverId: receiverId,
      payload: {
        'transferId': transferId,
        'thumbnail': thumbnailBase64,
        'fileName': fileName,
        'fileSize': fileSize,
        'width': width,
        'height': height,
      },
      timestamp: DateTime.now(),
      status: AppConstants.messageStatusSending,
    );
  }

  /// A file message. Like an image, the bytes are streamed separately in chunks
  /// and written to disk; the payload only carries metadata.
  static Message createFileMessage({
    required String senderId,
    required String receiverId,
    required String transferId,
    required String fileName,
    required int fileSize,
  }) {
    return Message(
      id: const Uuid().v4(),
      type: AppConstants.messageTypeFile,
      senderId: senderId,
      receiverId: receiverId,
      payload: {
        'transferId': transferId,
        'fileName': fileName,
        'fileSize': fileSize,
      },
      timestamp: DateTime.now(),
      status: AppConstants.messageStatusSending,
    );
  }

  /// A voice message: an audio file streamed like any other attachment, with
  /// its duration carried in the payload so the bubble can show it.
  static Message createVoiceMessage({
    required String senderId,
    required String receiverId,
    required String transferId,
    required String fileName,
    required int fileSize,
    required int durationMs,
  }) {
    return Message(
      id: const Uuid().v4(),
      type: AppConstants.messageTypeVoice,
      senderId: senderId,
      receiverId: receiverId,
      payload: {
        'transferId': transferId,
        'fileName': fileName,
        'fileSize': fileSize,
        'durationMs': durationMs,
      },
      timestamp: DateTime.now(),
      status: AppConstants.messageStatusSending,
    );
  }

  /// A single chunk of a binary transfer (image, file, or voice). Ephemeral —
  /// routed and reassembled, never persisted.
  static Message createFileChunk({
    required String senderId,
    required String receiverId,
    required String transferId,
    required int index,
    required int total,
    required String dataBase64,
  }) {
    return Message(
      id: const Uuid().v4(),
      type: AppConstants.messageTypeFileChunk,
      senderId: senderId,
      receiverId: receiverId,
      payload: {
        'transferId': transferId,
        'index': index,
        'total': total,
        'data': dataBase64,
      },
      timestamp: DateTime.now(),
      status: AppConstants.messageStatusSent,
    );
  }

  String? get textContent => payload['message'] as String?;
  String? get originalMessageId => payload['originalMessageId'] as String?;

  /// The group this message belongs to, if any (present on group messages).
  String? get groupId => payload['groupId'] as String?;
  bool get isGroupMessage => groupId != null;

  /// The group definition carried by a group_invite control message.
  Map<String, dynamic>? get groupInvitePayload =>
      payload['group'] as Map<String, dynamic>?;

  /// A short one-line preview for conversation lists and notifications.
  String get previewText {
    if (isImage) return '📷 Photo';
    if (isVoice) return '🎤 Voice message';
    if (isFile) return '📎 ${attachmentName ?? 'File'}';
    return textContent ?? '';
  }

  // Transfer accessors shared by image, file, and voice messages.
  bool get isImage => type == AppConstants.messageTypeImage;
  bool get isFile => type == AppConstants.messageTypeFile;
  bool get isVoice => type == AppConstants.messageTypeVoice;
  bool get isAttachment => isImage || isFile || isVoice;
  String? get transferId => payload['transferId'] as String?;
  String? get attachmentName => payload['fileName'] as String?;
  int get attachmentSize => (payload['fileSize'] as num?)?.toInt() ?? 0;
  int get voiceDurationMs => (payload['durationMs'] as num?)?.toInt() ?? 0;

  // Image-specific accessors.
  String? get thumbnailBase64 => payload['thumbnail'] as String?;
  int get imageWidth => (payload['width'] as num?)?.toInt() ?? 0;
  int get imageHeight => (payload['height'] as num?)?.toInt() ?? 0;

  bool get isControlMessage =>
      type == AppConstants.messageTypeDeliveryAck ||
      type == AppConstants.messageTypeReadReceipt ||
      type == AppConstants.messageTypeTyping ||
      type == AppConstants.messageTypeFileChunk ||
      type == AppConstants.messageTypeGroupInvite;
}
