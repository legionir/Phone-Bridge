// فقط تابع _loadConfigFromPrefs تغییر می‌کند — بقیه فایل بدون تغییر
// جایگزین کنید:

Future<BridgeConfig> _loadConfigFromPrefs() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final authToken = prefs.getString('auth_token') ?? '';
    final encryptedConfig = prefs.getString('encrypted_config') ?? '';
    final enableForward = prefs.getBool('enable_forward') ?? false;
    final forwardPort = prefs.getInt('forward_port') ?? 10808;

    if (encryptedConfig.isNotEmpty) {
      final decrypted = _decryptConfig(encryptedConfig);
      if (decrypted != null) {
        return BridgeConfig(
          serverHost: decrypted['serverHost'] as String? ?? '',
          serverPort: decrypted['serverPort'] as int? ?? 443,
          wsPath: decrypted['wsPath'] as String? ?? '/api/bridge',
          isSSL: decrypted['isSSL'] as bool? ?? true,
          authToken: authToken,
          enableForward: enableForward,
          forwardPort: forwardPort,
        );
      }
    }

    final mapStr = prefs.getString('config_map');
    if (mapStr != null) {
      final map = jsonDecode(mapStr) as Map<String, dynamic>;
      return BridgeConfig.fromMap(map).copyWith(
        authToken: authToken,
        enableForward: enableForward,
        forwardPort: forwardPort,
      );
    }
  } catch (_) {}
  return const BridgeConfig();
}
┌─────────────────────────────────────────────────────┐
│  Forward OFF (مستقیم)                                │
│  OPEN(host,port) → Socket.connect(host, port)       │
│                                                      │
│  Forward ON                                          │
│  OPEN(host,port) → SOCKS5(127.0.0.1:10808) → target │
│                    ↑ v2rayNG                         │
└─────────────────────────────────────────────────────┘