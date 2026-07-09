import 'package:flutter_test/flutter_test.dart';
import 'package:kylan_connect/services/mdns_codec.dart';

void main() {
  group('MdnsCodec', () {
    test('encodes and decodes a peer round-trip', () {
      final txt = MdnsCodec.encode(
        deviceId: 'device-123',
        deviceName: 'Alice',
        avatarColor: '#4ECDC4',
        platform: 'android',
        appVersion: '1.0.0',
        publicKey: 'base64publickey==',
      );

      final packet = MdnsCodec.decode(txt, ipAddress: '192.168.1.42');
      expect(packet, isNotNull);
      expect(packet!.deviceId, equals('device-123'));
      expect(packet.deviceName, equals('Alice'));
      expect(packet.avatarColor, equals('#4ECDC4'));
      expect(packet.platform, equals('android'));
      expect(packet.appVersion, equals('1.0.0'));
      expect(packet.publicKey, equals('base64publickey=='));
      expect(packet.ipAddress, equals('192.168.1.42'));
    });

    test('omits the public key when not advertised', () {
      final txt = MdnsCodec.encode(
        deviceId: 'd',
        deviceName: 'n',
        avatarColor: '#fff',
        platform: 'ios',
        appVersion: '1.0.0',
      );
      expect(txt.containsKey(MdnsCodec.kPublicKey), isFalse);

      final packet = MdnsCodec.decode(txt, ipAddress: '10.0.0.1');
      expect(packet!.publicKey, isNull);
    });

    test('deviceIdOf prefers the TXT id, falling back to the service name', () {
      final txt = MdnsCodec.encode(
        deviceId: 'txt-id',
        deviceName: 'n',
        avatarColor: '#fff',
        platform: 'ios',
        appVersion: '1',
      );
      expect(MdnsCodec.deviceIdOf(txt, 'svc-name'), equals('txt-id'));
      expect(MdnsCodec.deviceIdOf(null, 'svc-name'), equals('svc-name'));
      expect(MdnsCodec.deviceIdOf(null, null), isNull);
    });

    test('decode returns null without a reachable IP', () {
      final txt = MdnsCodec.encode(
        deviceId: 'd',
        deviceName: 'n',
        avatarColor: '#fff',
        platform: 'ios',
        appVersion: '1',
      );
      expect(MdnsCodec.decode(txt, ipAddress: null), isNull);
      expect(MdnsCodec.decode(txt, ipAddress: ''), isNull);
    });

    test('decode returns null without a device id', () {
      expect(
        MdnsCodec.decode(<String, List<int>?>{}, ipAddress: '10.0.0.1'),
        isNull,
      );
    });

    test('falls back to service name for identity when TXT lacks id', () {
      final packet = MdnsCodec.decode(
        <String, List<int>?>{},
        ipAddress: '10.0.0.5',
        serviceName: 'peer-from-name',
      );
      expect(packet, isNotNull);
      expect(packet!.deviceId, equals('peer-from-name'));
      expect(packet.deviceName, equals('Unknown'));
    });
  });
}
