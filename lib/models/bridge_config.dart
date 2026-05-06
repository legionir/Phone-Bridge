// lib/models/bridge_config.dart
// All config is hardcoded here — not exposed in UI

class BridgeConfig {
  // ── CHANGE THESE BEFORE BUILD ──────────────────────────
  static const String kServerHost = 'panel.mr-expert.ir';
  static const int kServerPort = 443;
  static const String kWsPath = '/api/bridge';
  static const String kAuthToken = 'phone-secret-token';
  // ───────────────────────────────────────────────────────

  final String serverHost;
  final int serverPort;
  final String wsPath;
  final String authToken;
  final bool autoReconnect;
  final int reconnectBaseMs;
  final int reconnectMaxMs;
  final int pingIntervalMs;
  final int maxSessions;

  const BridgeConfig({
    this.serverHost = kServerHost,
    this.serverPort = kServerPort,
    this.wsPath = kWsPath,
    this.authToken = kAuthToken,
    this.autoReconnect = true,
    this.reconnectBaseMs = 1000,
    this.reconnectMaxMs = 30000,
    this.pingIntervalMs = 25000,
    this.maxSessions = 2000,
  });

  String get wsUrl {
    final base = 'wss://$serverHost';
    return wsPath.isEmpty ? base : '$base$wsPath';
  }
}
