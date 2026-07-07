# Kylan Connect

A production-ready offline peer-to-peer messaging platform that enables direct communication between devices on the same local network without requiring internet access or centralized servers.

## Features

- **Device Discovery**: Automatic peer discovery using UDP broadcasting
- **Direct Messaging**: Real-time P2P communication via TCP sockets
- **End-to-End Encryption**: X25519 key agreement + AES-256-GCM authenticated encryption
- **Offline-First**: No internet dependency, works entirely on local networks
- **Modern UI**: Material 3 design with light/dark theme support
- **Local Storage**: Persistent chat history using Hive
- **Network Diagnostics**: Built-in tools for troubleshooting network issues

## Architecture

Kylan Connect follows **Clean Architecture** with a **Feature-First** approach, ensuring scalability and maintainability for future expansion.

### Folder Structure

```
lib/
├── core/
│   ├── constants/          # App-wide constants
│   ├── errors/             # Custom exceptions and failures
│   ├── themes/             # App theming (Material 3)
│   ├── utils/              # Utility functions (validators, extensions, logger)
│   ├── network/            # Network utilities
│   ├── security/           # Encryption service
│   └── widgets/           # Reusable core widgets
├── features/
│   ├── onboarding/         # Welcome and profile setup screens
│   ├── discovery/          # Device discovery feature
│   ├── messaging/          # Chat screen
│   ├── conversations/      # Home screen with chats and devices
│   ├── profile/            # Profile management
│   └── settings/           # Settings and diagnostics
├── services/               # Business logic services
├── repositories/          # Data access layer
├── models/                 # Data models with JSON serialization
├── providers/              # Riverpod state management
├── routes/                 # App routing configuration
└── main.dart              # App entry point
```

## Installation

### Prerequisites

- Flutter SDK (3.0.0 or higher)
- Dart SDK (3.0.0 or higher)
- Android Studio / VS Code with Flutter extension

### Setup

1. Clone the repository:
```bash
git clone <repository-url>
cd kylan_connect
```

2. Install dependencies:
```bash
flutter pub get
```

