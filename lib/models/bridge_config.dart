// lib/models/bridge_config.dart
class BridgeConfig {
  final String serverHost;
  final int serverPort;
  final String wsPath;
  final bool isSSL;
  final String authToken;
  final bool autoReconnect;
  final int reconnectBaseMs;
  final int reconnectMaxMs;
  final int pingIntervalMs;
  final int maxSessions;
  // ── Forward Proxy ──
  final bool enableForward;
  final int forwardPort;

  const BridgeConfig({
    this.serverHost = '',
    this.serverPort = 443,
    this.wsPath = '/api/bridge',
    this.isSSL = true,
    this.authToken = '',
    this.autoReconnect = true,
    this.reconnectBaseMs = 1000,
    this.reconnectMaxMs = 30000,
    this.pingIntervalMs = 25000,
    this.maxSessions = 2000,
    this.enableForward = false,
    this.forwardPort = 10808,
  });

  String get wsUrl {
    final scheme = isSSL ? 'wss' : 'ws';
    final base = '$scheme://$serverHost:$serverPort';
    final path = wsPath.startsWith('/') ? wsPath : '/$wsPath';
    return '$base$path';
  }

  BridgeConfig copyWith({
    String? serverHost,
    int? serverPort,
    String? wsPath,
    bool? isSSL,
    String? authToken,
    bool? autoReconnect,
    int? reconnectBaseMs,
    int? reconnectMaxMs,
    int? pingIntervalMs,
    int? maxSessions,
    bool? enableForward,
    int? forwardPort,
  }) {
    return BridgeConfig(
      serverHost: serverHost ?? this.serverHost,
      serverPort: serverPort ?? this.serverPort,
      wsPath: wsPath ?? this.wsPath,
      isSSL: isSSL ?? this.isSSL,
      authToken: authToken ?? this.authToken,
      autoReconnect: autoReconnect ?? this.autoReconnect,
      reconnectBaseMs: reconnectBaseMs ?? this.reconnectBaseMs,
      reconnectMaxMs: reconnectMaxMs ?? this.reconnectMaxMs,
      pingIntervalMs: pingIntervalMs ?? this.pingIntervalMs,
      maxSessions: maxSessions ?? this.maxSessions,
      enableForward: enableForward ?? this.enableForward,
      forwardPort: forwardPort ?? this.forwardPort,
    );
  }

  Map<String, dynamic> toMap() => {
        'serverHost': serverHost,
        'serverPort': serverPort,
        'wsPath': wsPath,
        'isSSL': isSSL,
        'authToken': authToken,
        'autoReconnect': autoReconnect,
        'reconnectBaseMs': reconnectBaseMs,
        'reconnectMaxMs': reconnectMaxMs,
        'pingIntervalMs': pingIntervalMs,
        'maxSessions': maxSessions,
        'enableForward': enableForward,
        'forwardPort': forwardPort,
      };

  factory BridgeConfig.fromMap(Map<String, dynamic> m) => BridgeConfig(
        serverHost: m['serverHost'] as String? ?? '',
        serverPort: m['serverPort'] as int? ?? 443,
        wsPath: m['wsPath'] as String? ?? '/api/bridge',
        isSSL: m['isSSL'] as bool? ?? true,
        authToken: m['authToken'] as String? ?? '',
        autoReconnect: m['autoReconnect'] as bool? ?? true,
        reconnectBaseMs: m['reconnectBaseMs'] as int? ?? 1000,
        reconnectMaxMs: m['reconnectMaxMs'] as int? ?? 30000,
        pingIntervalMs: m['pingIntervalMs'] as int? ?? 25000,
        maxSessions: m['maxSessions'] as int? ?? 2000,
        enableForward: m['enableForward'] as bool? ?? false,
        forwardPort: m['forwardPort'] as int? ?? 10808,
      );

  bool get isValid => serverHost.isNotEmpty && authToken.isNotEmpty;
}