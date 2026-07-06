import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/validators.dart';
import '../../core/utils/extensions.dart';
import '../../models/message.dart';
import '../../providers/profile_provider.dart';
import '../../repositories/chat_repository.dart';
import '../../repositories/peer_repository.dart';
import '../../services/app_startup_service.dart';
import '../../services/discovery_service.dart';
import '../../services/messaging_service.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  List<Message> _messages = [];

  String _conversationId = '';
  late String _participantId;
  late String _participantName;
  late String _participantAvatarColor;
  String _participantIp = '';
  bool _isLoading = false;
  bool _didLoadArguments = false;
  StreamSubscription<Message>? _messageSubscription;
  StreamSubscription<Message>? _statusSubscription;

  @override
  void initState() {
    super.initState();
    _messageSubscription = MessagingService.instance.onMessageReceived.listen(
      (_) => _loadMessages(),
    );
    _statusSubscription = MessagingService.instance.onMessageStatusChanged
        .listen((_) => _loadMessages());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didLoadArguments) {
      _loadArguments();
      _didLoadArguments = true;
      _loadMessages();
      // Mark conversation as read when the screen opens.
      if (_conversationId.isNotEmpty) {
        ChatRepository.instance.markAsRead(_conversationId);
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

  void _loadArguments() {
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is! Map<String, dynamic>) {
      _participantId = '';
      _participantName = 'Unknown';
      _participantAvatarColor = AppConstants.avatarColors.first;
      return;
    }

    _conversationId = args['conversationId'] as String? ?? '';
    _participantId = args['participantId'] as String;
    _participantName = args['participantName'] as String;
    _participantAvatarColor = args['participantAvatarColor'] as String;
    _participantIp = args['participantIp'] as String? ?? '';
  }

  Future<void> _loadMessages() async {
    if (_conversationId.isEmpty) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final messages = await ChatRepository.instance.getMessages(
        _conversationId,
      );
      if (!mounted) return;
      setState(() {
        _messages = messages;
        _isLoading = false;
      });

      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final validationError = Validators.validateMessage(text);
    if (validationError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(validationError)),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final profile = ref.read(profileProvider);
      if (profile == null) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Create a profile before messaging')),
        );
        return;
      }

      final receiverIp = _resolveParticipantIp();
      if (receiverIp.isEmpty) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This device is not currently reachable')),
        );
        return;
      }

      if (!MessagingService.instance.isInitialized) {
        await AppStartupService.instance.startPeerServices(profile);
      }

      await ChatRepository.instance.sendMessage(
        receiverId: _participantId,
        receiverIp: receiverIp,
        text: text,
      );

      setState(() {
        _participantIp = receiverIp;
        _messageController.clear();
      });

      await _loadMessages();
    } catch (e) {
      await _loadMessages();
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send message: $e')),
        );
      }
    }
  }

  String _resolveParticipantIp() {
    if (_participantIp.isNotEmpty) return _participantIp;
    final peer = PeerRepository.instance.getPeer(_participantId);
    return peer?.ipAddress ?? '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: Color(
                int.parse(_participantAvatarColor.replaceFirst('#', '0xFF')),
              ),
              child: Text(
                _participantName.initials,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _participantName,
                    style: const TextStyle(fontSize: 16),
                  ),
                  Builder(builder: (context) {
                    final peer = DiscoveryService.instance.getPeer(_participantId);
                    final isOnline = peer?.isOnline ?? false;
                    return Text(
                      isOnline ? 'Online' : 'Offline',
                      style: TextStyle(
                        fontSize: 12,
                        color: isOnline
                            ? Colors.green
                            : Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.5),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () {
              _showOptionsMenu();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading && _messages.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? _buildEmptyState()
                    : _buildMessagesList(),
          ),
          _buildMessageComposer(),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 40,
            backgroundColor: Color(
              int.parse(_participantAvatarColor.replaceFirst('#', '0xFF')),
            ),
            child: Text(
              _participantName.initials,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 24,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Start a conversation with $_participantName',
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Messages are encrypted and sent directly',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.6),
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessagesList() {
    final profile = ref.watch(profileProvider);

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        final isMe = message.senderId == profile?.deviceId;

        return _buildMessageBubble(message, isMe);
      },
    );
  }

  Widget _buildMessageBubble(Message message, bool isMe) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
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
                color: isMe
                    ? Colors.white
                    : Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                message.timestamp.toChatTime(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.5),
                    ),
              ),
              if (isMe) ...[
                const SizedBox(width: 4),
                Icon(
                  _getStatusIcon(message.status),
                  size: 12,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.5),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case AppConstants.messageStatusSent:
        return Icons.check;
      case AppConstants.messageStatusDelivered:
        return Icons.done_all;
      case AppConstants.messageStatusFailed:
        return Icons.error_outline;
      default:
        return Icons.schedule;
    }
  }

  Widget _buildMessageComposer() {
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
            IconButton(
              icon: const Icon(Icons.attach_file),
              onPressed: () {
                // Future: File attachment
              },
            ),
            Expanded(
              child: TextField(
                controller: _messageController,
                decoration: InputDecoration(
                  hintText: 'Type a message...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor:
                      Theme.of(context).colorScheme.surfaceContainerHighest,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
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

  void _showOptionsMenu() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Contact Info'),
              onTap: () {
                Navigator.pop(context);
                // Show contact info
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Clear Chat'),
              onTap: () {
                Navigator.pop(context);
                _showClearChatDialog();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showClearChatDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Chat'),
        content:
            const Text('Are you sure you want to clear this conversation?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await ChatRepository.instance.deleteConversation(_conversationId);
              if (mounted) {
                setState(() {
                  _messages.clear();
                });
              }
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}
