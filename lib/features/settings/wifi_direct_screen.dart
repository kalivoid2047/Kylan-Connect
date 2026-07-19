import 'dart:async';

import 'package:flutter/material.dart';
import '../../services/wifi_direct_service.dart';

/// Experimental, Android-only screen for forming a direct WiFi Direct link to
/// a nearby device when there's no shared router/access point. Once
/// connected, regular device discovery and messaging take over automatically
/// — this screen only establishes the link.
class WifiDirectScreen extends StatefulWidget {
  const WifiDirectScreen({super.key});

  @override
  State<WifiDirectScreen> createState() => _WifiDirectScreenState();
}

class _WifiDirectScreenState extends State<WifiDirectScreen> {
  final _service = WifiDirectService.instance;

  bool _starting = false;
  bool _discovering = false;
  bool _connected = false;
  List<WifiDirectPeer> _peers = [];
  StreamSubscription<List<WifiDirectPeer>>? _peersSubscription;
  StreamSubscription<bool>? _connectionSubscription;

  @override
  void initState() {
    super.initState();
    _peersSubscription = _service.onPeersUpdated.listen((peers) {
      if (mounted) setState(() => _peers = peers);
    });
    _connectionSubscription = _service.onConnectionChanged.listen((connected) {
      if (mounted) setState(() => _connected = connected);
    });
  }

  @override
  void dispose() {
    _peersSubscription?.cancel();
    _connectionSubscription?.cancel();
    super.dispose();
  }

  Future<void> _enable() async {
    setState(() => _starting = true);
    try {
      final initialized = await _service.initialize();
      if (!initialized) {
        _showSnack('Could not start WiFi Direct — permission denied or '
            'unsupported on this device.');
        return;
      }
      final discovering = await _service.startDiscovery();
      if (!discovering) {
        _showSnack('WiFi Direct discovery failed to start. Make sure '
            'Location is turned on in system settings, then try again.');
        return;
      }
      if (mounted) setState(() => _discovering = true);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _stop() async {
    await _service.stopDiscovery();
    await _service.disconnect();
    if (mounted) setState(() => _discovering = false);
  }

  Future<void> _connectTo(WifiDirectPeer peer) async {
    final ok = await _service.connect(peer.deviceAddress);
    if (!ok) _showSnack('Failed to connect to ${peer.deviceName}');
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (!_service.isSupported) {
      return Scaffold(
        appBar: AppBar(title: const Text('WiFi Direct')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'WiFi Direct is only available on Android.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('WiFi Direct')),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.science_outlined,
                        size: 18, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      'Experimental',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Use this when two devices have no shared WiFi router. Pick a '
                  'nearby device below to form a direct link — once connected, '
                  'Kylan Connect discovers and messages it exactly like any '
                  'other device on the network.',
                ),
              ],
            ),
          ),
          if (_connected)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: Colors.green.withValues(alpha: 0.15),
              child: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 18),
                  SizedBox(width: 8),
                  Text('Connected — searching for the peer on this link…'),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _starting
                        ? null
                        : (_discovering ? _stop : _enable),
                    icon: Icon(_discovering ? Icons.stop : Icons.wifi_tethering),
                    label: Text(_starting
                        ? 'Starting…'
                        : (_discovering
                            ? 'Stop'
                            : 'Enable WiFi Direct')),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: !_discovering
                ? const Center(
                    child: Text('Enable WiFi Direct to see nearby devices'),
                  )
                : _peers.isEmpty
                    ? const Center(child: Text('Searching for devices…'))
                    : ListView.builder(
                        itemCount: _peers.length,
                        itemBuilder: (context, index) {
                          final peer = _peers[index];
                          return ListTile(
                            leading: const Icon(Icons.smartphone),
                            title: Text(peer.deviceName),
                            subtitle: Text(peer.statusText),
                            trailing: TextButton(
                              onPressed: () => _connectTo(peer),
                              child: const Text('Connect'),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
