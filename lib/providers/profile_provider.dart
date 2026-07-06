import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_profile.dart';
import '../repositories/profile_repository.dart';
import '../services/app_startup_service.dart';

final profileProvider = StateNotifierProvider<ProfileNotifier, UserProfile?>((ref) {
  return ProfileNotifier();
});

class ProfileNotifier extends StateNotifier<UserProfile?> {
  ProfileNotifier() : super(null) {
    _loadProfile();
  }
  
  Future<void> _loadProfile() async {
    try {
      final profile = await ProfileRepository.instance.getProfile();
      state = profile;
    } catch (e) {
      state = null;
    }
  }
  
  Future<void> createProfile({
    required String displayName,
    required String avatarColor,
  }) async {
    try {
      final profile = await ProfileRepository.instance.createProfile(
        displayName: displayName,
        avatarColor: avatarColor,
      );
      state = profile;
      await AppStartupService.instance.startPeerServices(profile);
    } catch (e) {
      rethrow;
    }
  }
  
  Future<void> updateProfile({
    String? displayName,
    String? avatarColor,
  }) async {
    try {
      final profile = await ProfileRepository.instance.updateProfile(
        displayName: displayName,
        avatarColor: avatarColor,
      );
      state = profile;
      await AppStartupService.instance.startPeerServices(profile);
    } catch (e) {
      rethrow;
    }
  }
  
  Future<void> deleteProfile() async {
    try {
      await ProfileRepository.instance.deleteProfile();
      state = null;
      await AppStartupService.instance.stopPeerServices();
    } catch (e) {
      rethrow;
    }
  }
}

final hasProfileProvider = Provider<bool>((ref) {
  final profile = ref.watch(profileProvider);
  return profile != null;
});
