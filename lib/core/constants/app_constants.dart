class AppConstants {
  // App Information
  static const String appName = 'Kylan Connect';
  static const String appVersion = '1.0.0';
  
  // Network Configuration
  static const int discoveryPort = 54321;
  static const int messagingPort = 54322;
  static const int broadcastIntervalSeconds = 5;
  static const int peerTimeoutSeconds = 15;
  static const int maxRetries = 3;
  static const int connectionTimeoutSeconds = 10;
  
  // Message Configuration
  static const int maxMessageRetries = 3;
  static const int messageRetryDelayMs = 1000;
  
  // Storage Configuration
  static const String hiveBoxName = 'kylan_connect';
  static const String userProfileKey = 'user_profile';
  static const String conversationsKey = 'conversations';
  static const String messagesKey = 'messages';
  static const String peersKey = 'peers';
  static const String settingsKey = 'settings';
  
  // Encryption Configuration
  static const int encryptionKeyLength = 32; // 256 bits
  static const int ivLength = 16; // 128 bits
  
  // UI Configuration
  static const int maxMessageLength = 1000;
  static const int maxDisplayNameLength = 30;
  static const int minDisplayNameLength = 2;
  
  // Message Types
  static const String messageTypeText = 'text';
  static const String messageTypeImage = 'image';
  static const String messageTypeVoice = 'voice';
  static const String messageTypeFile = 'file';
  static const String messageTypeTyping = 'typing';
  
  // Message Status
  static const String messageStatusSending = 'sending';
  static const String messageStatusSent = 'sent';
  static const String messageStatusDelivered = 'delivered';
  static const String messageStatusFailed = 'failed';
  
  // Avatar Colors
  static const List<String> avatarColors = [
    '#FF6B6B',
    '#4ECDC4',
    '#45B7D1',
    '#96CEB4',
    '#FFEAA7',
    '#DDA0DD',
    '#98D8C8',
    '#F7DC6F',
    '#BB8FCE',
    '#85C1E9',
  ];
  
  // Platform
  static const String platformAndroid = 'android';
  static const String platformIOS = 'ios';
  static const String platformWindows = 'windows';
  static const String platformMacOS = 'macos';
  static const String platformLinux = 'linux';
}
