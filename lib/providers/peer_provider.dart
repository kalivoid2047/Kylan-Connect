import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/peer_device.dart';
import '../repositories/peer_repository.dart';
import '../services/discovery_service.dart';

final activePeersProvider = StateNotifierProvider<ActivePeersNotifier, List<PeerDevice>>((ref) {
  return ActivePeersNotifier();
});

class ActivePeersNotifier extends StateNotifier<List<PeerDevice>> {
  ActivePeersNotifier() : super([]) {
    _init();
  }
  
  void _init() {
    DiscoveryService.instance.onPeerDiscovered.listen((peer) {
      _updatePeers();
    });
    
    DiscoveryService.instance.onPeerLeft.listen((deviceId) {
      _updatePeers();
    });
    
    _updatePeers();
  }
  
  void _updatePeers() {
    state = PeerRepository.instance.getActivePeers();
  }
  
  void refresh() {
    _updatePeers();
  }
}

final cachedPeersProvider = FutureProvider<List<PeerDevice>>((ref) async {
  return PeerRepository.instance.getCachedPeers();
});

final peerCountProvider = Provider<int>((ref) {
  final peers = ref.watch(activePeersProvider);
  return peers.length;
});
