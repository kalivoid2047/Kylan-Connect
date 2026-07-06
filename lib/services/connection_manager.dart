import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../core/constants/app_constants.dart';
import '../core/constants/network_constants.dart';
import '../core/errors/exceptions.dart';
import '../models/message_packet.dart';
import '../core/utils/app_logger.dart';

// How often the reconnect timer fires to restore dropped connections.
const _reconnectInterval = Duration(seconds: 15);

class ConnectionManager {
  static final ConnectionManager _instance = ConnectionManager._internal();
  static ConnectionManager get instance => _instance;

  ServerSocket? _server;

  // Keyed by remote IP address only (not IP:port) so incoming and outgoing
  // connections for the same peer share the same slot.
  final Map<String, Socket> _connections = {};
  final Map<String, StringBuffer> _receiveBuffers = {};

  // IPs that we should actively keep connected; drives the reconnect timer.
  final Set<String> _intendedPeers = {};
  Timer? _reconnectTimer;

  final StreamController<MessagePacket> _messageReceivedController =
      StreamController.broadcast();
  final StreamController<String> _peerConnectedController =
      StreamController.broadcast();
  final StreamController<String> _peerDisconnectedController =
      StreamController.broadcast();

  bool _isRunning = false;

  ConnectionManager._internal();

  Stream<MessagePacket> get onMessageReceived =>
      _messageReceivedController.stream;
  Stream<String> get onPeerConnected => _peerConnectedController.stream;
  Stream<String> get onPeerDisconnected => _peerDisconnectedController.stream;
  bool get isRunning => _isRunning;
  List<String> get connectedPeers => _connections.keys.toList();

  /// Register an IP as one that should be kept connected persistently.
  /// The reconnect timer will re-establish the connection whenever it drops.
  void registerIntendedPeer(String ipAddress) {
    _intendedPeers.add(ipAddress);
    _ensureReconnectTimer();
  }

  void _ensureReconnectTimer() {
    if (_reconnectTimer != null) return;
    _reconnectTimer = Timer.periodic(_reconnectInterval, (_) => _reconnectAll());
  }

  Future<void> _reconnectAll() async {
    for (final ip in List.of(_intendedPeers)) {
      if (!isConnectedTo(ip)) {
        try {
          await connectToPeer(ip);
          AppLogger.instance.info('Reconnected to peer: $ip');
        } catch (_) {
          // Will retry on the next timer tick — not an error worth logging here.
        }
      }
    }
  }

  Future<void> startServer() async {
    if (_isRunning) {
      AppLogger.instance.warning('Connection manager already running');
      return;
    }

    try {
      _server = await ServerSocket.bind(
          InternetAddress.anyIPv4, AppConstants.messagingPort);
      _server!.listen(_handleIncomingConnection);
      _isRunning = true;
      AppLogger.instance
          .info('Connection manager started on port ${AppConstants.messagingPort}');
    } catch (e, stackTrace) {
      AppLogger.instance
          .error('Failed to start connection manager', e, stackTrace);
      throw ConnectionException('Failed to start connection manager', e);
    }
  }

  Future<void> stopServer() async {
    if (!_isRunning) return;

    try {
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      _intendedPeers.clear();

      for (final socket in _connections.values) {
        await socket.close();
      }
      _connections.clear();
      _receiveBuffers.clear();
      await _server?.close();
      _isRunning = false;
      AppLogger.instance.info('Connection manager stopped');
    } catch (e, stackTrace) {
      AppLogger.instance
          .error('Failed to stop connection manager', e, stackTrace);
      throw ConnectionException('Failed to stop connection manager', e);
    }
  }

  void _handleIncomingConnection(Socket socket) {
    try {
      final remoteIp = socket.remoteAddress.address;

      // If we already have an outgoing connection to this IP, close the duplicate.
      if (_connections.containsKey(remoteIp)) {
        AppLogger.instance
            .debug('Already connected to $remoteIp — closing duplicate incoming socket');
        socket.close();
        return;
      }

      AppLogger.instance.info('Incoming connection from: $remoteIp');

      _connections[remoteIp] = socket;
      _receiveBuffers[remoteIp] = StringBuffer();
      _peerConnectedController.add(remoteIp);

      socket.listen(
        (data) => _handleIncomingData(remoteIp, data),
        onError: (error) {
          AppLogger.instance.error('Socket error for $remoteIp', error);
          _handleDisconnection(remoteIp);
        },
        onDone: () => _handleDisconnection(remoteIp),
      );
    } catch (e, stackTrace) {
      AppLogger.instance
          .error('Failed to handle incoming connection', e, stackTrace);
    }
  }

