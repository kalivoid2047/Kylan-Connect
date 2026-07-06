import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import '../core/constants/storage_constants.dart';
import '../exceptions/storage_exception.dart';
import '../models/app_settings.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../models/peer_device.dart';
import '../models/user_profile.dart';
import '../core/utils/app_logger.dart';

class StorageService {
  static final StorageService _instance = StorageService._internal();
  static StorageService get instance => _instance;

  late Box<UserProfile> _userProfileBox;
  late Box<Conversation> _conversationsBox;
  late Box<dynamic> _messagesBox;
  late Box<PeerDevice> _peersBox;
  late Box<AppSettings> _settingsBox;

  bool _isInitialized = false;

  StorageService._internal();

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      if (kIsWeb) {
        await Hive.initFlutter();
      } else {
        final appDocDir = await getApplicationDocumentsDirectory();
        await Hive.initFlutter(appDocDir.path);
      }

      // Register adapters
      _registerAdapters();

      // Open boxes
      _userProfileBox =
          await Hive.openBox<UserProfile>(StorageConstants.userProfileBox);
      _conversationsBox =
          await Hive.openBox<Conversation>(StorageConstants.conversationsBox);
      _messagesBox = await Hive.openBox<dynamic>(StorageConstants.messagesBox);
      _peersBox = await Hive.openBox<PeerDevice>(StorageConstants.peersBox);
      _settingsBox =
          await Hive.openBox<AppSettings>(StorageConstants.settingsBox);

