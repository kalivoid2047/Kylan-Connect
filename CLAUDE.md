# Kylan Connect - AI Assistant Context

## Project Overview
Kylan Connect is a production-ready offline peer-to-peer messaging platform that enables direct communication between devices on the same local network without requiring internet access or centralized servers.

## Tech Stack
- **Framework**: Flutter 3.19.0+
- **Language**: Dart 3.0.0+
- **State Management**: Riverpod
- **Local Storage**: Hive
- **Encryption**: cryptography package (X25519 + AES-256-GCM + HKDF)
- **Testing**: flutter_test, mockito

## Architecture
- **Pattern**: Clean Architecture with Feature-First approach
- **Networking**: UDP broadcast for discovery, TCP for messaging
- **Encryption**: X25519 ECDH → HKDF-SHA256 session key → AES-256-GCM (authenticated). Public keys broadcast in discovery and pinned trust-on-first-use.
- **Storage**: Hive for local persistence

## Development Roadmap

### Phase 0 — Foundation (COMPLETED)
- ✅ git init, initial commit, GitHub remote
- ✅ CI running flutter analyze + flutter test
- ✅ Delete stale default widget test
- ✅ Add CLAUDE.md
- ⏳ Decide the license

### Phase 1 — Security & reliability hardening (IN PROGRESS)
**Priority: Must complete before new features**

- ✅ **Real E2E encryption**: per-device X25519 keypair (persisted in Hive), non-interactive ECDH key agreement (public key broadcast in discovery), HKDF-SHA256 session key, AES-256-GCM for messages. Peer public keys are pinned trust-on-first-use to detect spoofing/MITM. Implemented in `CryptoService`. Tradeoff: static keys → no per-message forward secrecy (a future ephemeral-key handshake could add it); identity is still the UUID deviceId (not the fingerprint).
- ✅ **Delivery ACKs + read receipts** — control messages routed in MessagingService; never persisted; status can only advance (sending<sent<delivered<read).
- ✅ **Offline message queue**: persist unsent messages in Hive, flush when discovery sees the peer again.
- ✅ **Message pagination** in storage and chat screen.
- ✅ **Interface selection fix**: discovery now sends a packet per non-loopback IPv4 interface to that subnet's directed broadcast (advertising the sender's IP on that subnet), plus a limited-broadcast fallback. Assumes /24 for the directed broadcast (Dart exposes no netmask); the fallback covers other prefixes.
- ✅ **Unit tests** for DiscoveryService, ConnectionManager, MessagingService, CryptoService + one two-instance integration test.
- ✅ **iOS local-network permission**: `NSLocalNetworkUsageDescription` + `NSBonjourServices` present; added `Runner.entitlements` with `com.apple.developer.networking.multicast` (required for UDP broadcast on iOS 14+) and wired `CODE_SIGN_ENTITLEMENTS` into all three Runner build configs. **Manual step remaining**: the multicast entitlement is Apple-managed — request it at developer.apple.com, add it to the provisioning profile, and validate on a real device.

### Phase 2 — Rich messaging (~1 month)
**Ordered easiest → hardest, each exercising the protocol's type system:**

- Typing indicators (pure control packet, no storage)
- Image sharing (chunked transfer over the existing TCP channel, thumbnails in Hive, files on disk)
- File sharing (generalizes the image pipeline)
- Voice messages (recording UI + the file pipeline)
- OS-level notifications via flutter_local_notifications so backgrounded devices actually alert

### Phase 3 — Advanced networking
- mDNS/Bonjour discovery alongside UDP broadcast (more reliable, crosses some network setups broadcast can't)
- Group chats — the biggest protocol change (multi-receiver fan-out, group key management); design it on top of Phase 1's crypto
- WiFi Direct (Android) for router-less links, then mesh relay/store-and-forward for emergency scenarios

### Phase 4 — Distribution & community
- App icons, splash, store listings; Play Store / Microsoft Store releases
- Broadcast messaging and device groups for the community-communication use case

## Key Services

### DiscoveryService
Manages UDP broadcast discovery on port 54321:
- `startDiscovery()`: Start peer discovery
- `stopDiscovery()`: Stop peer discovery
- `broadcastPresence()`: Broadcast device presence
- `getActivePeers()`: Get currently active peers

### ConnectionManager
Manages TCP socket connections on port 54322:
- `startServer()`: Start TCP server
- `connectToPeer()`: Connect to a peer
- `sendPacket()`: Send data packet
- `disconnectPeer()`: Disconnect from peer

### MessagingService
Handles message sending/receiving:
- `sendMessage()`: Send a message
- `getMessages()`: Get conversation messages
- `markAsRead()`: Mark conversation as read

### CryptoService
Provides end-to-end encryption (X25519 + AES-256-GCM):
- `ensureIdentityKeys()`: Load or generate the device's X25519 keypair
- `publicKeyBase64`: Our public key (broadcast in discovery)
- `pinPeerPublicKey()`: Pin a peer's key (TOFU); returns false on key change
- `encryptFor()` / `decryptFrom()`: Seal/open a message for a peer deviceId
- `canEncryptFor()`: Whether a peer's key is known/pinned

## Protocol Design

### Discovery Packet Format
```json
{
  "deviceId": "uuid",
  "deviceName": "user-name",
  "ipAddress": "local-ip",
  "platform": "android",
  "appVersion": "1.0.0",
  "avatarColor": "#4ECDC4",
  "timestamp": "iso-date",
  "publicKey": "base64-x25519-public-key"
}
```

### Message Packet Format
```json
{
  "id": "uuid",
  "type": "text|image|voice|file|typing|delivery_ack|read_receipt",
  "senderId": "uuid",
  "receiverId": "uuid",
  "timestamp": "iso-date",
  "payload": {
    "encrypted": "base64(nonce | AES-GCM ciphertext | tag)"
  }
}
```
The `payload.encrypted` blob decrypts to the full inner Message JSON (the real
type/text live there). Control messages (ACKs, read receipts, typing) are
encrypted the same way but never persisted.

## Important Notes
- Web platform is not supported due to lack of raw UDP/TCP socket access
- Messages use X25519 ECDH → HKDF → AES-256-GCM (see `CryptoService`). Keys are static per device, so there is no per-message forward secrecy yet. Peer keys are pinned trust-on-first-use, so an active MITM at first contact is still possible until out-of-band verification is added.
- Android permissions are configured, iOS local-network permission needs verification
- All services follow singleton pattern with `instance` getter
