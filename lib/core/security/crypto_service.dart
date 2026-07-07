import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../errors/exceptions.dart';
import '../utils/app_logger.dart';
import '../../services/storage_service.dart';

/// End-to-end cryptography for Kylan Connect.
///
/// Each device owns a long-lived X25519 identity keypair. A per-peer session
/// key is derived non-interactively via ECDH:
///
///   shared = X25519(myPrivate, peerPublic) == X25519(peerPrivate, myPublic)
///   sessionKey = HKDF-SHA256(shared, salt = sha256(sorted(pubA, pubB)),
///                            info = "kylan-connect-v1")
///
/// Both peers compute the identical key from their own private key plus the
/// other's public key (broadcast in discovery), so no interactive handshake is
/// required. Messages are sealed with AES-GCM, which authenticates them.
///
/// Security notes:
/// - A passive eavesdropper on the LAN sees only public keys and cannot derive
///   the session key without a private key.
/// - Peer public keys are pinned on first sighting (trust-on-first-use). A
///   later key change for the same deviceId is surfaced as a possible spoof.
/// - The keys are static, so this construction does NOT provide per-message
///   forward secrecy. A future enhancement could add an ephemeral-key handshake.
class CryptoService {
  static final CryptoService _instance = CryptoService._internal();
  static CryptoService get instance => _instance;

  CryptoService._internal();

  static const String _hkdfInfo = 'kylan-connect-v1';

  final X25519 _x25519 = X25519();
  final AesGcm _aesGcm = AesGcm.with256bits();
  final Hkdf _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  SimpleKeyPair? _identityKeyPair;
  List<int>? _identityPublicKeyBytes;

  /// Derived AES-GCM session keys, cached by peer deviceId.
  final Map<String, SecretKey> _sessionKeys = {};

  bool get isReady => _identityKeyPair != null;

  /// Our own X25519 public key, base64-encoded. Broadcast in discovery so
  /// peers can derive the shared session key.
  String get publicKeyBase64 {
    if (_identityPublicKeyBytes == null) {
      throw const CryptoException('Identity keys not initialized');
    }
    return base64.encode(_identityPublicKeyBytes!);
  }

  /// A short, human-comparable fingerprint of our public key (for future
  /// out-of-band "safety number" verification).
  Future<String> get fingerprint async =>
      fingerprintOf(publicKeyBase64);

  /// Loads the device identity keypair from storage, generating and persisting
  /// a new one on first run. Safe to call repeatedly.
  Future<void> ensureIdentityKeys() async {
    if (_identityKeyPair != null) return;

    final storedPrivate = StorageService.instance.getDevicePrivateKey();
    final storedPublic = StorageService.instance.getDevicePublicKey();

    if (storedPrivate != null && storedPublic != null) {
      _identityKeyPair = await _x25519.newKeyPairFromSeed(
        base64.decode(storedPrivate),
      );
      _identityPublicKeyBytes = base64.decode(storedPublic);
      AppLogger.instance.info('Loaded existing device identity keypair');
      return;
    }

    // Generate a fresh keypair. We persist the 32-byte seed (private key) and
    // reconstruct the keypair from it on subsequent launches.
    final seed = _randomBytes(32);
    _identityKeyPair = await _x25519.newKeyPairFromSeed(seed);
    final publicKey = await _identityKeyPair!.extractPublicKey();
    _identityPublicKeyBytes = publicKey.bytes;

    await StorageService.instance.saveDeviceKeys(
      base64.encode(seed),
      base64.encode(_identityPublicKeyBytes!),
    );
    AppLogger.instance.info('Generated new device identity keypair');
  }

  /// Records a peer's public key on first sighting (trust-on-first-use).
  /// Returns false if the peer was already pinned to a *different* key, which
  /// indicates a possible spoof or man-in-the-middle attempt.
  bool pinPeerPublicKey(String peerDeviceId, String peerPublicKeyBase64) {
    final existing =
        StorageService.instance.getPinnedPeerPublicKey(peerDeviceId);

    if (existing == null) {
      StorageService.instance.pinPeerPublicKey(peerDeviceId, peerPublicKeyBase64);
      return true;
    }

    if (existing != peerPublicKeyBase64) {
      AppLogger.instance.warning(
          'Public key for peer $peerDeviceId changed — possible spoof/MITM. '
          'Keeping the originally pinned key.');
      // Invalidate any cached session so we never encrypt to an unpinned key.
      _sessionKeys.remove(peerDeviceId);
      return false;
    }

    return true;
  }

