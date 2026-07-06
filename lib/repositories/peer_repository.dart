import '../core/errors/failures.dart';
import '../models/peer_device.dart';
import '../services/discovery_service.dart';
import '../services/storage_service.dart';
import '../core/utils/app_logger.dart';

class PeerRepository {
  static final PeerRepository _instance = PeerRepository._internal();
  static PeerRepository get instance => _instance;
  
  PeerRepository._internal();
  
  List<PeerDevice> getActivePeers() {
    try {
      return DiscoveryService.instance.activePeers;
    } catch (e, stackTrace) {
      AppLogger.instance.error('Failed to get active peers', e, stackTrace);
      throw NetworkFailure('Failed to get active peers', e);
    }
  }
  
  PeerDevice? getPeer(String deviceId) {
    try {
      return DiscoveryService.instance.getPeer(deviceId);
    } catch (e, stackTrace) {
      AppLogger.instance.error('Failed to get peer', e, stackTrace);
      throw NetworkFailure('Failed to get peer', e);
    }
  }
  
  List<PeerDevice> getCachedPeers() {
    try {
      return StorageService.instance.getAllPeers();
    } catch (e, stackTrace) {
      AppLogger.instance.error('Failed to get cached peers', e, stackTrace);
      throw StorageFailure('Failed to get cached peers', e);
    }
  }
  
  Future<void> cachePeer(PeerDevice peer) async {
    try {
      await StorageService.instance.savePeer(peer);
      AppLogger.instance.debug('Peer cached: ${peer.displayName}');
    } catch (e, stackTrace) {
      AppLogger.instance.error('Failed to cache peer', e, stackTrace);
      throw StorageFailure('Failed to cache peer', e);
    }
  }
  
  Future<void> removePeer(String deviceId) async {
    try {
      DiscoveryService.instance.removePeer(deviceId);
      await StorageService.instance.removePeer(deviceId);
      AppLogger.instance.debug('Peer removed: $deviceId');
    } catch (e, stackTrace) {
      AppLogger.instance.error('Failed to remove peer', e, stackTrace);
      throw StorageFailure('Failed to remove peer', e);
    }
  }
  
  Future<void> clearExpiredPeers() async {
    try {
      await StorageService.instance.clearExpiredPeers();
      AppLogger.instance.debug('Expired peers cleared');
    } catch (e, stackTrace) {
      AppLogger.instance.error('Failed to clear expired peers', e, stackTrace);
      throw StorageFailure('Failed to clear expired peers', e);
    }
  }
  
  Future<void> clearAllPeers() async {
    try {
      await StorageService.instance.clearCache();
      AppLogger.instance.debug('All peers cleared');
    } catch (e, stackTrace) {
      AppLogger.instance.error('Failed to clear all peers', e, stackTrace);
      throw StorageFailure('Failed to clear all peers', e);
    }
  }
}
