import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/utils/extensions.dart';
import '../../core/utils/validators.dart';
import '../../models/group.dart';
import '../../models/message.dart';
import '../../providers/profile_provider.dart';
import '../../repositories/chat_repository.dart';
import '../../repositories/group_repository.dart';
import '../../repositories/peer_repository.dart';
import '../../services/messaging_service.dart';

/// A group chat view. Text-only for now: group fan-out for images/files/voice
/// and per-member typing indicators are not yet implemented (see
/// MessagingService.sendGroupMessage / createGroup).
class GroupChatScreen extends ConsumerStatefulWidget {
  const GroupChatScreen({super.key});

  @override
  ConsumerState<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends ConsumerState<GroupChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();

  String _groupId = '';
  Group? _group;
  List<Message> _messages = [];
  bool _isLoading = false;
  bool _didLoadArguments = false;
  StreamSubscription<Message>? _messageSubscription;
  StreamSubscription<Message>? _statusSubscription;

  @override
  void initState() {
    super.initState();
    _messageSubscription = MessagingService.instance.onMessageReceived.listen(
      (message) {
        if (message.groupId == _groupId) _loadMessages();
      },
    );
    _statusSubscription = MessagingService.instance.onMessageStatusChanged
        .listen((_) => _loadMessages());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didLoadArguments) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map<String, dynamic>) {
        _groupId = args['groupId'] as String? ?? '';
      }
      _didLoadArguments = true;
      _group = GroupRepository.instance.getGroup(_groupId);
      _loadMessages();
      if (_groupId.isNotEmpty) {
        ChatRepository.instance.markAsRead(_groupId);
      }
    }
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    _statusSubscription?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    if (_groupId.isEmpty) return;
    try {
      final messages = ChatRepository.instance.getMessagesPaginated(_groupId);
      if (!mounted) return;
      setState(() => _messages = messages);
      _scrollToBottom();
    } catch (_) {
      // Best-effort — keep whatever was already shown.
    }
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _groupId.isEmpty) return;

    final error = Validators.validateMessage(text);
    if (error != null) {
      _showSnack(error);
      return;
    }

    setState(() => _isLoading = true);
    try {
      await GroupRepository.instance.sendGroupMessage(
        groupId: _groupId,
        text: text,
      );
      _messageController.clear();
      await _loadMessages();
    } catch (e) {
      _showSnack('Failed to send message: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  String _senderName(String senderId) {
    final active = PeerRepository.instance.getPeer(senderId);
    if (active != null) return active.displayName;

    for (final peer in PeerRepository.instance.getCachedPeers()) {
      if (peer.deviceId == senderId) return peer.displayName;
    }
    return 'Member';
  }

  @override
  Widget build(BuildContext context) {
    final group = _group;
    final profile = ref.watch(profileProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: Color(int.parse(
                  (group?.avatarColor ?? '#4ECDC4').replaceFirst('#', '0xFF'))),
              child: const Icon(Icons.groups, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(group?.name ?? 'Group', style: const TextStyle(fontSize: 16)),
                  Text(
                    '${group?.memberIds.length ?? 0} members',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Text(
                      'Say hello to the group',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      final isMe = message.senderId == profile?.deviceId;
                      return _buildBubble(message, isMe);
                    },
                  ),
          ),
          _buildComposer(),
        ],
      ),
    );
  }

  Widget _buildBubble(Message message, bool isMe) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (!isMe)
            Padding(
              padding: const EdgeInsets.only(left: 12, bottom: 2),
              child: Text(
                _senderName(message.senderId),
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.7,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isMe
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              message.textContent ?? '',
              style: TextStyle(
                color: isMe ? Colors.white : Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            message.timestamp.toChatTime(),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.5),
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildComposer() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _messageController,
                decoration: InputDecoration(
                  hintText: 'Message the group…',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                maxLines: null,
                textCapitalization: TextCapitalization.sentences,
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.send),
              onPressed: _isLoading ? null : _sendMessage,
              style: IconButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
