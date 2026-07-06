import 'package:flutter_test/flutter_test.dart';
import 'package:kylan_connect/core/security/encryption_service.dart';

void main() {
  group('EncryptionService', () {
    late EncryptionService encryptionService;
    const deviceIdA = 'device-aaa-111';
    const deviceIdB = 'device-bbb-222';

    setUp(() {
      encryptionService = EncryptionService.instance;
    });

    test('should encrypt and decrypt text using a conversation key', () {
      const plaintext = 'Hello, World!';
      final key = encryptionService.getConversationKey(deviceIdA, deviceIdB);

      final encrypted = encryptionService.encryptWithKey(plaintext, key);
      final decrypted = encryptionService.decryptWithKey(encrypted, key);

      expect(decrypted, equals(plaintext));
    });

    test('should produce different ciphertext for the same plaintext (random IV)', () {
      const plaintext = 'Hello, World!';
      final key = encryptionService.getConversationKey(deviceIdA, deviceIdB);

      final encrypted1 = encryptionService.encryptWithKey(plaintext, key);
      final encrypted2 = encryptionService.encryptWithKey(plaintext, key);

      expect(encrypted1, isNot(equals(encrypted2)));
    });

    test('both peers derive the same conversation key regardless of argument order', () {
      final keyAB = encryptionService.getConversationKey(deviceIdA, deviceIdB);
      final keyBA = encryptionService.getConversationKey(deviceIdB, deviceIdA);

      const plaintext = 'symmetric key test';
      final encrypted = encryptionService.encryptWithKey(plaintext, keyAB);
      final decrypted = encryptionService.decryptWithKey(encrypted, keyBA);

      expect(decrypted, equals(plaintext));
    });

    test('should encrypt and decrypt JSON using a conversation key', () {
      final json = {'message': 'Hello', 'sender': 'Alice'};
      final key = encryptionService.getConversationKey(deviceIdA, deviceIdB);

      final encrypted = encryptionService.encryptJsonWithKey(json, key);
      final decrypted = encryptionService.decryptJsonWithKey(encrypted, key);

      expect(decrypted, equals(json));
    });

    test('should hash input consistently', () {
      const input = 'test_input';

      final hash1 = encryptionService.hash(input);
      final hash2 = encryptionService.hash(input);

      expect(hash1, equals(hash2));
    });

    test('should produce different hashes for different inputs', () {
      final hash1 = encryptionService.hash('input1');
      final hash2 = encryptionService.hash('input2');

      expect(hash1, isNot(equals(hash2)));
    });
  });
}
