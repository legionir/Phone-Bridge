// lib/services/background_service_manager.dart
import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/bridge_config.dart';
import 'bridge_service.dart';

const _kChannelId = 'phone_bridge_channel';
const _kChannelName = 'Phone Bridge Service';
const _kNotifId = 888;

// ── Background entry point ────────────────────────────────

@pragma('vm:entry-point')
void onServiceStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  // Config is hardcoded — no SharedPreferences needed
  const config = BridgeConfig();
  final bridge = BridgeService(config);
  await bridge.start();

  // Push stats to UI every 3 seconds
  Timer.periodic(const Duration(seconds: 3), (_) async {
    final stats = {
      'status': bridge.status.name,
      'activeSessions': bridge.activeSessions,
      'bytesIn': bridge.bytesIn,
      'bytesOut': bridge.bytesOut,
      'totalOpened': bridge.totalOpened,
    };

    if (service is AndroidServiceInstance) {
      final label = bridge.isConnected
          ? '● Connected  ·  ${bridge.activeSessions} active sessions'
          : '○ Reconnecting…';
      await service.setForegroundNotificationInfo(
        title: 'Bridge',
        content: label,
      );
    }

    service.invoke('stats', stats);
  });

  // Commands from UI
  service.on('stop').listen((_) async {
    await bridge.stop();
    service.stopSelf();
  });

  service.on('reconnect').listen((_) async {
    await bridge.stop();
    await bridge.start();
  });

  // Config update (ignored — config is hardcoded)
  service.on('updateConfig').listen((_) {});
}

// ── Manager ───────────────────────────────────────────────

class BackgroundServiceManager {
  static final _service = FlutterBackgroundService();
  // _configured tracks whether configure() was called.
  // configure() only needs to run once per app lifetime.
  // startService() must be called every time we want to (re)start.
  static bool _configured = false;

  static Future<void> init() async {
    // configure() registers the entry point — only needs to happen once
    if (!_configured) {
      _configured = true;
      await _createNotificationChannel();
      await _service.configure(
        androidConfiguration: AndroidConfiguration(
          onStart: onServiceStart,
          isForegroundMode: true,
          autoStart: true,
          autoStartOnBoot: true,
          notificationChannelId: _kChannelId,
          initialNotificationTitle: 'Bridge',
          initialNotificationContent: 'Starting…',
          foregroundServiceNotificationId: _kNotifId,
        ),
        iosConfiguration: IosConfiguration(
          autoStart: true,
          onForeground: onServiceStart,
          onBackground: _iosBackground,
        ),
      );
    }

    // Always call startService() — it's safe to call even if already running
    final running = await _service.isRunning();
    if (!running) {
      await _service.startService();
    }
  }

  static Future<bool> isRunning() => _service.isRunning();

  static void stop() => _service.invoke('stop');
  static void reconnect() => _service.invoke('reconnect');

  // Config updates are no-op (hardcoded)
  static void updateConfig(BridgeConfig _) {}

  static Stream<Map<String, dynamic>> get statsStream =>
      _service.on('stats').map((data) =>
          data == null ? <String, dynamic>{} : Map<String, dynamic>.from(data));

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
