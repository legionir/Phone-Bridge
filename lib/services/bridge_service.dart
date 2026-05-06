// lib/services/bridge_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../models/bridge_config.dart';
import '../models/frame.dart';
import 'log_service.dart';
import 'socks5_connector.dart';

enum BridgeStatus {
  idle,
  connecting,
  connected,
  reconnecting,
  stopped,
  error,
}

class BridgeService {
  BridgeConfig _config;
  final LogService _log = LogService.instance;

  BridgeService(this._config);

  // ─────────────────────────────────────────
  // State
  // ─────────────────────────────────────────

  BridgeStatus _status = BridgeStatus.idle;
  BridgeStatus get status => _status;
  bool get isConnected => _status == BridgeStatus.connected;

  // ─────────────────────────────────────────
  // Metrics
  // ─────────────────────────────────────────

  int bytesIn = 0;
  int bytesOut = 0;
  int activeSessions = 0;
  int totalOpened = 0;
  int reconnectAttempts = 0;

  DateTime? _connectedAt;
  Duration get uptime => _connectedAt != null
      ? DateTime.now().difference(_connectedAt!)
      : Duration.zero;

  // ─────────────────────────────────────────
  // Internals
  // ─────────────────────────────────────────

  WebSocket? _ws;
  Future<void>? _loopTask;
  bool _manualStop = false;

  int _retryDelay = 2;
  static const int _maxRetry = 60;
  final Random _rng = Random();

  final Map<String, _BridgeSession> _sessions = {};

  // ─────────────────────────────────────────
  // Public API
  // ─────────────────────────────────────────

  Future<void> start() async {
    if (_loopTask != null) return;

    _manualStop = false;
    _transition(BridgeStatus.connecting);

    if (_config.enableForward) {
      _log.info(
          'Forward mode ON → SOCKS5 127.0.0.1:${_config.forwardPort}');
    } else {
      _log.info('Forward mode OFF → direct connections');
    }

    _log.info('Bridge service starting...');

    _loopTask = _runLoop().whenComplete(() {
      _loopTask = null;
    });
  }

  Future<void> stop() async {
    _manualStop = true;
    _log.info('Bridge service stopping...');
    _transition(BridgeStatus.stopped);

    await _cleanup();

    final task = _loopTask;
    if (task != null) {
      try {
        await task.timeout(const Duration(seconds: 3));
      } catch (_) {}
    }
    _log.info('Bridge service stopped.');
  }

  void updateConfig(BridgeConfig config) {
    _config = config;
    _log.info('Config updated.');
    if (config.enableForward) {
      _log.info('Forward → SOCKS5 :${config.forwardPort}');
    }
  }

  // ─────────────────────────────────────────
  // Core loop
  // ─────────────────────────────────────────

  Future<void> _runLoop() async {
    while (!_manualStop) {
      try {
        await _connect();
        _retryDelay = 2;
        reconnectAttempts = 0;
        await _listen();

        if (_manualStop) break;
        _log.warn('WebSocket disconnected unexpectedly.');
        throw Exception('WebSocket closed');
      } catch (e) {
        if (_manualStop) break;

        _transition(BridgeStatus.reconnecting);
        reconnectAttempts++;

        await _cleanup();

        final delay = _computeBackoff();
        _log.warn(
          'Reconnect attempt $reconnectAttempts in ${delay.inSeconds}s...',
        );
        await _waitWithCancel(delay);
      }
    }
  }

  // ─────────────────────────────────────────
  // Connect (WebSocket to server — DIRECT, not through forward)
  // ─────────────────────────────────────────

  Future<void> _connect() async {
    _transition(BridgeStatus.connecting);
    _log.info('Connecting to relay server...');

    if (!_config.isValid) {
      throw StateError('Config is not valid — check settings.');
    }

    final uri = Uri.parse(_config.wsUrl);

    final authToken = _config.authToken.trim();
    final authHeader = authToken.toLowerCase().startsWith('bearer ')
        ? authToken
        : 'Bearer $authToken';

    final ws = await WebSocket.connect(
      uri.toString(),
      headers: {'Authorization': authHeader},
    ).timeout(const Duration(seconds: 15));

    ws.pingInterval = const Duration(seconds: 20);

    _ws = ws;
    _connectedAt = DateTime.now();
    _transition(BridgeStatus.connected);
    _log.info('Connected to relay successfully.');
  }

  // ─────────────────────────────────────────
  // Listen
  // ─────────────────────────────────────────

  Future<void> _listen() async {
    final ws = _ws;
    if (ws == null) throw StateError('WebSocket is not connected');

    final frameBuffer = FrameBuffer(_onFrame);

    await for (final raw in ws) {
      if (_manualStop) break;
      if (raw is List<int>) {
        final chunk = raw is Uint8List ? raw : Uint8List.fromList(raw);
        bytesIn += chunk.length;
        frameBuffer.push(chunk);
      }
    }

    frameBuffer.reset();
  }

  // ─────────────────────────────────────────
  // Frame handling
  // ─────────────────────────────────────────

  void _onFrame(FrameType type, String sessionId, Uint8List payload) {
    if (_manualStop) return;
    switch (type) {
      case FrameType.open:
        _handleOpen(sessionId, payload);
        break;
      case FrameType.data:
        _handleData(sessionId, payload);
        break;
      case FrameType.close:
        _handleRemoteClose(sessionId);
        break;
      case FrameType.ackOpen:
        break;
    }
  }

