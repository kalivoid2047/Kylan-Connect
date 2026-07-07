import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:kylan_connect/core/errors/exceptions.dart';
import 'package:kylan_connect/core/security/crypto_service.dart';
import 'package:kylan_connect/services/storage_service.dart';

void main() {
  late Directory tempDir;
  late String peerPublicKeyBase64;

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('kylan_crypto_test');
    await StorageService.instance.initializeForTest(tempDir.path);
    await CryptoService.instance.ensureIdentityKeys();

    // A second, valid X25519 public key standing in for a remote peer.
    final peerKeyPair = await X25519().newKeyPair();
    final peerPublic = await peerKeyPair.extractPublicKey();
    peerPublicKeyBase64 = base64.encode(peerPublic.bytes);
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('Identity keys', () {
    test('are generated and expose a public key', () {
      expect(CryptoService.instance.isReady, isTrue);
      expect(CryptoService.instance.publicKeyBase64, isNotEmpty);
    });

    test('are stable across reload (persisted seed)', () async {
      final before = CryptoService.instance.publicKeyBase64;

      CryptoService.instance.resetForTest();
      expect(CryptoService.instance.isReady, isFalse);

      await CryptoService.instance.ensureIdentityKeys();
      expect(CryptoService.instance.publicKeyBase64, equals(before));
    });
  });

  group('Peer key pinning (TOFU)', () {
    test('pins on first sighting and rejects a changed key', () async {
      final other = await X25519().newKeyPair();
      final otherPub = base64.encode((await other.extractPublicKey()).bytes);

      expect(
        CryptoService.instance.pinPeerPublicKey('peer-tofu', peerPublicKeyBase64),
        isTrue,
      );
      // Same key again is fine.
      expect(
        CryptoService.instance.pinPeerPublicKey('peer-tofu', peerPublicKeyBase64),
        isTrue,
      );
      // A different key for the same peer is rejected.
      expect(
        CryptoService.instance.pinPeerPublicKey('peer-tofu', otherPub),
        isFalse,
      );
    });
  });

  group('AES-GCM messaging', () {
    setUp(() {
      CryptoService.instance.pinPeerPublicKey('peer-1', peerPublicKeyBase64);
    });

    test('round-trips a message', () async {
      const plaintext = 'Hello, encrypted world!';
      final ciphertext =
          await CryptoService.instance.encryptFor('peer-1', plaintext);
      final decrypted =
          await CryptoService.instance.decryptFrom('peer-1', ciphertext);
      expect(decrypted, equals(plaintext));
    });

    test('produces a different ciphertext each time (random nonce)', () async {
      const plaintext = 'same message';
      final a = await CryptoService.instance.encryptFor('peer-1', plaintext);
      final b = await CryptoService.instance.encryptFor('peer-1', plaintext);
      expect(a, isNot(equals(b)));
    });

    test('rejects tampered ciphertext (authentication)', () async {
      final ciphertext =
          await CryptoService.instance.encryptFor('peer-1', 'authentic');
      final bytes = base64.decode(ciphertext);
      bytes[bytes.length - 1] ^= 0xFF; // flip a bit in the MAC
      final tampered = base64.encode(bytes);

      expect(
        () => CryptoService.instance.decryptFrom('peer-1', tampered),
        throwsA(anything),
      );
    });

    test('throws when no key is pinned for the peer', () async {
      expect(
        () => CryptoService.instance.encryptFor('unknown-peer', 'hi'),
        throwsA(isA<CryptoException>()),
      );
      expect(CryptoService.instance.canEncryptFor('unknown-peer'), isFalse);
      expect(CryptoService.instance.canEncryptFor('peer-1'), isTrue);
    });
  });

  group('Fingerprint', () {
    test('is deterministic and 16 hex chars', () async {
      final fp1 = await CryptoService.fingerprintOf(peerPublicKeyBase64);
      final fp2 = await CryptoService.fingerprintOf(peerPublicKeyBase64);
      expect(fp1, equals(fp2));
      expect(fp1.length, equals(16));
      expect(RegExp(r'^[0-9a-f]{16}$').hasMatch(fp1), isTrue);
    });
  });
}