  /// Returns the AES-GCM session key for [peerDeviceId], deriving it from the
  /// pinned peer public key if not already cached. Throws if no key is pinned.
  Future<SecretKey> sessionKeyFor(String peerDeviceId) async {
    final cached = _sessionKeys[peerDeviceId];
    if (cached != null) return cached;

    final pinned =
        StorageService.instance.getPinnedPeerPublicKey(peerDeviceId);
    if (pinned == null) {
      throw CryptoException(
          'No public key known for peer $peerDeviceId — cannot derive key');
    }

    final key = await _deriveSessionKey(base64.decode(pinned));
    _sessionKeys[peerDeviceId] = key;
    return key;
  }

  /// True when we hold (or can derive) a session key for the peer.
  bool canEncryptFor(String peerDeviceId) =>
      _sessionKeys.containsKey(peerDeviceId) ||
      StorageService.instance.getPinnedPeerPublicKey(peerDeviceId) != null;

  Future<SecretKey> _deriveSessionKey(List<int> peerPublicKeyBytes) async {
    if (_identityKeyPair == null) {
      throw const CryptoException('Identity keys not initialized');
    }

    final peerPublicKey = SimplePublicKey(
      peerPublicKeyBytes,
      type: KeyPairType.x25519,
    );

    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair: _identityKeyPair!,
      remotePublicKey: peerPublicKey,
    );

    // Bind the derived key to both identities by salting with a sorted hash of
    // the two public keys, so the salt is identical on both peers.
    final salt = await _saltFor(peerPublicKeyBytes);

    return _hkdf.deriveKey(
      secretKey: sharedSecret,
      nonce: salt,
      info: utf8.encode(_hkdfInfo),
    );
  }

  Future<List<int>> _saltFor(List<int> peerPublicKeyBytes) async {
    final mine = base64.encode(_identityPublicKeyBytes!);
    final theirs = base64.encode(peerPublicKeyBytes);
    final ordered = [mine, theirs]..sort();
    final digest =
        await Sha256().hash(utf8.encode('${ordered[0]}:${ordered[1]}'));
    return digest.bytes;
  }

  /// Encrypts [plaintext] for [peerDeviceId], returning base64(nonce|cipher|mac).
  Future<String> encryptFor(String peerDeviceId, String plaintext) async {
    final key = await sessionKeyFor(peerDeviceId);
    final secretBox = await _aesGcm.encrypt(
      utf8.encode(plaintext),
      secretKey: key,
    );
    final combined = Uint8List.fromList([
      ...secretBox.nonce,
      ...secretBox.cipherText,
      ...secretBox.mac.bytes,
    ]);
    return base64.encode(combined);
  }

  /// Decrypts a payload produced by [encryptFor] from [peerDeviceId].
  Future<String> decryptFrom(String peerDeviceId, String ciphertextBase64) async {
    final key = await sessionKeyFor(peerDeviceId);
    final combined = base64.decode(ciphertextBase64);

    const nonceLength = 12; // AES-GCM standard nonce
    const macLength = 16; // 128-bit tag
    if (combined.length < nonceLength + macLength) {
      throw const CryptoException('Ciphertext too short');
    }

    final nonce = combined.sublist(0, nonceLength);
    final cipherText =
        combined.sublist(nonceLength, combined.length - macLength);
    final mac = Mac(combined.sublist(combined.length - macLength));

    final clear = await _aesGcm.decrypt(
      SecretBox(cipherText, nonce: nonce, mac: mac),
      secretKey: key,
    );
    return utf8.decode(clear);
  }

  /// A short fingerprint (first 16 hex chars of SHA-256) of a base64 public key.
  static Future<String> fingerprintOf(String publicKeyBase64) async {
    final digest =
        await Sha256().hash(base64.decode(publicKeyBase64));
    final hex = digest.bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return hex.substring(0, 16);
  }

  Uint8List _randomBytes(int length) {
    final secretKey = SecretKeyData.random(length: length);
    return Uint8List.fromList(secretKey.bytes);
  }

  /// Test-only reset so the singleton can be exercised deterministically.
  void resetForTest() {
    _identityKeyPair = null;
    _identityPublicKeyBytes = null;
    _sessionKeys.clear();
  }
}