  /// اتصال به مقصد — مستقیم یا از طریق SOCKS5 proxy
  Future<void> _handleOpen(String sessionId, Uint8List payload) async {
    try {
      final meta = _parseOpenPayload(payload);
      _log.debug('Session $sessionId: open → [TARGET]');

      await _closeSession(sessionId, notifyServer: false);

      // ── اتصال TCP ────────────────────────────────────
      Socket socket;

      if (_config.enableForward) {
        // از طریق SOCKS5 proxy محلی (v2rayNG)
        _log.debug(
          'Session $sessionId: connecting via SOCKS5 :${_config.forwardPort}',
        );
        socket = await Socks5Connector.connect(
          targetHost: meta.host,
          targetPort: meta.port,
          proxyPort: _config.forwardPort,
          timeout: const Duration(seconds: 15),
        );
      } else {
        // اتصال مستقیم
        socket = await Socket.connect(
          meta.host,
          meta.port,
          timeout: const Duration(seconds: 10),
        );
      }

      try {
        socket.setOption(SocketOption.tcpNoDelay, true);
      } catch (_) {}

      final session = _BridgeSession(sessionId, socket);
      _sessions[sessionId] = session;
      activeSessions = _sessions.length;
      totalOpened++;

      session.subscription = socket.listen(
        (chunk) {
          if (_manualStop) return;
          final bytes =
              chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
          _sendFrame(Frame.data(sessionId, bytes));
        },
        onDone: () => _closeSession(sessionId, notifyServer: true),
        onError: (_) => _closeSession(sessionId, notifyServer: true),
        cancelOnError: true,
      );

      _sendFrame(Frame.ackOpen(sessionId));
    } catch (e) {
      _log.error('Session $sessionId: ${_sanitizeError(e)}');
      _sendFrame(Frame.close(sessionId));
    }
  }

  void _handleData(String sessionId, Uint8List payload) {
    final session = _sessions[sessionId];
    if (session == null) return;
    try {
      session.socket.add(payload);
    } catch (_) {
      _closeSession(sessionId, notifyServer: true);
    }
  }

  void _handleRemoteClose(String sessionId) {
    _closeSession(sessionId, notifyServer: false);
  }

  _OpenMeta _parseOpenPayload(Uint8List payload) {
    final decoded = jsonDecode(utf8.decode(payload));
    if (decoded is! Map) {
      throw const FormatException('OPEN payload must be a JSON object');
    }

    final host = (decoded['host'] ?? '').toString().trim();
    final portRaw = decoded['port'];
    final int port;
    if (portRaw is int) {
      port = portRaw;
    } else {
      port = int.parse(portRaw.toString());
    }

    if (host.isEmpty || port < 1 || port > 65535) {
      throw const FormatException('Invalid OPEN target');
    }
    return _OpenMeta(host, port);
  }

  // ─────────────────────────────────────────
  // Send
  // ─────────────────────────────────────────

  void _sendFrame(Frame frame) {
    if (_manualStop) return;
    final ws = _ws;
    if (ws == null) return;
    try {
      final bytes = frame.toBytes();
      ws.add(bytes);
      bytesOut += bytes.length;
    } catch (_) {}
  }

  // ─────────────────────────────────────────
  // Session cleanup
  // ─────────────────────────────────────────

  Future<void> _closeSession(
    String sessionId, {
    required bool notifyServer,
  }) async {
    final session = _sessions.remove(sessionId);
    if (session == null) return;
    activeSessions = _sessions.length;
    await session.close();
    if (notifyServer && !_manualStop) {
      _sendFrame(Frame.close(sessionId));
    }
  }

  Future<void> _cleanup() async {
    final existing = _sessions.values.toList();
    _sessions.clear();
    activeSessions = 0;

    for (final s in existing) {
      try {
        await s.close();
      } catch (_) {}
    }

    final ws = _ws;
    _ws = null;
    _connectedAt = null;

    if (ws != null) {
      try {
        await ws.close();
      } catch (_) {}
    }
  }

  // ─────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────

  Duration _computeBackoff() {
    _retryDelay = min(_retryDelay * 2, _maxRetry);
    final jitterMs = _rng.nextInt(1000);
    return Duration(seconds: _retryDelay) + Duration(milliseconds: jitterMs);
  }

  Future<void> _waitWithCancel(Duration duration) async {
    var remaining = duration;
    const step = Duration(milliseconds: 200);
    while (!_manualStop && remaining > Duration.zero) {
      final cur = remaining < step ? remaining : step;
      await Future.delayed(cur);
      remaining -= cur;
    }
  }

  void _transition(BridgeStatus newState) {
    _status = newState;
  }

  String _sanitizeError(Object e) {
    return e
        .toString()
        .replaceAllMapped(
          RegExp(r'\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b'),
          (_) => '[SERVER]',
        )
        .replaceAllMapped(
          RegExp(r'wss?://[^\s]+'),
          (_) => '[WS_URL]',
        );
  }
}

class _OpenMeta {
  final String host;
  final int port;
  const _OpenMeta(this.host, this.port);
}

class _BridgeSession {
  final String sessionId;
  final Socket socket;
  StreamSubscription<Uint8List>? subscription;
  bool _closing = false;

  _BridgeSession(this.sessionId, this.socket);

  Future<void> close() async {
    if (_closing) return;
    _closing = true;
    try {
      await subscription?.cancel();
    } catch (_) {}
    try {
      await socket.close();
    } catch (_) {}
    try {
      socket.destroy();
    } catch (_) {}
  }
}