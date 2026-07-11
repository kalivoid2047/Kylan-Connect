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

- ✅ Typing indicators (pure control packet, no storage). Encrypted `typing` control message; `MessagingService.sendTypingIndicator` sends, `TypingService` tracks who's typing (receive-only, 4s auto-expiry), chat screen throttles sends (2s) and shows "typing…" in the app-bar subtitle.
- ✅ Image sharing. `MessagingService.sendImage` persists a bubble carrying only a base64 thumbnail + metadata (in Hive), then streams the full image as encrypted `file_chunk` control messages (32KB chunks) over the existing TCP channel; the receiver reassembles and writes the file to disk (`ImageService`, deterministic `transferId_fileName` path under app docs/images). Chat renders the thumbnail with a full-screen pinch-zoom viewer on tap. Uses image_picker (gallery) + the image package (thumbnails).
- ✅ File sharing. Generalizes the image pipeline: a shared, unified transfer core streams `file_chunk` control messages for both images and files. `MessagingService.sendFile` persists a `file` bubble (name + size metadata) and streams the bytes; the receiver reassembles via `FileService` (app docs/files, same deterministic path scheme). Chat shows a file-card bubble that opens with the OS default app on tap (open_filex); file picked via file_picker. The generic chunk/reassemble helpers live in `FileService`; `ImageService` keeps thumbnail/dimension logic.
- ✅ Voice messages. Built on the file transfer core: `MessagingService.sendVoice` records to an m4a (record package), streams it as a `voice` attachment (via the same `file_chunk` path + `FileService` storage), and carries `durationMs` in the payload. Chat composer shows a mic button (when the text field is empty) that opens a recording bar (elapsed timer, cancel/send); received voice messages render a play/pause bubble with a progress bar (audioplayers). Permissions: Android `RECORD_AUDIO`, iOS `NSMicrophoneUsageDescription`.
- ✅ OS-level notifications. `NotificationService.initialize()` (called at startup) sets up flutter_local_notifications (Android `messages` channel, Darwin permission request) and degrades gracefully on unsupported platforms. Incoming messages raise a system notification with an attachment-aware preview, suppressed for the chat currently on screen (`setActiveConversation`). **Not yet wired**: tapping a notification to deep-link into the conversation; the iOS `UNUserNotificationCenter` delegate may need manual AppDelegate setup for foreground display (unverified — no Xcode here).

### Phase 3 — Advanced networking (IN PROGRESS)
- ✅ mDNS/Bonjour discovery alongside UDP broadcast. `DiscoveryService` registers a `_kylanconnect._tcp` service (on the messaging port) with TXT records (deviceId, name, color, platform, version, publicKey) via the `nsd` package, browses + IPv4-resolves peers, and routes them through the same `_handlePeerDiscovered` pipeline (TOFU key-pinning included). mDNS peers are kept alive by "service lost" events, so they're exempt from the UDP heartbeat timeout (`_mdnsPresentPeers`). TXT encode/decode is the pure, unit-tested `MdnsCodec`. Best-effort — degrades to UDP-only where mDNS is unavailable. iOS `NSBonjourServices` already declared the type.
- ✅ Group chats (text-only v1). No new crypto: a group message is encrypted once per member with the existing pairwise X25519 key (`encryptFor(member)`) and fanned out over individual TCP connections — no group key to distribute or rotate. `Group` (plain JSON, `groups_box`) holds id/name/memberIds/creator/avatarColor; a group's `Conversation.conversationId` is its `groupId`, so it reuses the existing conversation list/storage. `MessagingService.createGroup` saves the group and fans out an encrypted `group_invite` control message to each member; `sendGroupMessage` fans out an encrypted copy to each reachable member and stores the message once locally, keyed by `groupId`. Incoming group text is filed under the group conversation and shows the sender name per bubble. UI: `CreateGroupScreen` (name + multi-select active peers) and `GroupChatScreen`, reachable via a "New group" app-bar action and group tiles in the conversation list (`GroupRepository.isGroup`). **Known v1 gaps**: images/files/voice are 1:1-only (group fan-out for chunked transfers isn't implemented); no typing indicators or per-message delivery/read receipts in groups (a group message has many recipients, so there's no single tick to show); a member who missed the invite silently drops later group messages; no leave/add-member/remove-member flow after creation.
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
  "type": "text|image|voice|file|typing|delivery_ack|read_receipt|file_chunk",
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
