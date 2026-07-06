import '../core/errors/failures.dart';
import '../models/app_settings.dart';
import '../services/storage_service.dart';
import '../core/utils/app_logger.dart';

class SettingsRepository {
  static final SettingsRepository _instance = SettingsRepository._internal();
  static SettingsRepository get instance => _instance;
  
  SettingsRepository._internal();
  
  Future<AppSettings> getSettings() async {
    try {
      return StorageService.instance.getSettings() ?? AppSettings.createDefault();
    } catch (e, stackTrace) {
      AppLogger.instance.error('Failed to get settings', e, stackTrace);
      throw StorageFailure('Failed to get settings', e);
    }
  }
  
  Future<AppSettings> updateThemeMode(String themeMode) async {
    try {
      final currentSettings = await getSettings();
      final updatedSettings = currentSettings.copyWith(
        themeMode: themeMode,
        lastUpdated: DateTime.now(),
      );
      await StorageService.instance.saveSettings(updatedSettings);
      AppLogger.instance.info('Theme mode updated: $themeMode');
      return updatedSettings;
    } catch (e, stackTrace) {
      AppLogger.instance.error('Failed to update theme mode', e, stackTrace);
      throw StorageFailure('Failed to update theme mode', e);
    }
  }
  
  Future<AppSettings> updateNotificationsEnabled(bool enabled) async {
    try {
      final currentSettings = await getSettings();
      final updatedSettings = currentSettings.copyWith(
        notificationsEnabled: enabled,
        lastUpdated: DateTime.now(),
      );
      await StorageService.instance.saveSettings(updatedSettings);
      AppLogger.instance.info('Notifications ${enabled ? "enabled" : "disabled"}');
      return updatedSettings;
    } catch (e, stackTrace) {
      AppLogger.instance.error('Failed to update notifications', e, stackTrace);
      throw StorageFailure('Failed to update notifications', e);
    }
  }
  
  Future<AppSettings> updateSoundEnabled(bool enabled) async {
    try {
      final currentSettings = await getSettings();
      final updatedSettings = currentSettings.copyWith(
        soundEnabled: enabled,
        lastUpdated: DateTime.now(),
      );
      await StorageService.instance.saveSettings(updatedSettings);
      AppLogger.instance.info('Sound ${enabled ? "enabled" : "disabled"}');
      return updatedSettings;
    } catch (e, stackTrace) {
      AppLogger.instance.error('Failed to update sound', e, stackTrace);
      throw StorageFailure('Failed to update sound', e);
    }
  }
  
  Future<AppSettings> updateVibrationEnabled(bool enabled) async {
    try {
      final currentSettings = await getSettings();
      final updatedSettings = currentSettings.copyWith(
        vibrationEnabled: enabled,
        lastUpdated: DateTime.now(),
      );
      await StorageService.instance.saveSettings(updatedSettings);
      AppLogger.instance.info('Vibration ${enabled ? "enabled" : "disabled"}');
      return updatedSettings;
    } catch (e, stackTrace) {
      AppLogger.instance.error('Failed to update vibration', e, stackTrace);
      throw StorageFailure('Failed to update vibration', e);
    }
  }
  
  Future<void> resetSettings() async {
    try {
      final defaultSettings = AppSettings.createDefault();
      await StorageService.instance.saveSettings(defaultSettings);
      AppLogger.instance.info('Settings reset to default');
    } catch (e, stackTrace) {
      AppLogger.instance.error('Failed to reset settings', e, stackTrace);
      throw StorageFailure('Failed to reset settings', e);
    }
  }
}
