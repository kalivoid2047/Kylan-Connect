import '../core/errors/failures.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../services/messaging_service.dart';
import '../services/storage_service.dart';
import '../core/utils/app_logger.dart';

class ChatRepository {
  static final ChatRepository _instance = ChatRepository._internal();
  static ChatRepository get instance => _instance;
  
  ChatRepository._internal();
  
  List<Conversation> getConversations() {
    try {
      return StorageService.instance.getAllConversations();
    } catch (e, stackTrace) {
      AppLogger.instance.error('Failed to get conversations', e, stackTrace);
      throw StorageFailure('Failed to get conversations', e);
    }
  }
  
  Conversation? getConversation(String conversationId) {
    try {
      return StorageService.instance.getConversation(conversationId);
    } catch (e, stackTrace) {
      AppLogger.instance.error('Failed to get conversation', e, stackTrace);
      throw StorageFailure('Failed to get conversation', e);
    }
  }
  
  Future<List<Message>> getMessages(String conversationId) async {
    try {
      return StorageService.instance.getMessages(conversationId);
    } catch (e, stackTrace) {
      AppLogger.instance.error('Failed to get messages', e, stackTrace);
      throw StorageFailure('Failed to get messages', e);
    }
  }
  
  Future<Message> sendMessage({
    required String receiverId,
    required String receiverIp,
    required String text,
  }) async {
    try {
      return await MessagingService.instance.sendMessage(
        receiverId: receiverId,
        receiverIp: receiverIp,
        text: text,
      );
    } catch (e, stackTrace) {
      AppLogger.instance.error('Failed to send message', e, stackTrace);
      throw MessagingFailure('Failed to send message', e);
    }
  }
  
  Future<void> markAsRead(String conversationId) async {
    try {
      await MessagingService.instance.markAsRead(conversationId);
      AppLogger.instance.debug('Conversation marked as read: $conversationId');
    } catch (e, stackTrace) {
      AppLogger.instance.error('Failed to mark as read', e, stackTrace);
      throw StorageFailure('Failed to mark as read', e);
    }
  }
  
  Future<void> deleteMessage(String conversationId, String messageId) async {
    try {
      await MessagingService.instance.deleteMessage(conversationId, messageId);
      AppLogger.instance.debug('Message deleted: $messageId');
    } catch (e, stackTrace) {
      AppLogger.instance.error('Failed to delete message', e, stackTrace);
      throw StorageFailure('Failed to delete message', e);
    }
  }
  
  Future<void> deleteConversation(String conversationId) async {
    try {
      await StorageService.instance.deleteConversation(conversationId);
      AppLogger.instance.debug('Conversation deleted: $conversationId');
    } catch (e, stackTrace) {
      AppLogger.instance.error('Failed to delete conversation', e, stackTrace);
      throw StorageFailure('Failed to delete conversation', e);
    }
  }
  
  Future<void> clearAllConversations() async {
    try {
      await StorageService.instance.clearAllConversations();
      AppLogger.instance.info('All conversations cleared');
    } catch (e, stackTrace) {
      AppLogger.instance.error('Failed to clear conversations', e, stackTrace);
      throw StorageFailure('Failed to clear conversations', e);
    }
  }
  
  int getUnreadCount() {
    try {
      final conversations = StorageService.instance.getAllConversations();
      return conversations.fold(0, (sum, conv) => sum + conv.unreadCount);
    } catch (e, stackTrace) {
      AppLogger.instance.error('Failed to get unread count', e, stackTrace);
      return 0;
    }
  }
}
