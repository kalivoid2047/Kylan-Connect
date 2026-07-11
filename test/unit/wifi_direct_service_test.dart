import 'package:flutter_test/flutter_test.dart';
import 'package:kylan_connect/services/wifi_direct_service.dart';
import 'package:wifi_direct_plugin/wifi_direct_plugin_platform_interface.dart';

void main() {
  group('WifiDirectPeer.fromNative', () {
    WifiDirectDevice device({
      String deviceName = 'Pixel 8',
      String deviceAddress = '02:00:00:00:00:01',
      int? status,
    }) {
      return WifiDirectDevice(
        deviceName: deviceName,
        deviceAddress: deviceAddress,
        deviceMacAddress: deviceAddress,
        status: status,
      );
    }

    test('carries the device name and address through', () {
      final peer = WifiDirectPeer.fromNative(device());
      expect(peer.deviceName, equals('Pixel 8'));
      expect(peer.deviceAddress, equals('02:00:00:00:00:01'));
    });

    test('falls back to a placeholder name when empty', () {
      final peer = WifiDirectPeer.fromNative(device(deviceName: ''));
      expect(peer.deviceName, equals('Unknown device'));
    });

    test('maps every known WifiP2pDevice status code to a readable label', () {
      const expected = {
        0: 'Connected',
        1: 'Invited',
        2: 'Failed',
        3: 'Available',
        4: 'Unavailable',
      };
      for (final entry in expected.entries) {
        final peer = WifiDirectPeer.fromNative(device(status: entry.key));
        expect(peer.statusText, equals(entry.value),
            reason: 'status ${entry.key}');
      }
    });

    test('falls back to Unknown for an unrecognized or missing status', () {
      expect(WifiDirectPeer.fromNative(device(status: 99)).statusText,
          equals('Unknown'));
      expect(WifiDirectPeer.fromNative(device(status: null)).statusText,
          equals('Unknown'));
    });
  });

  group('WifiDirectService', () {
    test('isSupported reflects the current platform', () {
      // In the test VM (desktop host), WiFi Direct is never supported.
      expect(WifiDirectService.instance.isSupported, isFalse);
    });

    test('initialize/startDiscovery/connect are no-ops off Android', () async {
      final service = WifiDirectService.instance;
      expect(await service.initialize(), isFalse);
      expect(await service.startDiscovery(), isFalse);
      expect(await service.connect('02:00:00:00:00:01'), isFalse);
      expect(service.isInitialized, isFalse);
    });
  });
}
