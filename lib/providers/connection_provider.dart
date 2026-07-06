import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/connection_manager.dart';
import '../services/discovery_service.dart';

final connectionStatusProvider = StateNotifierProvider<ConnectionStatusNotifier, ConnectionStatus>((ref) {
  return ConnectionStatusNotifier();
});

class ConnectionStatusNotifier extends StateNotifier<ConnectionStatus> {
  ConnectionStatusNotifier() : super(ConnectionStatus.disconnected) {
    _monitorConnection();
  }
  
  void _monitorConnection() {
    DiscoveryService.instance.onPeerDiscovered.listen((_) {
      state = ConnectionStatus.connected;
    });

    DiscoveryService.instance.onPeerLeft.listen((_) {
      _checkStatus();
    });

    ConnectionManager.instance.onPeerConnected.listen((_) {
      state = ConnectionStatus.connected;
    });

    ConnectionManager.instance.onPeerDisconnected.listen((_) {
      _checkStatus();
    });

    _checkStatus();
  }
  
  void _checkStatus() {
    if (!DiscoveryService.instance.isRunning &&
        !ConnectionManager.instance.isRunning) {
      state = ConnectionStatus.disconnected;
    } else if (DiscoveryService.instance.activePeers.isNotEmpty ||
        ConnectionManager.instance.connectedPeers.isNotEmpty) {
      state = ConnectionStatus.connected;
    } else {
      state = ConnectionStatus.searching;
    }
  }
  
  void refresh() {
    _checkStatus();
  }
}

enum ConnectionStatus {
  disconnected,
  searching,
  connected,
}

final activeConnectionsProvider = Provider<int>((ref) {
  return ConnectionManager.instance.connectedPeers.length;
});