  Future<void> connectToPeer(String ipAddress, {int? port}) async {
    final targetPort = port ?? AppConstants.messagingPort;

    if (_connections.containsKey(ipAddress)) {
      AppLogger.instance.debug('Already connected to: $ipAddress');
      return;
    }

    try {
      AppLogger.instance.info('Connecting to peer: $ipAddress:$targetPort');

      final socket = await Socket.connect(
        ipAddress,
        targetPort,
        timeout: NetworkConstants.connectionTimeout,
      );

      _connections[ipAddress] = socket;
      _receiveBuffers[ipAddress] = StringBuffer();
      _peerConnectedController.add(ipAddress);

      socket.listen(
        (data) => _handleIncomingData(ipAddress, data),
        onError: (error) {
          AppLogger.instance.error('Socket error for $ipAddress', error);
          _handleDisconnection(ipAddress);
        },
        onDone: () => _handleDisconnection(ipAddress),
      );

      AppLogger.instance.info('Connected to peer: $ipAddress');
    } catch (e, stackTrace) {
      AppLogger.instance
          .error('Failed to connect to peer: $ipAddress', e, stackTrace);
      throw ConnectionException('Failed to connect to peer: $ipAddress', e);
    }
  }

  void _handleIncomingData(String peerId, List<int> data) {
    try {
      final buffer = _receiveBuffers.putIfAbsent(peerId, StringBuffer.new);
      buffer.write(utf8.decode(data));

      final bufferedData = buffer.toString();
      final parts = bufferedData.split('\n');

      // The last part may be an incomplete message — keep it in the buffer
      _receiveBuffers[peerId] = StringBuffer(parts.removeLast());

      for (final part in parts) {
        final trimmed = part.trim();
        if (trimmed.isEmpty) continue;

        final jsonData = jsonDecode(trimmed) as Map<String, dynamic>;
        final packet = MessagePacket.fromJson(jsonData);

        AppLogger.instance
            .debug('Message received from $peerId: ${packet.id}');
        _messageReceivedController.add(packet);
      }
    } catch (e, stackTrace) {
      AppLogger.instance
          .error('Failed to handle incoming data from $peerId', e, stackTrace);
    }
  }

  void _handleDisconnection(String peerId) {
    try {
      final socket = _connections.remove(peerId);
      _receiveBuffers.remove(peerId);
      if (socket != null) {
        socket.close();
        AppLogger.instance.info('Peer disconnected: $peerId');
        _peerDisconnectedController.add(peerId);
      }
    } catch (e, stackTrace) {
      AppLogger.instance
          .error('Failed to handle disconnection for $peerId', e, stackTrace);
    }
  }

  Future<void> sendPacket(String ipAddress, MessagePacket packet) async {
    final socket = _connections[ipAddress];

    if (socket == null) {
      throw ConnectionException('Not connected to peer: $ipAddress');
    }

    try {
      final jsonData = '${jsonEncode(packet.toJson())}\n';
      socket.add(utf8.encode(jsonData));
      AppLogger.instance.debug('Packet sent to $ipAddress: ${packet.id}');
    } catch (e, stackTrace) {
      AppLogger.instance
          .error('Failed to send packet to $ipAddress', e, stackTrace);
      throw ConnectionException('Failed to send packet to $ipAddress', e);
    }
  }

  Future<void> disconnectPeer(String ipAddress) async {
    final socket = _connections.remove(ipAddress);
    _receiveBuffers.remove(ipAddress);

    if (socket != null) {
      await socket.close();
      AppLogger.instance.info('Disconnected from peer: $ipAddress');
      _peerDisconnectedController.add(ipAddress);
    }
  }

  bool isConnectedTo(String ipAddress) => _connections.containsKey(ipAddress);

  void dispose() {
    _reconnectTimer?.cancel();
    _messageReceivedController.close();
    _peerConnectedController.close();
    _peerDisconnectedController.close();
    stopServer();
  }
}
