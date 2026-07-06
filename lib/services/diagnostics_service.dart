import 'dart:io';
import '../core/constants/app_constants.dart';
import '../services/connection_manager.dart';
import '../services/discovery_service.dart';
import '../services/storage_service.dart';
import '../core/utils/app_logger.dart';

class DiagnosticsInfo {
  final String localIpAddress;
  final String deviceId;
  final bool tcpServerRunning;
  final bool discoveryServiceRunning;
  final int activeConnections;
  final int knownPeers;
  final int totalConversations;
  final int totalMessages;
  final String platform;
  final String appVersion;
  
  DiagnosticsInfo({
    required this.localIpAddress,
    required this.deviceId,
    required this.tcpServerRunning,
    required this.discoveryServiceRunning,
    required this.activeConnections,
    required this.knownPeers,
    required this.totalConversations,
    required this.totalMessages,
    required this.platform,
    required this.appVersion,
  });
  
  Map<String, dynamic> toJson() => {
    'localIpAddress': localIpAddress,
    'deviceId': deviceId,
    'tcpServerRunning': tcpServerRunning,
    'discoveryServiceRunning': discoveryServiceRunning,
    'activeConnections': activeConnections,
    'knownPeers': knownPeers,
    'totalConversations': totalConversations,
    'totalMessages': totalMessages,
    'platform': platform,
    'appVersion': appVersion,
  };
}

class DiagnosticsService {
  static final DiagnosticsService _instance = DiagnosticsService._internal();
  static DiagnosticsService get instance => _instance;
  
  DiagnosticsService._internal();
  
  Future<DiagnosticsInfo> getDiagnosticsInfo() async {
    try {
      final userProfile = StorageService.instance.getUserProfile();
      final localIp = await _getLocalIpAddress();
      
      final conversations = StorageService.instance.getAllConversations();
      int totalMessages = 0;
      for (final conv in conversations) {
        totalMessages += StorageService.instance.getMessages(conv.conversationId).length;
      }
      
      return DiagnosticsInfo(
        localIpAddress: localIp,
        deviceId: userProfile?.deviceId ?? 'Unknown',
        tcpServerRunning: ConnectionManager.instance.isRunning,
        discoveryServiceRunning: DiscoveryService.instance.isRunning,
        activeConnections: ConnectionManager.instance.connectedPeers.length,
        knownPeers: DiscoveryService.instance.activePeers.length,
        totalConversations: conversations.length,
        totalMessages: totalMessages,
        platform: _getPlatform(),
        appVersion: AppConstants.appVersion,
      );
    } catch (e, stackTrace) {
      AppLogger.instance.error('Failed to get diagnostics info', e, stackTrace);
      rethrow;
    }
  }
  
  Future<String> _getLocalIpAddress() async {
    try {
      final interfaces = await NetworkInterface.list(includeLoopback: false, type: InternetAddressType.IPv4);
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            return addr.address;
          }
        }
      }
      return 'Unknown';
    } catch (e) {
      AppLogger.instance.warning('Failed to get local IP address: $e');
      return 'Unknown';
    }
  }
  
  Future<bool> testConnection(String ipAddress) async {
    try {
      final socket = await Socket.connect(
        ipAddress,
        AppConstants.messagingPort,
        timeout: const Duration(seconds: 5),
      );
      socket.destroy();
      AppLogger.instance.info('Connection test successful for $ipAddress');
      return true;
    } catch (e) {
      AppLogger.instance.warning('Connection test failed for $ipAddress: $e');
      return false;
    }
  }
  
  Future<void> restartDiscovery() async {
    try {
      await DiscoveryService.instance.stopDiscovery();
      await Future.delayed(const Duration(seconds: 1));
      await DiscoveryService.instance.startDiscovery();
      AppLogger.instance.info('Discovery service restarted');
    } catch (e, stackTrace) {
      AppLogger.instance.error('Failed to restart discovery service', e, stackTrace);
      rethrow;
    }
  }
  
  Future<void> restartConnectionManager() async {
    try {
      await ConnectionManager.instance.stopServer();
      await Future.delayed(const Duration(seconds: 1));
      await ConnectionManager.instance.startServer();
      AppLogger.instance.info('Connection manager restarted');
    } catch (e, stackTrace) {
      AppLogger.instance.error('Failed to restart connection manager', e, stackTrace);
      rethrow;
    }
  }
  
  Future<void> refreshPeers() async {
    try {
      await StorageService.instance.clearExpiredPeers();
      AppLogger.instance.info('Peers refreshed');
    } catch (e, stackTrace) {
      AppLogger.instance.error('Failed to refresh peers', e, stackTrace);
      rethrow;
    }
  }
  
  Future<Map<String, dynamic>> exportDiagnostics() async {
    final info = await getDiagnosticsInfo();
    final peers = DiscoveryService.instance.activePeers.map((p) => p.toJson()).toList();
    final conversations = StorageService.instance.getAllConversations().map((c) => c.toJson()).toList();
    
    return {
      'diagnostics': info.toJson(),
      'peers': peers,
      'conversations': conversations,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }
  
  String _getPlatform() {
    if (Platform.isAndroid) return AppConstants.platformAndroid;
    if (Platform.isIOS) return AppConstants.platformIOS;
    if (Platform.isWindows) return AppConstants.platformWindows;
    if (Platform.isMacOS) return AppConstants.platformMacOS;
    if (Platform.isLinux) return AppConstants.platformLinux;
    return 'unknown';
  }
}
