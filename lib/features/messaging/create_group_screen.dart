import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/extensions.dart';
import '../../models/peer_device.dart';
import '../../providers/peer_provider.dart';
import '../../providers/profile_provider.dart';
import '../../repositories/group_repository.dart';

class CreateGroupScreen extends ConsumerStatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  ConsumerState<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends ConsumerState<CreateGroupScreen> {
  final _nameController = TextEditingController();
  final Set<String> _selectedMemberIds = {};
  bool _isCreating = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _createGroup() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showSnack('Enter a group name');
      return;
    }
    if (_selectedMemberIds.length < 2) {
      _showSnack('Pick at least 2 members');
      return;
    }

    final profile = ref.read(profileProvider);
    if (profile == null) {
      _showSnack('Create a profile before starting a group');
      return;
    }

    setState(() => _isCreating = true);
    try {
      final group = await GroupRepository.instance.createGroup(
        name: name,
        memberIds: _selectedMemberIds.toList(),
        avatarColor: AppConstants
            .avatarColors[name.hashCode.abs() % AppConstants.avatarColors.length],
      );
      if (!mounted) return;
      Navigator.pushReplacementNamed(
        context,
        '/group-chat',
        arguments: {'groupId': group.groupId},
      );
    } catch (e) {
      _showSnack('Failed to create group: $e');
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final peers = ref.watch(activePeersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('New Group'),
        actions: [
          TextButton(
            onPressed: _isCreating ? null : _createGroup,
            child: _isCreating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Create'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _nameController,
              maxLength: AppConstants.maxDisplayNameLength,
              decoration: const InputDecoration(
                labelText: 'Group name',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Members (${_selectedMemberIds.length} selected — need at least 2)',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: peers.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No devices found nearby. Make sure others are on '
                        'the same network and Kylan Connect is open.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: peers.length,
                    itemBuilder: (context, index) =>
                        _buildPeerTile(peers[index]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPeerTile(PeerDevice peer) {
    final selected = _selectedMemberIds.contains(peer.deviceId);
    return CheckboxListTile(
      value: selected,
      onChanged: (checked) {
        setState(() {
          if (checked ?? false) {
            _selectedMemberIds.add(peer.deviceId);
          } else {
            _selectedMemberIds.remove(peer.deviceId);
          }
        });
      },
      secondary: CircleAvatar(
        backgroundColor:
            Color(int.parse(peer.avatarColor.replaceFirst('#', '0xFF'))),
        child: Text(
          peer.displayName.initials,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      title: Text(peer.displayName),
      subtitle: Text(peer.isOnline ? 'Online' : 'Offline'),
    );
  }
}
