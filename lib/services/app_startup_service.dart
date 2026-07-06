import '../core/utils/app_logger.dart';
import '../models/user_profile.dart';
import '../repositories/profile_repository.dart';
import 'background_service.dart';
import 'connection_manager.dart';
import 'discovery_service.dart';
import 'messaging_service.dart';
import 'storage_service.dart';

class AppStartupService {
  static final AppStartupService _instance = AppStartupService._internal();
  static AppStartupService get instance => _instance;

  bool _isInitialized = false;

  AppStartupService._internal();

  Future<void> initialize() async {
    if (_isInitialized) return;

    await StorageService.instance.initialize();

    final profile = await ProfileRepository.instance.getProfile();
    if (profile != null) {
      await startPeerServices(profile);
    }

    _isInitialized = true;
  }

  Future<void> startPeerServices(UserProfile profile) async {
    await MessagingService.instance.initialize(profile.deviceId);

    try {
      await DiscoveryService.instance.initialize(
        deviceId: profile.deviceId,
        deviceName: profile.displayName,
        avatarColor: profile.avatarColor,
      );
      await DiscoveryService.instance.startDiscovery();
    } catch (e, stackTrace) {
      AppLogger.instance
          .warning('Discovery service could not be started: $e');
      AppLogger.instance.error('Discovery startup stack trace', e, stackTrace);
    }

    try {
      await ConnectionManager.instance.startServer();
    } catch (e, stackTrace) {
      AppLogger.instance
          .warning('Connection manager could not be started: $e');
      AppLogger.instance
          .error('Connection manager startup stack trace', e, stackTrace);
    }

    // Start the platform background service so discovery and connections
    // survive when the app is moved to the background.
    await BackgroundService.instance.start();
  }

  Future<void> stopPeerServices() async {
    try {
      await BackgroundService.instance.stop();
      await DiscoveryService.instance.stopDiscovery();
      await ConnectionManager.instance.stopServer();
    } catch (e, stackTrace) {
      AppLogger.instance.error('Failed to stop peer services', e, stackTrace);
    }
  }
}
