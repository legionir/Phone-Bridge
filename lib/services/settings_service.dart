// lib/services/settings_service.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/bridge_config.dart';
import 'crypto_service.dart';

const _kAuthToken = 'auth_token';
const _kEncryptedConfig = 'encrypted_config';
const _kConfigMap = 'config_map';
const _kEnableForward = 'enable_forward';
const _kForwardPort = 'forward_port';

class SettingsService {
  static SettingsService? _instance;
  static SettingsService get instance => _instance ??= SettingsService._();
  SettingsService._();

  SharedPreferences? _prefs;

  Future<SharedPreferences> get _p async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  // ── Load ─────────────────────────────────────────────────

  Future<BridgeConfig> load() async {
    final p = await _p;

    final authToken = p.getString(_kAuthToken) ?? '';
    final encryptedConfig = p.getString(_kEncryptedConfig) ?? '';
    final enableForward = p.getBool(_kEnableForward) ?? false;
    final forwardPort = p.getInt(_kForwardPort) ?? 10808;

    // اگر config رمزگذاری شده وجود دارد
    if (encryptedConfig.isNotEmpty) {
      final decrypted = CryptoService.decrypt(encryptedConfig);
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

    // fallback
    final mapStr = p.getString(_kConfigMap);
    if (mapStr != null) {
      try {
        final map = jsonDecode(mapStr) as Map<String, dynamic>;
        return BridgeConfig.fromMap(map).copyWith(
          authToken: authToken,
          enableForward: enableForward,
          forwardPort: forwardPort,
        );
      } catch (_) {}
    }

    return BridgeConfig(
      authToken: authToken,
      enableForward: enableForward,
      forwardPort: forwardPort,
    );
  }

  // ── Save ─────────────────────────────────────────────────

  Future<void> saveAuthToken(String token) async {
    final p = await _p;
    await p.setString(_kAuthToken, token.trim());
  }

  Future<void> saveEncryptedConfig(String encoded) async {
    final p = await _p;
    await p.setString(_kEncryptedConfig, encoded.trim());
  }

  Future<void> saveForwardSettings({
    required bool enable,
    required int port,
  }) async {
    final p = await _p;
    await p.setBool(_kEnableForward, enable);
    await p.setInt(_kForwardPort, port);
  }

  Future<void> saveConfigMap(BridgeConfig config) async {
    final p = await _p;
    await p.setString(_kConfigMap, jsonEncode(config.toMap()));
  }

  Future<String> getAuthToken() async {
    final p = await _p;
    return p.getString(_kAuthToken) ?? '';
  }

  Future<String> getEncryptedConfig() async {
    final p = await _p;
    return p.getString(_kEncryptedConfig) ?? '';
  }

  Future<bool> getEnableForward() async {
    final p = await _p;
    return p.getBool(_kEnableForward) ?? false;
  }

  Future<int> getForwardPort() async {
    final p = await _p;
    return p.getInt(_kForwardPort) ?? 10808;
  }

  // ── Validate encrypted string ─────────────────────────────

  static Map<String, dynamic>? validateEncrypted(String encoded) {
    if (encoded.trim().isEmpty) return null;
    return CryptoService.decrypt(encoded.trim());
  }

  // ── Clear ─────────────────────────────────────────────────

  Future<void> clear() async {
    final p = await _p;
    await p.remove(_kAuthToken);
    await p.remove(_kEncryptedConfig);
    await p.remove(_kConfigMap);
    await p.remove(_kEnableForward);
    await p.remove(_kForwardPort);
  }
}