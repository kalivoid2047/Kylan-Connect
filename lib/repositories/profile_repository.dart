import 'dart:io';
import 'package:uuid/uuid.dart';
import '../core/constants/app_constants.dart';
import '../core/errors/failures.dart';
import '../models/user_profile.dart';
import '../services/storage_service.dart';
import '../core/utils/app_logger.dart';

class ProfileRepository {
  static final ProfileRepository _instance = ProfileRepository._internal();
  static ProfileRepository get instance => _instance;
  
  ProfileRepository._internal();
  
  Future<UserProfile?> getProfile() async {
    try {
      return StorageService.instance.getUserProfile();
    } catch (e, stackTrace) {
      AppLogger.instance.error('Failed to get profile', e, stackTrace);
      throw StorageFailure('Failed to get profile', e);
    }
  }
  
  Future<bool> hasProfile() async {
    try {
      return StorageService.instance.getUserProfile() != null;
    } catch (e, stackTrace) {
      AppLogger.instance.error('Failed to check profile existence', e, stackTrace);
      return false;
    }
  }
  
  Future<UserProfile> createProfile({
    required String displayName,
    required String avatarColor,
  }) async {
    try {
      final deviceId = const Uuid().v4();
      final now = DateTime.now();
      
      final profile = UserProfile(
        deviceId: deviceId,
        displayName: displayName,
        avatarColor: avatarColor,
        createdAt: now,
        lastUpdated: now,
      );
      
      await StorageService.instance.saveUserProfile(profile);
      AppLogger.instance.info('Profile created: $displayName');
      
      return profile;
    } catch (e, stackTrace) {
      AppLogger.instance.error('Failed to create profile', e, stackTrace);
      throw StorageFailure('Failed to create profile', e);
    }
  }
  
  Future<UserProfile> updateProfile({
    String? displayName,
    String? avatarColor,
  }) async {
    try {
      final currentProfile = StorageService.instance.getUserProfile();
      if (currentProfile == null) {
        throw const ValidationFailure('No profile exists');
      }
      
      final updatedProfile = currentProfile.copyWith(
        displayName: displayName ?? currentProfile.displayName,
        avatarColor: avatarColor ?? currentProfile.avatarColor,
        lastUpdated: DateTime.now(),
      );
      
      await StorageService.instance.saveUserProfile(updatedProfile);
      AppLogger.instance.info('Profile updated');
      
      return updatedProfile;
    } catch (e, stackTrace) {
      AppLogger.instance.error('Failed to update profile', e, stackTrace);
      throw StorageFailure('Failed to update profile', e);
    }
  }
  
  Future<void> deleteProfile() async {
    try {
      await StorageService.instance.deleteUserProfile();
      AppLogger.instance.info('Profile deleted');
    } catch (e, stackTrace) {
      AppLogger.instance.error('Failed to delete profile', e, stackTrace);
      throw StorageFailure('Failed to delete profile', e);
    }
  }
  
  String getPlatform() {
    if (Platform.isAndroid) return AppConstants.platformAndroid;
    if (Platform.isIOS) return AppConstants.platformIOS;
    if (Platform.isWindows) return AppConstants.platformWindows;
    if (Platform.isMacOS) return AppConstants.platformMacOS;
    if (Platform.isLinux) return AppConstants.platformLinux;
    return 'unknown';
  }
}
