# Kylan Connect - AI Assistant Context

## Project Overview
Kylan Connect is a production-ready offline peer-to-peer messaging platform that enables direct communication between devices on the same local network without requiring internet access or centralized servers.

## Tech Stack
- **Framework**: Flutter 3.19.0+
- **Language**: Dart 3.0.0+
- **State Management**: Riverpod
- **Local Storage**: Hive
- **Encryption**: encrypt package (AES-256)
- **Testing**: flutter_test, mockito

## Architecture
- **Pattern**: Clean Architecture with Feature-First approach
- **Networking**: UDP broadcast for discovery, TCP for messaging
- **Encryption**: AES-256 CBC with random IV
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

- **Real E2E encryption**: per-device X25519 keypair, ECDH key agreement during handshake, AES-GCM for messages. Peer identity becomes the public-key fingerprint (fixes spoofing too). The cryptography package covers all of it.
- **Delivery ACKs + read receipts** — the MessagePacket.type field already reserves room for control messages.
- **Offline message queue**: persist unsent messages in Hive, flush when discovery sees the peer again.
- **Message pagination** in storage and chat screen.
- **Interface selection fix**: broadcast on all non-loopback interfaces, or prefer the one with a private-range gateway.
- **Unit tests** for DiscoveryService, ConnectionManager, MessagingService (mocked sockets) + one two-instance integration test.
- **Verify iOS local-network permission** (NSLocalNetworkUsageDescription) — Android permissions are done, iOS likely isn't.

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

### EncryptionService
Provides encryption/decryption:
- `encrypt()`: Encrypt data
- `decrypt()`: Decrypt data
- `encryptJson()`: Encrypt JSON object
- `decryptJson()`: Decrypt JSON object

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
  "timestamp": "iso-date"
}
```

### Message Packet Format
```json
{
  "id": "uuid",
  "type": "text|image|voice|file|typing",
  "senderId": "uuid",
  "receiverId": "uuid",
  "timestamp": "iso-date",
  "payload": {
    // Type-specific data
  }
}
```

## Important Notes
- Web platform is not supported due to lack of raw UDP/TCP socket access
- The app currently uses AES-256 CBC encryption, but Phase 1 will upgrade to X25519 + AES-GCM for proper E2E encryption
- Android permissions are configured, iOS local-network permission needs verification
- All services follow singleton pattern with `instance` getter
