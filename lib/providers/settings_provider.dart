import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_settings.dart';
import '../repositories/settings_repository.dart';

final settingsProvider = StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
  return SettingsNotifier();
});

class SettingsNotifier extends StateNotifier<AppSettings> {
  SettingsNotifier() : super(AppSettings.createDefault()) {
    _loadSettings();
  }
  
  Future<void> _loadSettings() async {
    try {
      final settings = await SettingsRepository.instance.getSettings();
      state = settings;
    } catch (e) {
      state = AppSettings.createDefault();
    }
  }
  
  Future<void> updateThemeMode(String themeMode) async {
    final settings = await SettingsRepository.instance.updateThemeMode(themeMode);
    state = settings;
  }
  
  Future<void> updateNotificationsEnabled(bool enabled) async {
    final settings = await SettingsRepository.instance.updateNotificationsEnabled(enabled);
    state = settings;
  }
  
  Future<void> updateSoundEnabled(bool enabled) async {
    final settings = await SettingsRepository.instance.updateSoundEnabled(enabled);
    state = settings;
  }
  
  Future<void> updateVibrationEnabled(bool enabled) async {
    final settings = await SettingsRepository.instance.updateVibrationEnabled(enabled);
    state = settings;
  }
  
  Future<void> resetSettings() async {
    await SettingsRepository.instance.resetSettings();
    await _loadSettings();
  }
}

final themeModeProvider = Provider<ThemeMode>((ref) {
  final settings = ref.watch(settingsProvider);
  switch (settings.themeMode) {
    case 'light':
      return ThemeMode.light;
    case 'dark':
      return ThemeMode.dark;
    default:
      return ThemeMode.system;
  }
});

final notificationsEnabledProvider = Provider<bool>((ref) {
  final settings = ref.watch(settingsProvider);
  return settings.notificationsEnabled;
});
