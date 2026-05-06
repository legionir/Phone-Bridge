// lib/services/permission_manager.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionStatus {
  final bool batteryOptimizationDisabled;
  final bool notificationsGranted;
  const PermissionStatus({
    required this.batteryOptimizationDisabled,
    required this.notificationsGranted,
  });
  bool get allGood => batteryOptimizationDisabled && notificationsGranted;
}

class PermissionManager {
  static Future<PermissionStatus> checkAll() async {
    if (!Platform.isAndroid) {
      return const PermissionStatus(
          batteryOptimizationDisabled: true, notificationsGranted: true);
    }
    return PermissionStatus(
      batteryOptimizationDisabled:
          await Permission.ignoreBatteryOptimizations.isGranted,
      notificationsGranted: await Permission.notification.isGranted,
    );
  }

  static Future<bool> requestBatteryOptimization() async {
    if (!Platform.isAndroid) return true;
    return (await Permission.ignoreBatteryOptimizations.request()).isGranted;
  }

  static Future<bool> requestNotifications() async {
    if (!Platform.isAndroid) return true;
    final r = await Permission.notification.request();
    return r.isGranted || r.isLimited;
  }

  static Future<PermissionStatus> requestAll() async {
    await requestNotifications();
    await requestBatteryOptimization();
    return checkAll();
  }

  static Future<void> showPermissionDialog(BuildContext context) async {
    final status = await checkAll();
    if (status.allGood) return;
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(.7),
      builder: (ctx) => _PermissionDialog(initialStatus: status),
    );
  }
}

// ── Dialog ────────────────────────────────────────────────

class _PermissionDialog extends StatefulWidget {
  final PermissionStatus initialStatus;
  const _PermissionDialog({required this.initialStatus});
  @override
  State<_PermissionDialog> createState() => _PermissionDialogState();
}

class _PermissionDialogState extends State<_PermissionDialog>
    with SingleTickerProviderStateMixin {
  late PermissionStatus _status;
  bool _loading = false;
  late AnimationController _slideCtrl;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _status = widget.initialStatus;
    _slideCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _slideAnim = Tween<Offset>(begin: const Offset(0, .15), end: Offset.zero)
        .animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOut));
    _slideCtrl.forward();
  }

  @override
  void dispose() {
    _slideCtrl.dispose();
    super.dispose();
  }

  Future<void> _requestAll() async {
    setState(() => _loading = true);
    _status = await PermissionManager.requestAll();
    setState(() => _loading = false);
    if (_status.allGood && mounted) Navigator.of(context).pop();
  }

  Future<void> _openSettings() async {
    await openAppSettings();
    await Future.delayed(const Duration(milliseconds: 500));
    _status = await PermissionManager.checkAll();
    setState(() {});
    if (_status.allGood && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF0D1117);
    const surface = Color(0xFF161B27);
    const border = Color(0xFF1C2333);
    const cyan = Color(0xFF00F5C4);
    const amber = Color(0xFFFFB627);
    const textCol = Color(0xFFEAEEF4);
    const dimCol = Color(0xFF4A5568);

    return Dialog(
      backgroundColor: Colors.transparent,
      child: SlideTransition(
        position: _slideAnim,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 360),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: border, width: 1),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(.5),
                  blurRadius: 40,
                  offset: const Offset(0, 20)),
            ],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Header
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: border, width: 1)),
              ),
              child: Row(children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: amber.withOpacity(.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: amber.withOpacity(.3), width: 1),
                  ),
                  child: const Icon(Icons.shield_outlined,
                      color: Color(0xFFFFB627), size: 20),
                ),
                const SizedBox(width: 16),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Permissions Required',
                      style: TextStyle(
                        color: textCol,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        letterSpacing: .3,
                      )),
                  const SizedBox(height: 3),
                  Text('For always-on background relay',
                      style: TextStyle(
                        color: dimCol,
                        fontSize: 12,
                      )),
                ]),
              ]),
            ),

            // Permissions list
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(children: [
                _PermRow(
                  icon: Icons.battery_saver_outlined,
                  title: 'Battery Optimization',
                  subtitle:
                      'Must be disabled — service will be killed otherwise',
                  granted: _status.batteryOptimizationDisabled,
                ),
                const SizedBox(height: 10),
                _PermRow(
                  icon: Icons.notifications_outlined,
                  title: 'Notifications',
                  subtitle: 'Show persistent status in notification bar',
                  granted: _status.notificationsGranted,
                ),
              ]),
            ),

            // Actions
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Column(children: [
                if (!_status.allGood) ...[
                  _DialogButton(
                    label: _loading ? 'Requesting...' : 'Grant Permissions',
                    accent: cyan,
                    filled: true,
                    onTap: _loading ? null : _requestAll,
                  ),
                  const SizedBox(height: 10),
                  _DialogButton(
                    label: 'Open Settings',
                    accent: amber,
                    filled: false,
                    onTap: _openSettings,
                  ),
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Text('Skip for now (unstable)',
                        style: TextStyle(
                            color: dimCol,
                            fontSize: 12,
                            decoration: TextDecoration.underline,
                            decorationColor: dimCol)),
                  ),
                ] else
                  _DialogButton(
                    label: 'All Set  ✓',
                    accent: cyan,
                    filled: true,
                    onTap: () => Navigator.of(context).pop(),
                  ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _PermRow extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final bool granted;
  const _PermRow(
      {required this.icon,
      required this.title,
      required this.subtitle,
      required this.granted});

  @override
  Widget build(BuildContext context) {
    const border = Color(0xFF1C2333);
    const textCol = Color(0xFFEAEEF4);
    const dimCol = Color(0xFF4A5568);
    const cyan = Color(0xFF00F5C4);
    const amber = Color(0xFFFFB627);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF161B27),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border, width: 1),
      ),
      child: Row(children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: (granted ? cyan : amber).withOpacity(.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: granted ? cyan : amber, size: 17),
        ),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: const TextStyle(
                  color: textCol, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 3),
          Text(subtitle,
              style: const TextStyle(color: dimCol, fontSize: 11, height: 1.4)),
        ])),
        const SizedBox(width: 8),
        Icon(
            granted
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            color: granted ? cyan : const Color(0xFF2D3748),
            size: 20),
      ]),
    );
  }
}

class _DialogButton extends StatefulWidget {
  final String label;
  final Color accent;
  final bool filled;
  final VoidCallback? onTap;
  const _DialogButton(
      {required this.label,
      required this.accent,
      required this.filled,
      this.onTap});
  @override
  State<_DialogButton> createState() => _DialogButtonState();
}

class _DialogButtonState extends State<_DialogButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final disabled = widget.onTap == null;
    return GestureDetector(
      onTapDown: (_) {
        if (!disabled) setState(() => _pressed = true);
      },
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap?.call();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 48,
        width: double.infinity,
        decoration: BoxDecoration(
          color: widget.filled
              ? (disabled
                  ? widget.accent.withOpacity(.15)
                  : _pressed
                      ? widget.accent.withOpacity(.3)
                      : widget.accent.withOpacity(.18))
              : Colors.transparent,
          border: Border.all(
            color: widget.accent.withOpacity(disabled ? .2 : .5),
            width: 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text(widget.label,
              style: TextStyle(
                color: widget.accent.withOpacity(disabled ? .4 : 1),
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              )),
        ),
      ),
    );
  }
}
