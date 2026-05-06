// lib/services/background_service_manager.dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:pointycastle/export.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/bridge_config.dart';
import 'bridge_service.dart';
import 'log_service.dart';

const _kChannelId = 'phone_bridge_channel';
const _kChannelName = 'Phone Bridge Service';
const _kNotifId = 888;

// کلید رمزگذاری — باید با CryptoService یکسان باشد
final _aesKey = Uint8List.fromList([
  0x42, 0x72, 0x69, 0x64, 0x67, 0x65, 0x41, 0x70,
  0x70, 0x4B, 0x65, 0x79, 0x32, 0x30, 0x32, 0x34,
  0x53, 0x65, 0x63, 0x72, 0x65, 0x74, 0x58, 0x59,
  0x5A, 0x21, 0x40, 0x23, 0x24, 0x25, 0x5E, 0x26,
]);

Map<String, dynamic>? _decryptConfig(String encoded) {
  try {
    final raw = base64.decode(encoded.trim());
    if (raw.length < 17) return null;

    final iv = Uint8List.fromList(raw.sublist(0, 16));
    final cipher = Uint8List.fromList(raw.sublist(16));

    final params = ParametersWithIV(KeyParameter(_aesKey), iv);
    final cbcCipher = CBCBlockCipher(AESEngine());
    final paddedCipher =
        PaddedBlockCipherImpl(PKCS7Padding(), cbcCipher);
    paddedCipher.init(false, PaddedBlockCipherParameters(params, null));

    final plain = paddedCipher.process(cipher);
    final decoded = jsonDecode(utf8.decode(plain));
    if (decoded is Map<String, dynamic>) return decoded;
  } catch (_) {}
  return null;
}

Future<BridgeConfig> _loadConfigFromPrefs() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final authToken = prefs.getString('auth_token') ?? '';
    final encryptedConfig = prefs.getString('encrypted_config') ?? '';

    if (encryptedConfig.isNotEmpty) {
      final decrypted = _decryptConfig(encryptedConfig);
      if (decrypted != null) {
        return BridgeConfig(
          serverHost: decrypted['serverHost'] as String? ?? '',
          serverPort: decrypted['serverPort'] as int? ?? 443,
          wsPath: decrypted['wsPath'] as String? ?? '/api/bridge',
          isSSL: decrypted['isSSL'] as bool? ?? true,
          authToken: authToken,
        );
      }
    }

    final mapStr = prefs.getString('config_map');
    if (mapStr != null) {
      final map = jsonDecode(mapStr) as Map<String, dynamic>;
      return BridgeConfig.fromMap(map).copyWith(authToken: authToken);
    }
  } catch (_) {}
  return const BridgeConfig();
}

// ── Background entry point ────────────────────────────────

@pragma('vm:entry-point')
void onServiceStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  BridgeConfig config = await _loadConfigFromPrefs();
  final bridge = BridgeService(config);
  final log = LogService.instance;

  // این فلگ نشان می‌دهد آیا سرویس باید ادامه دهد
  bool shouldRun = true;

  service.on('stop').listen((_) async {
    shouldRun = false;
    log.info('Stop command received from UI.');
    await bridge.stop();
    // کمی صبر می‌کنیم تا cleanup کامل شود
    await Future.delayed(const Duration(milliseconds: 500));
    await service.stopSelf();
  });

  service.on('reconnect').listen((_) async {
    if (!shouldRun) return;
    log.info('Reconnect command received.');
    await bridge.stop();
    if (shouldRun) await bridge.start();
  });

  service.on('updateConfig').listen((data) async {
    if (data == null) return;
    try {
      final newConfig =
          BridgeConfig.fromMap(Map<String, dynamic>.from(data as Map));
      bridge.updateConfig(newConfig);
      if (bridge.isConnected || bridge.status == BridgeStatus.connecting) {
        await bridge.stop();
      }
      if (shouldRun) await bridge.start();
    } catch (_) {}
  });

  // شروع bridge
  if (config.isValid) {
    await bridge.start();
  } else {
    log.warn('Config is not configured. Please go to Settings.');
  }

  // Push stats — فقط وقتی shouldRun = true
  Timer.periodic(const Duration(seconds: 2), (timer) async {
    if (!shouldRun) {
      timer.cancel();
      return;
    }

    final stats = {
      'status': bridge.status.name,
      'activeSessions': bridge.activeSessions,
      'bytesIn': bridge.bytesIn,
      'bytesOut': bridge.bytesOut,
      'totalOpened': bridge.totalOpened,
      'shouldRun': shouldRun,
    };

    if (service is AndroidServiceInstance) {
      final content = switch (bridge.status) {
        BridgeStatus.connected =>
          '● Connected  ·  ${bridge.activeSessions} sessions',
        BridgeStatus.stopped => '○ Stopped',
        BridgeStatus.error => '✕ Error',
        _ => '○ Reconnecting…',
      };
      await service.setForegroundNotificationInfo(
        title: 'Bridge',
        content: content,
      );
    }

    service.invoke('stats', stats);

    // ارسال لاگ‌ها
    final logEntries = log.entries
        .map((e) => {
              'time': e.timeStr,
              'level': e.levelStr,
              'msg': e.message,
            })
        .toList();
    service.invoke('logs', {'entries': logEntries});
  });
}

// ── Manager ───────────────────────────────────────────────

class BackgroundServiceManager {
  static final _service = FlutterBackgroundService();
  static bool _configured = false;

  static Future<void> init() async {
    if (!_configured) {
      _configured = true;
      await _createNotificationChannel();
      await _service.configure(
        androidConfiguration: AndroidConfiguration(
          onStart: onServiceStart,
          isForegroundMode: true,
          autoStart: false,
          autoStartOnBoot: false,
          notificationChannelId: _kChannelId,
          initialNotificationTitle: 'Bridge',
          initialNotificationContent: 'Initializing…',
          foregroundServiceNotificationId: _kNotifId,
        ),
        iosConfiguration: IosConfiguration(
          autoStart: false,
          onForeground: onServiceStart,
          onBackground: _iosBackground,
        ),
      );
    }
  }

  static Future<void> startService() async {
    await init();
    if (!await _service.isRunning()) {
      await _service.startService();
    }
  }

  static Future<void> stopService() async {
    _service.invoke('stop');
    // polling تا متوقف شود
    for (int i = 0; i < 25; i++) {
      await Future.delayed(const Duration(milliseconds: 200));
      if (!await _service.isRunning()) break;
    }
  }

  static Future<bool> isRunning() => _service.isRunning();

  static void reconnect() => _service.invoke('reconnect');

  static void updateConfig(BridgeConfig config) {
    _service.invoke('updateConfig', config.toMap());
  }

  static Stream<Map<String, dynamic>> get statsStream =>
      _service.on('stats').map((data) => data == null
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(data));

  static Stream<List<Map<String, dynamic>>> get logsStream =>
      _service.on('logs').map((data) {
        if (data == null) return <Map<String, dynamic>>[];
        final entries = data['entries'] as List? ?? [];
        return entries
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      });

  static Future<void> _createNotificationChannel() async {
    final plugin = FlutterLocalNotificationsPlugin();
    const channel = AndroidNotificationChannel(
      _kChannelId,
      _kChannelName,
      description: 'Keeps the Bridge relay running',
      importance: Importance.low,
      playSound: false,
      enableVibration: false,
      showBadge: false,
    );
    await plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  @pragma('vm:entry-point')
  static Future<bool> _iosBackground(ServiceInstance service) async {
    DartPluginRegistrant.ensureInitialized();
    return true;
  }
}