      _isInitialized = true;
      AppLogger.instance.info('Storage service initialized successfully');
    } catch (e, stackTrace) {
      AppLogger.instance
          .error('Failed to initialize storage service', e, stackTrace);
      throw StorageException('Failed to initialize storage service', e);
    }
  }

  /// Test-only initializer. Uses [Hive.init] (pure Dart, no platform channels)
  /// against a caller-provided [path] so services can be exercised in unit
  /// tests without `path_provider`. Do not call from production code.
  @visibleForTesting
  Future<void> initializeForTest(String path) async {
    if (_isInitialized) return;

    Hive.init(path);
    _registerAdapters();

    _userProfileBox =
        await Hive.openBox<UserProfile>(StorageConstants.userProfileBox);
    _conversationsBox =
        await Hive.openBox<Conversation>(StorageConstants.conversationsBox);
    _messagesBox = await Hive.openBox<dynamic>(StorageConstants.messagesBox);
    _peersBox = await Hive.openBox<PeerDevice>(StorageConstants.peersBox);
    _settingsBox =
        await Hive.openBox<AppSettings>(StorageConstants.settingsBox);

    _isInitialized = true;
  }

  void _registerAdapters() {
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(UserProfileAdapter());
    }
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(PeerDeviceAdapter());
    }
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(MessageAdapter());
    }
    if (!Hive.isAdapterRegistered(3)) {
      Hive.registerAdapter(ConversationAdapter());
    }
    if (!Hive.isAdapterRegistered(4)) {
      Hive.registerAdapter(AppSettingsAdapter());
    }
  }

  // User Profile Operations
  Future<void> saveUserProfile(UserProfile profile) async {
    try {
      await _userProfileBox.put(StorageConstants.currentProfileKey, profile);
      AppLogger.instance.debug('User profile saved');
    } catch (e, stackTrace) {
      AppLogger.instance.error('Failed to save user profile', e, stackTrace);
      throw StorageException('Failed to save user profile', e);
    }
  }

  UserProfile? getUserProfile() {
    try {
      return _userProfileBox.get(StorageConstants.currentProfileKey);
    } catch (e, stackTrace) {
      AppLogger.instance.error('Failed to get user profile', e, stackTrace);
      throw StorageException('Failed to get user profile', e);
    }
  }

  Future<void> deleteUserProfile() async {
    try {
      await _userProfileBox.delete(StorageConstants.currentProfileKey);
      AppLogger.instance.debug('User profile deleted');
    } catch (e, stackTrace) {
      AppLogger.instance.error('Failed to delete user profile', e, stackTrace);
      throw StorageException('Failed to delete user profile', e);
    }
  }

  // Conversation Operations
  Future<void> saveConversation(Conversation conversation) async {
    try {
      await _conversationsBox.put(conversation.conversationId, conversation);
      AppLogger.instance
          .debug('Conversation saved: ${conversation.conversationId}');
    } catch (e, stackTrace) {
      AppLogger.instance.error('Failed to save conversation', e, stackTrace);
      throw StorageException('Failed to save conversation', e);
    }
  }

  List<Conversation> getAllConversations() {
    try {
      return _conversationsBox.values.toList()
        ..sort((a, b) {
          final timeA =
              a.lastMessageTime ?? DateTime.fromMillisecondsSinceEpoch(0);
          final timeB =
              b.lastMessageTime ?? DateTime.fromMillisecondsSinceEpoch(0);
          return timeB.compareTo(timeA);
        });
    } catch (e, stackTrace) {
      AppLogger.instance.error('Failed to get conversations', e, stackTrace);
      throw StorageException('Failed to get conversations', e);
    }
  }

  Conversation? getConversation(String conversationId) {
    try {
      return _conversationsBox.get(conversationId);
    } catch (e, stackTrace) {
      AppLogger.instance.error('Failed to get conversation', e, stackTrace);
      throw StorageException('Failed to get conversation', e);
    }
  }

  Future<void> deleteConversation(String conversationId) async {
    try {
      await _conversationsBox.delete(conversationId);
      await _messagesBox.delete(conversationId);
      AppLogger.instance.debug('Conversation deleted: $conversationId');
    } catch (e, stackTrace) {
      AppLogger.instance.error('Failed to delete conversation', e, stackTrace);
      throw StorageException('Failed to delete conversation', e);
    }
  }

  Future<void> clearAllConversations() async {
    try {
      await _conversationsBox.clear();
      await _messagesBox.clear();
      AppLogger.instance.debug('All conversations cleared');
    } catch (e, stackTrace) {
      AppLogger.instance.error('Failed to clear conversations', e, stackTrace);
      throw StorageException('Failed to clear conversations', e);
    }
  }

  // Message Operations
  Future<void> saveMessage(String conversationId, Message message) async {
    try {
      final messages = _messagesBox.get(conversationId);
      final messageList =
          messages != null ? List<Message>.from(messages) : <Message>[];
      messageList.add(message);
      await _messagesBox.put(conversationId, messageList);
      AppLogger.instance.debug('Message saved: ${message.id}');
    } catch (e, stackTrace) {
      AppLogger.instance.error('Failed to save message', e, stackTrace);
      throw StorageException('Failed to save message', e);
    }
  }

  List<Message> getMessages(String conversationId) {
    try {
      final messages = _messagesBox.get(conversationId);
      if (messages == null) {
        return [];
      }
      return List<Message>.from(messages)
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    } catch (e, stackTrace) {
      AppLogger.instance.error('Failed to get messages', e, stackTrace);
      throw StorageException('Failed to get messages', e);
    }
  }

  List<Message> getMessagesPaginated(
    String conversationId, {
    int limit = 50,
    int offset = 0,
  }) {
    try {
      final messages = _messagesBox.get(conversationId);
      if (messages == null) {
        return [];
      }
      final sortedMessages = List<Message>.from(messages)
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

      final total = sortedMessages.length;
      final start = (total - offset - limit).clamp(0, total);
      final end = (total - offset).clamp(0, total);

      return sortedMessages.sublist(start, end);
    } catch (e, stackTrace) {
      AppLogger.instance
          .error('Failed to get paginated messages', e, stackTrace);
      throw StorageException('Failed to get paginated messages', e);
    }
  }

  int getMessageCount(String conversationId) {
    try {
      final messages = _messagesBox.get(conversationId);
      if (messages == null) {
        return 0;
      }
      return (messages as List).length;
    } catch (e, stackTrace) {
      AppLogger.instance.error('Failed to get message count', e, stackTrace);
      throw StorageException('Failed to get message count', e);
    }
  }

  Future<void> replaceMessages(
      String conversationId, List<Message> messages) async {
    try {
      await _messagesBox.put(conversationId, List<Message>.from(messages));
      AppLogger.instance.debug('Messages replaced: $conversationId');
    } catch (e, stackTrace) {
      AppLogger.instance.error('Failed to replace messages', e, stackTrace);
      throw StorageException('Failed to replace messages', e);
    }
  }

  Future<void> updateMessageStatus(
      String conversationId, String messageId, String status) async {
    try {
      final messages = _messagesBox.get(conversationId);
      if (messages != null) {
        final messageList = List<Message>.from(messages);
        final index = messageList.indexWhere((m) => m.id == messageId);
        if (index != -1) {
          messageList[index] = messageList[index].copyWith(status: status);
          await _messagesBox.put(conversationId, messageList);
          AppLogger.instance
              .debug('Message status updated: $messageId -> $status');
        }
      }
    } catch (e, stackTrace) {
      AppLogger.instance
          .error('Failed to update message status', e, stackTrace);
      throw StorageException('Failed to update message status', e);
    }
  }

  // Offline Message Queue Operations
  Future<void> enqueueOfflineMessage(Message message) async {
    try {
      final queue = _messagesBox.get('offline_queue') as List<Message>?;
      final messageQueue = queue ?? <Message>[];
      messageQueue.add(message);
      await _messagesBox.put('offline_queue', messageQueue);
      AppLogger.instance
          .debug('Message enqueued for offline delivery: ${message.id}');
    } catch (e, stackTrace) {
      AppLogger.instance
          .error('Failed to enqueue offline message', e, stackTrace);
      throw StorageException('Failed to enqueue offline message', e);
    }
  }

  List<Message> getOfflineQueue() {
    try {
      final queue = _messagesBox.get('offline_queue') as List<Message>?;
      return queue ?? [];
    } catch (e, stackTrace) {
      AppLogger.instance.error('Failed to get offline queue', e, stackTrace);
      throw StorageException('Failed to get offline queue', e);
    }
  }

  List<Message> getOfflineMessagesForPeer(String peerId) {
    try {
      final queue = getOfflineQueue();
      return queue.where((message) => message.receiverId == peerId).toList();
    } catch (e, stackTrace) {
      AppLogger.instance
          .error('Failed to get offline messages for peer', e, stackTrace);
      throw StorageException('Failed to get offline messages for peer', e);
    }
  }

  Future<void> removeOfflineMessage(String messageId) async {
    try {
      final queue = _messagesBox.get('offline_queue') as List<Message>?;
      if (queue != null) {
        final messageQueue = List<Message>.from(queue);
        messageQueue.removeWhere((m) => m.id == messageId);
        await _messagesBox.put('offline_queue', messageQueue);
        AppLogger.instance
            .debug('Message removed from offline queue: $messageId');
      }
    } catch (e, stackTrace) {
      AppLogger.instance
          .error('Failed to remove offline message', e, stackTrace);
      throw StorageException('Failed to remove offline message', e);
    }
  }

  Future<void> clearOfflineQueueForPeer(String peerId) async {
    try {
      final queue = _messagesBox.get('offline_queue') as List<Message>?;
      if (queue != null) {
        final messageQueue = List<Message>.from(queue);
        final removedCount =
            messageQueue.where((m) => m.receiverId == peerId).length;
        messageQueue.removeWhere((m) => m.receiverId == peerId);
        await _messagesBox.put('offline_queue', messageQueue);
        AppLogger.instance
            .debug('Cleared $removedCount offline messages for peer: $peerId');
      }
    } catch (e, stackTrace) {
      AppLogger.instance
          .error('Failed to clear offline queue for peer', e, stackTrace);
      throw StorageException('Failed to clear offline queue for peer', e);
    }
  }

  // Peer Device Operations
  Future<void> savePeer(PeerDevice peer) async {
    try {
      await _peersBox.put(peer.deviceId, peer);
      AppLogger.instance.debug('Peer saved: ${peer.deviceId}');
    } catch (e, stackTrace) {
      AppLogger.instance.error('Failed to save peer', e, stackTrace);
      throw StorageException('Failed to save peer', e);
    }
  }

  List<PeerDevice> getAllPeers() {
    try {
      return _peersBox.values.toList();
    } catch (e, stackTrace) {
      AppLogger.instance.error('Failed to get peers', e, stackTrace);
      throw StorageException('Failed to get peers', e);
    }
  }

  PeerDevice? getPeer(String deviceId) {
    try {
      return _peersBox.get(deviceId);
    } catch (e, stackTrace) {
      AppLogger.instance.error('Failed to get peer', e, stackTrace);
      throw StorageException('Failed to get peer', e);
    }
  }

  Future<void> removePeer(String deviceId) async {
    try {
      await _peersBox.delete(deviceId);
      AppLogger.instance.debug('Peer removed: $deviceId');
    } catch (e, stackTrace) {
      AppLogger.instance.error('Failed to remove peer', e, stackTrace);
      throw StorageException('Failed to remove peer', e);
    }
  }

  Future<void> clearExpiredPeers() async {
    try {
      final now = DateTime.now();
      final expiredPeers = _peersBox.values
          .where((peer) => now.difference(peer.lastSeen).inSeconds > 15)
          .map((peer) => peer.deviceId)
          .toList();

      for (final deviceId in expiredPeers) {
        await _peersBox.delete(deviceId);
      }

      if (expiredPeers.isNotEmpty) {
        AppLogger.instance
            .debug('Cleared ${expiredPeers.length} expired peers');
      }
    } catch (e, stackTrace) {
      AppLogger.instance.error('Failed to clear expired peers', e, stackTrace);
      throw StorageException('Failed to clear expired peers', e);
    }
  }

  // Settings Operations
  Future<void> saveSettings(AppSettings settings) async {
    try {
      await _settingsBox.put(StorageConstants.settingsKey, settings);
      AppLogger.instance.debug('Settings saved');
    } catch (e, stackTrace) {
      AppLogger.instance.error('Failed to save settings', e, stackTrace);
      throw StorageException('Failed to save settings', e);
    }
  }

  AppSettings? getSettings() {
    try {
      return _settingsBox.get(StorageConstants.settingsKey);
    } catch (e, stackTrace) {
      AppLogger.instance.error('Failed to get settings', e, stackTrace);
      throw StorageException('Failed to get settings', e);
    }
  }

  // Cache Management
  Future<void> clearCache() async {
    try {
      await _peersBox.clear();
      AppLogger.instance.debug('Cache cleared');
    } catch (e, stackTrace) {
      AppLogger.instance.error('Failed to clear cache', e, stackTrace);
      throw StorageException('Failed to clear cache', e);
    }
  }

  Future<void> clearAllData() async {
    try {
      await _userProfileBox.clear();
      await _conversationsBox.clear();
      await _messagesBox.clear();
      await _peersBox.clear();
      await _settingsBox.clear();
      AppLogger.instance.info('All data cleared');
    } catch (e, stackTrace) {
      AppLogger.instance.error('Failed to clear all data', e, stackTrace);
      throw StorageException('Failed to clear all data', e);
    }
  }

  Future<void> close() async {
    try {
      await _userProfileBox.close();
      await _conversationsBox.close();
      await _messagesBox.close();
      await _peersBox.close();
      await _settingsBox.close();
      _isInitialized = false;
      AppLogger.instance.info('Storage service closed');
    } catch (e, stackTrace) {
      AppLogger.instance
          .error('Failed to close storage service', e, stackTrace);
      throw StorageException('Failed to close storage service', e);
    }
  }

  bool get isInitialized => _isInitialized;
}
