import '../core/errors/failures.dart';
import '../models/group.dart';
import '../services/messaging_service.dart';
import '../services/storage_service.dart';
import '../core/utils/app_logger.dart';

class GroupRepository {
  static final GroupRepository _instance = GroupRepository._internal();
  static GroupRepository get instance => _instance;

  GroupRepository._internal();

  Group? getGroup(String groupId) {
    try {
      return StorageService.instance.getGroup(groupId);
    } catch (e, stackTrace) {
      AppLogger.instance.error('Failed to get group', e, stackTrace);
      return null;
    }
  }

  /// Whether [conversationId] refers to a group rather than a 1:1 chat.
  bool isGroup(String conversationId) => getGroup(conversationId) != null;

  List<Group> getAllGroups() {
    try {
      return StorageService.instance.getAllGroups();
    } catch (e, stackTrace) {
      AppLogger.instance.error('Failed to get groups', e, stackTrace);
      return [];
    }
  }

  Future<Group> createGroup({
    required String name,
    required List<String> memberIds,
    required String avatarColor,
  }) async {
    try {
      return await MessagingService.instance.createGroup(
        name: name,
        memberIds: memberIds,
        avatarColor: avatarColor,
      );
    } catch (e, stackTrace) {
      AppLogger.instance.error('Failed to create group', e, stackTrace);
      throw MessagingFailure('Failed to create group', e);
    }
  }

  Future<void> sendGroupMessage({
    required String groupId,
    required String text,
  }) async {
    try {
      await MessagingService.instance.sendGroupMessage(
        groupId: groupId,
        text: text,
      );
    } catch (e, stackTrace) {
      AppLogger.instance.error('Failed to send group message', e, stackTrace);
      throw MessagingFailure('Failed to send group message', e);
    }
  }

  Future<void> deleteGroup(String groupId) async {
    try {
      await StorageService.instance.deleteGroup(groupId);
      await StorageService.instance.deleteConversation(groupId);
      AppLogger.instance.debug('Group deleted: $groupId');
    } catch (e, stackTrace) {
      AppLogger.instance.error('Failed to delete group', e, stackTrace);
      throw StorageFailure('Failed to delete group', e);
    }
  }
}
