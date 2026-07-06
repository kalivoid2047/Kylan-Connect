import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart';
import '../constants/app_constants.dart';
import '../errors/exceptions.dart';
import '../utils/app_logger.dart';

class EncryptionService {
  static final EncryptionService _instance = EncryptionService._internal();
  static EncryptionService get instance => _instance;

  EncryptionService._internal();

  /// Returns a deterministic AES-256 key derived from two device IDs.
  /// IDs are sorted before hashing so both peers always compute the same key
  /// regardless of who initiates the conversation.
  Key getConversationKey(String deviceId1, String deviceId2) {
    final ids = [deviceId1, deviceId2]..sort();
    final combined = '${ids[0]}:${ids[1]}';
    final keyBytes = sha256.convert(utf8.encode(combined)).bytes;
    return Key(Uint8List.fromList(keyBytes));
  }

  Uint8List _generateRandomBytes(int length) {
    final random = Random.secure();
    final bytes = Uint8List(length);
    for (int i = 0; i < length; i++) {
      bytes[i] = random.nextInt(256);
    }
    return bytes;
  }

  /// Encrypts [plaintext] with [key]. Prepends a random IV to the ciphertext.
  String encryptWithKey(String plaintext, Key key) {
    try {
      final ivBytes = _generateRandomBytes(AppConstants.ivLength);
      final iv = IV(ivBytes);
      final encrypter = Encrypter(AES(key));
      final encrypted = encrypter.encrypt(plaintext, iv: iv);
      final combined = Uint8List.fromList([...ivBytes, ...encrypted.bytes]);
      AppLogger.instance.debug('Message encrypted successfully');
      return base64.encode(combined);
    } catch (e, stackTrace) {
      AppLogger.instance.error('Encryption failed', e, stackTrace);
      throw EncryptionException('Encryption failed', e);
    }
  }

  /// Decrypts [ciphertext] produced by [encryptWithKey] using the same [key].
  String decryptWithKey(String ciphertext, Key key) {
    try {
      final combined = base64.decode(ciphertext);
      final ivBytes = combined.sublist(0, AppConstants.ivLength);
      final encryptedBytes = combined.sublist(AppConstants.ivLength);
      final iv = IV(ivBytes);
      final encrypter = Encrypter(AES(key));
      final encrypted = Encrypted(encryptedBytes);
      final decrypted = encrypter.decrypt(encrypted, iv: iv);
      AppLogger.instance.debug('Message decrypted successfully');
      return decrypted;
    } catch (e, stackTrace) {
      AppLogger.instance.error('Decryption failed', e, stackTrace);
      throw EncryptionException('Decryption failed', e);
    }
  }

  String encryptJsonWithKey(Map<String, dynamic> json, Key key) {
    try {
      final jsonString = jsonEncode(json);
      return encryptWithKey(jsonString, key);
    } catch (e, stackTrace) {
      AppLogger.instance.error('JSON encryption failed', e, stackTrace);
      throw EncryptionException('JSON encryption failed', e);
    }
  }

  Map<String, dynamic> decryptJsonWithKey(String ciphertext, Key key) {
    try {
      final jsonString = decryptWithKey(ciphertext, key);
      return jsonDecode(jsonString) as Map<String, dynamic>;
    } catch (e, stackTrace) {
      AppLogger.instance.error('JSON decryption failed', e, stackTrace);
      throw EncryptionException('JSON decryption failed', e);
    }
  }

  String hash(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
}
