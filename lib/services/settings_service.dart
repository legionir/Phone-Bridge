// lib/services/settings_service.dart
// Config is now hardcoded in BridgeConfig — this file is kept for compatibility.
import '../models/bridge_config.dart';

class SettingsService {
  Future<BridgeConfig> load() async => const BridgeConfig();
  Future<void> save(BridgeConfig _) async {}
}
