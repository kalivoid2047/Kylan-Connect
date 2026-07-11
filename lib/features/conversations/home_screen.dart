import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/conversation.dart';
import '../../models/peer_device.dart';
import '../../models/user_profile.dart';
import '../../providers/peer_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/connection_provider.dart';
import '../../providers/profile_provider.dart';
import '../../repositories/group_repository.dart';
import '../../core/widgets/empty_state_widget.dart';
import '../../core/utils/extensions.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);
    final connectionStatus = ref.watch(connectionStatusProvider);

    return Scaffold(
      appBar: AppBar(
        title: Image.asset(
          Theme.of(context).brightness == Brightness.dark
              ? 'assets/images/logo_dark.png'
              : 'assets/images/logo_light.png',
          height: 32,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.group_add_outlined),
            tooltip: 'New group',
            onPressed: () {
              Navigator.pushNamed(context, '/create-group');
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.pushNamed(context, '/settings');
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Chats'),
            Tab(text: 'Devices'),
          ],
        ),
      ),
      body: Column(
        children: [
          _buildConnectionStatus(connectionStatus),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildChatsTab(profile),
                _buildDevicesTab(),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          _tabController.index = 1;
        },
        child: const Icon(Icons.person_add),
      ),
    );
  }

  Widget _buildConnectionStatus(ConnectionStatus status) {
    Color statusColor;
    String statusText;

    switch (status) {
      case ConnectionStatus.connected:
        statusColor = Colors.green;
        statusText = 'Connected';
        break;
      case ConnectionStatus.searching:
        statusColor = Colors.orange;
        statusText = 'Searching...';
        break;
      case ConnectionStatus.disconnected:
        statusColor = Colors.red;
        statusText = 'Disconnected';
        break;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      color: statusColor.withValues(alpha: 0.1),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            status == ConnectionStatus.connected
                ? Icons.wifi
                : status == ConnectionStatus.searching
                    ? Icons.search
                    : Icons.wifi_off,
            color: statusColor,
            size: 16,
          ),
          const SizedBox(width: 8),
          Text(
            statusText,
            style: TextStyle(
              color: statusColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatsTab(UserProfile? profile) {
    final conversationsAsync = ref.watch(conversationsProvider);

    return conversationsAsync.isEmpty
        ? const EmptyStateWidget(
            icon: Icons.chat_bubble_outline,
            title: 'No conversations yet',
            subtitle: 'Start chatting with devices on your network',
          )
        : RefreshIndicator(
            onRefresh: () async {
              await ref.read(conversationsProvider.notifier).refresh();
            },
            child: ListView.builder(
              itemCount: conversationsAsync.length,
              itemBuilder: (context, index) {
                final conversation = conversationsAsync[index];
                return _buildConversationTile(conversation, profile);
              },
            ),
          );
  }

  Widget _buildConversationTile(
      Conversation conversation, UserProfile? profile) {
    final isGroup = GroupRepository.instance.isGroup(conversation.conversationId);

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Color(
          int.parse(
              conversation.participantAvatarColor.replaceFirst('#', '0xFF')),
        ),
        child: isGroup
            ? const Icon(Icons.groups, color: Colors.white, size: 20)
            : Text(
                conversation.participantName.initials,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
      title: Text(conversation.participantName),
      subtitle: Text(
        conversation.lastMessage ?? 'No messages',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (conversation.lastMessageTime != null)
            Text(
              conversation.lastMessageTime!.toChatTime(),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          if (conversation.unreadCount > 0) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                conversation.unreadCount.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
      onTap: () {
        if (isGroup) {
          Navigator.pushNamed(
            context,
            '/group-chat',
            arguments: {'groupId': conversation.conversationId},
          );
          return;
        }
        Navigator.pushNamed(
          context,
          '/chat',
          arguments: {
            'conversationId': conversation.conversationId,
            'participantId': conversation.participantId,
            'participantName': conversation.participantName,
            'participantAvatarColor': conversation.participantAvatarColor,
            'participantIp': '', // Will be fetched from peer
          },
        );
      },
    );
  }

  Widget _buildDevicesTab() {
    final peers = ref.watch(activePeersProvider);

    return peers.isEmpty
        ? const EmptyStateWidget(
            icon: Icons.devices_other,
            title: 'No devices found',
            subtitle: 'Make sure devices are on the same network',
          )
        : RefreshIndicator(
            onRefresh: () async {
              ref.read(activePeersProvider.notifier).refresh();
            },
            child: ListView.builder(
              itemCount: peers.length,
              itemBuilder: (context, index) {
                final peer = peers[index];
                return _buildPeerTile(peer);
              },
            ),
          );
  }

  Widget _buildPeerTile(PeerDevice peer) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Color(
          int.parse(peer.avatarColor.replaceFirst('#', '0xFF')),
        ),
        child: Text(
          peer.displayName.initials,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      title: Text(peer.displayName),
      subtitle: Text(peer.ipAddress),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            peer.isOnline ? Icons.circle : Icons.circle_outlined,
            color: peer.isOnline ? Colors.green : Colors.grey,
            size: 12,
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.chat),
            onPressed: () {
              final profile = ref.read(profileProvider);
              if (profile == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Create a profile before messaging'),
                  ),
                );
                return;
              }

              Navigator.pushNamed(
                context,
                '/chat',
                arguments: {
                  'conversationId': Conversation.generateConversationId(
                    profile.deviceId,
                    peer.deviceId,
                  ),
                  'participantId': peer.deviceId,
                  'participantName': peer.displayName,
                  'participantAvatarColor': peer.avatarColor,
                  'participantIp': peer.ipAddress,
                },
              );
            },
          ),
        ],
      ),
    );
  }
}
