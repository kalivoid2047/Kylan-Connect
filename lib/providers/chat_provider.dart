import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../repositories/chat_repository.dart';
import '../services/messaging_service.dart';

final conversationsProvider = StateNotifierProvider<ConversationsNotifier, List<Conversation>>((ref) {
  return ConversationsNotifier();
});

class ConversationsNotifier extends StateNotifier<List<Conversation>> {
  ConversationsNotifier() : super([]) {
    _loadConversations();
    
    MessagingService.instance.onMessageReceived.listen((message) {
      _loadConversations();
    });
  }
  
  Future<void> _loadConversations() async {
    try {
      final conversations = ChatRepository.instance.getConversations();
      state = conversations;
    } catch (e) {
      state = [];
    }
  }
  
  Future<void> refresh() async {
    await _loadConversations();
  }
  
  Future<void> deleteConversation(String conversationId) async {
    await ChatRepository.instance.deleteConversation(conversationId);
    await _loadConversations();
  }
  
  Future<void> clearAll() async {
    await ChatRepository.instance.clearAllConversations();
    await _loadConversations();
  }
}

final conversationMessagesProvider = FutureProvider.family<List<Message>, String>((ref, conversationId) async {
  return ChatRepository.instance.getMessages(conversationId);
});

final unreadCountProvider = Provider<int>((ref) {
  return ChatRepository.instance.getUnreadCount();
});

class ChatMessageNotifier extends StateNotifier<List<Message>> {
  ChatMessageNotifier(String conversationId) : super([]) {
    _loadMessages(conversationId);
    
    MessagingService.instance.onMessageReceived.listen((message) {
      // Only add if message belongs to this conversation
      // This is a simplified check - in production you'd want better filtering
      _loadMessages(conversationId);
    });
  }
  
  Future<void> _loadMessages(String conversationId) async {
    try {
      final messages = await ChatRepository.instance.getMessages(conversationId);
      state = messages;
    } catch (e) {
      state = [];
    }
  }
  
  Future<void> sendMessage({
    required String receiverId,
    required String receiverIp,
    required String text,
  }) async {
    final message = await ChatRepository.instance.sendMessage(
      receiverId: receiverId,
      receiverIp: receiverIp,
      text: text,
    );
    state = [...state, message];
  }
  
  Future<void> deleteMessage(String messageId) async {
    // Need conversationId here - this is simplified
    // In production, you'd pass conversationId to the notifier
  }
  
  Future<void> markAsRead(String conversationId) async {
    await ChatRepository.instance.markAsRead(conversationId);
  }
}