3. Generate code (for JSON serialization):
```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

4. Run the app:
```bash
flutter run
```

## Networking Design

### Device Discovery

Kylan Connect uses **UDP broadcasting** for automatic peer discovery:

- **Protocol**: UDP
- **Port**: 54321
- **Broadcast Interval**: Every 5 seconds
- **Peer Timeout**: 15 seconds of inactivity

#### Discovery Packet Format

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

### Direct Messaging

Messages are sent via **TCP sockets** for reliable delivery:

- **Protocol**: TCP
- **Port**: 54322
- **Encryption**: X25519 + AES-256-GCM (see Encryption Design below)
- **Connection Management**: Automatic reconnection handling

#### Message Protocol

The message protocol is designed to be **future-proof**, supporting multiple content types:

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

#### Supported Message Types (Future)

- **text**: Plain text messages (Phase 1)
- **image**: Image sharing (Phase 2)
- **voice**: Voice messages (Phase 2)
- **file**: File sharing (Phase 2)
- **typing**: Typing indicators (Phase 2)

## Encryption Design

Messages are end-to-end encrypted using **X25519 ECDH + AES-256-GCM**:

- **Identity**: each device holds a long-lived X25519 keypair (private key persisted in Hive)
- **Key agreement**: non-interactive ECDH — each peer broadcasts its public key in discovery, and both derive the same shared secret from their own private key plus the other's public key
- **Key derivation**: HKDF-SHA256 over the shared secret (salted with a sorted hash of both public keys)
- **Cipher**: AES-256-GCM (authenticated encryption — detects tampering)
- **Trust**: peer public keys are pinned on first sighting (TOFU); a later key change is flagged as a possible spoof/MITM
- **Implementation**: `cryptography` package (`CryptoService`)

### Encryption Flow

1. Message is created with payload and serialized to JSON
2. The session key is derived from the peer's pinned public key (ECDH + HKDF)
3. JSON is sealed with AES-256-GCM (random nonce per message)
4. `base64(nonce | ciphertext | tag)` is wrapped in the message packet
5. Packet is sent via TCP; the receiver derives the same key and decrypts

> **Limitation**: keys are static per device, so there is no per-message forward
> secrecy yet, and TOFU cannot stop an active MITM at first contact. A future
> ephemeral-key handshake and out-of-band safety-number verification would close
> these gaps.

## State Management

Kylan Connect uses **Riverpod** for state management:

### Providers

- **profileProvider**: User profile state
- **activePeersProvider**: Currently discovered peers
- **conversationsProvider**: User's conversations
- **settingsProvider**: App settings (theme, notifications)
- **connectionProvider**: Network connection status
- **notificationProvider**: In-app notifications

## Storage

Local data persistence using **Hive**:

- **UserProfile**: User profile information
- **Conversation**: Chat conversations
- **Message**: Chat messages
- **PeerDevice**: Cached peer information
- **AppSettings**: User preferences

## Future Expansion Strategy

The architecture is designed to support future features without major rewrites:

### Phase 2: Rich Media
- Image sharing
- Voice messages
- File sharing
- Typing indicators

### Phase 3: Advanced Features
- WiFi Direct communication
- Group chats
- Mesh networking
- Emergency communication networks

### Phase 4: Community Features
- Community communication systems
- Broadcast messaging
- Device groups

## Services

### DiscoveryService
Manages UDP broadcast discovery:
- `startDiscovery()`: Start peer discovery
- `stopDiscovery()`: Stop peer discovery
- `broadcastPresence()`: Broadcast device presence
- `getActivePeers()`: Get currently active peers

### ConnectionManager
Manages TCP socket connections:
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
- `pinPeerPublicKey()`: Pin a peer's public key (trust-on-first-use)
- `encryptFor()` / `decryptFrom()`: Seal/open a message for a peer
- `canEncryptFor()`: Whether a peer's key is known

### StorageService
Manages local data persistence:
- `saveUserProfile()`: Save user profile
- `saveMessage()`: Save message
- `getConversations()`: Get all conversations
- `clearAllData()`: Clear all stored data

### NotificationService
Manages in-app notifications:
- `showNewMessageNotification()`: Show message notification
- `showDeviceJoinedNotification()`: Show device joined notification
- `clearNotifications()`: Clear all notifications

### DiagnosticsService
Provides network diagnostics:
- `getDiagnosticsInfo()`: Get diagnostic information
- `testConnection()`: Test connection to peer
- `restartDiscovery()`: Restart discovery service

## Repositories

### ProfileRepository
User profile data access:
- `getProfile()`: Get user profile
- `createProfile()`: Create new profile
- `updateProfile()`: Update profile

### PeerRepository
Peer device data access:
- `getActivePeers()`: Get active peers
- `cachePeer()`: Cache peer information
- `removePeer()`: Remove peer

### ChatRepository
Chat data access:
- `getConversations()`: Get conversations
- `sendMessage()`: Send message
- `deleteConversation()`: Delete conversation

### SettingsRepository
Settings data access:
- `getSettings()`: Get app settings
- `updateThemeMode()`: Update theme
- `updateNotificationsEnabled()`: Update notification settings

## Testing

### Unit Tests
Test services and repositories:
```bash
flutter test test/unit/
```

### Widget Tests
Test UI components:
```bash
flutter test test/widget/
```

### Integration Tests
Test end-to-end flows:
```bash
flutter test test/integration/
```

## Development

### Code Generation

Run code generation for JSON serialization:
```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

### Linting

Run Flutter linter:
```bash
flutter analyze
```

### Formatting

Format code:
```bash
dart format .
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Flutter team for the amazing framework
- Riverpod for state management
- Hive for local storage
- cryptography package for encryption

## Contact

[Contact information to be added]
