class NetworkConstants {
  // Discovery Protocol
  static const String discoveryProtocol = 'UDP';
  static const String messagingProtocol = 'TCP';
  
  // Packet Sizes
  static const int maxPacketSize = 65507; // UDP max packet size
  static const int bufferSize = 8192;
  
  // Timeouts
  static const Duration discoveryTimeout = Duration(seconds: 30);
  static const Duration connectionTimeout = Duration(seconds: 10);
  static const Duration readTimeout = Duration(seconds: 30);
  static const Duration writeTimeout = Duration(seconds: 30);
  
  // Retry Configuration
  static const int maxConnectionAttempts = 3;
  static const Duration retryDelay = Duration(seconds: 2);
  
  // Keep Alive
  static const Duration keepAliveInterval = Duration(seconds: 30);
  static const Duration peerExpiryTimeout = Duration(seconds: 15);
  
  // Broadcast Configuration
  static const String broadcastAddress = '255.255.255.255';
  static const bool enableBroadcast = true;
  static const bool allowReuseAddress = true;
}
