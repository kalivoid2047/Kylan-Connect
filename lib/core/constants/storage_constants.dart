class StorageConstants {
  // Box Names
  static const String userProfileBox = 'user_profile_box';
  static const String conversationsBox = 'conversations_box';
  static const String messagesBox = 'messages_box';
  static const String peersBox = 'peers_box';
  static const String settingsBox = 'settings_box';
  static const String keysBox = 'keys_box';
  static const String groupsBox = 'groups_box';

  // Key Names
  static const String currentProfileKey = 'current_profile';
  static const String devicePrivateKeyKey = 'device_private_key';
  static const String devicePublicKeyKey = 'device_public_key';
  static const String pinnedPeerKeyPrefix = 'peer_pub_';
  static const String settingsKey = 'settings';
  static const String themeKey = 'theme_mode';
  static const String languageKey = 'language';
  static const String notificationsEnabledKey = 'notifications_enabled';
  
  // Cache Configuration
  static const int maxCachedPeers = 100;
  static const int maxCachedMessages = 1000;
  static const Duration cacheExpiry = Duration(days: 7);
  
  // Backup Configuration
  static const bool enableAutoBackup = true;
  static const Duration backupInterval = Duration(hours: 24);
}
