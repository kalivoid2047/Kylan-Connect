import 'package:flutter/material.dart';
import '../../services/diagnostics_service.dart';
import '../../core/utils/app_logger.dart';

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  final DiagnosticsService _diagnosticsService = DiagnosticsService.instance;
  Map<String, dynamic>? _diagnosticsData;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadDiagnostics();
  }

  Future<void> _loadDiagnostics() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final info = await _diagnosticsService.getDiagnosticsInfo();
      setState(() {
        _diagnosticsData = info.toJson();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Network Diagnostics'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDiagnostics,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _diagnosticsData == null
              ? const Center(child: Text('Failed to load diagnostics'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildSection('Network Information', [
                      _buildInfoRow(
                          'Local IP', _diagnosticsData!['localIpAddress']),
                      _buildInfoRow('Device ID', _diagnosticsData!['deviceId']),
                      _buildInfoRow('Platform', _diagnosticsData!['platform']),
                      _buildInfoRow(
                          'App Version', _diagnosticsData!['appVersion']),
                    ]),
                    const SizedBox(height: 16),
                    _buildSection('Service Status', [
                      _buildStatusRow(
                        'TCP Server',
                        _diagnosticsData!['tcpServerRunning'],
                      ),
                      _buildStatusRow(
                        'Discovery Service',
                        _diagnosticsData!['discoveryServiceRunning'],
                      ),
                    ]),
                    const SizedBox(height: 16),
                    _buildSection('Connection Info', [
                      _buildInfoRow('Active Connections',
                          _diagnosticsData!['activeConnections'].toString()),
                      _buildInfoRow('Known Peers',
                          _diagnosticsData!['knownPeers'].toString()),
                    ]),
                    const SizedBox(height: 16),
                    _buildSection('Storage Info', [
                      _buildInfoRow('Total Conversations',
                          _diagnosticsData!['totalConversations'].toString()),
                      _buildInfoRow('Total Messages',
                          _diagnosticsData!['totalMessages'].toString()),
                    ]),
                    const SizedBox(height: 24),
                    _buildActionButtons(),
                  ],
                ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.7),
                ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusRow(String label, bool isActive) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.7),
                ),
          ),
          Row(
            children: [
              Icon(
                isActive ? Icons.check_circle : Icons.cancel,
                color: isActive ? Colors.green : Colors.red,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                isActive ? 'Running' : 'Stopped',
                style: TextStyle(
                  color: isActive ? Colors.green : Colors.red,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton.icon(
          onPressed: _restartDiscovery,
          icon: const Icon(Icons.wifi_find),
          label: const Text('Restart Discovery'),
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: _restartConnectionManager,
          icon: const Icon(Icons.refresh),
          label: const Text('Restart Connection Manager'),
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: _refreshPeers,
          icon: const Icon(Icons.people),
          label: const Text('Refresh Peers'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _exportDiagnostics,
          icon: const Icon(Icons.download),
          label: const Text('Export Diagnostics'),
        ),
      ],
    );
  }

  Future<void> _restartDiscovery() async {
    try {
      await _diagnosticsService.restartDiscovery();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Discovery service restarted')),
        );
      }
      _loadDiagnostics();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to restart discovery: $e')),
        );
      }
    }
  }

  Future<void> _restartConnectionManager() async {
    try {
      await _diagnosticsService.restartConnectionManager();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Connection manager restarted')),
        );
      }
      _loadDiagnostics();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to restart connection manager: $e')),
        );
      }
    }
  }

  Future<void> _refreshPeers() async {
    try {
      await _diagnosticsService.refreshPeers();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Peers refreshed')),
        );
      }
      _loadDiagnostics();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to refresh peers: $e')),
        );
      }
    }
  }

  Future<void> _exportDiagnostics() async {
    try {
      final data = await _diagnosticsService.exportDiagnostics();
      // In production, you'd save this to a file or share it
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Diagnostics exported (console log)')),
        );
      }
      AppLogger.instance.info('Diagnostics Data: $data');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to export diagnostics: $e')),
        );
      }
    }
  }
}
