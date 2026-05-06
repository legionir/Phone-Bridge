// lib/screens/home_screen.dart
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/background_service_manager.dart';
import '../services/permission_manager.dart';
import '../services/settings_service.dart';
import 'settings_screen.dart';
import 'log_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // ── data ─────────────────────────────────────────────────
  StreamSubscription? _statsSub;
  String _status = 'disconnected';
  int _sessions = 0;
  int _bytesIn = 0;
  int _bytesOut = 0;
  int _total = 0;
  bool _svcRunning = false;
  // فلگ جداگانه برای کنترل UI — جلوگیری از sync مشکل
  bool _userRequestedStop = false;

  // ── animation controllers ─────────────────────────────────
  late AnimationController _pulseCtrl;
  late AnimationController _ringCtrl;

  late Animation<double> _pulseAnim;
  late Animation<double> _ringAnim;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _pulseCtrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..repeat(reverse: true);
    _ringCtrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 3))
          ..repeat();

    _pulseAnim = Tween<double>(begin: 0.6, end: 1.0)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _ringAnim = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _ringCtrl, curve: Curves.linear));

    _init();
  }

  Future<void> _init() async {
    await BackgroundServiceManager.init();
    _svcRunning = await BackgroundServiceManager.isRunning();

    _statsSub = BackgroundServiceManager.statsStream.listen((d) {
      if (!mounted) return;
      // اگر کاربر stop زده، stats از سرویس را نادیده بگیر
      if (_userRequestedStop) return;

      final svcRunning = d['shouldRun'] as bool? ?? true;
      setState(() {
        _status = d['status'] as String? ?? 'disconnected';
        _sessions = d['activeSessions'] as int? ?? 0;
        _bytesIn = d['bytesIn'] as int? ?? 0;
        _bytesOut = d['bytesOut'] as int? ?? 0;
        _total = d['totalOpened'] as int? ?? 0;
        _svcRunning = svcRunning;
      });
    });

    if (mounted) setState(() {});
    await Future.delayed(const Duration(milliseconds: 800));
    if (mounted) await PermissionManager.showPermissionDialog(context);
  }

  @override
  void dispose() {
    _statsSub?.cancel();
    _pulseCtrl.dispose();
    _ringCtrl.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) {
      BackgroundServiceManager.isRunning().then((v) {
        if (mounted && !_userRequestedStop) {
          setState(() => _svcRunning = v);
        }
      });
    }
  }

  bool get _isConnected => _status == 'connected' && !_userRequestedStop;
  bool get _isConnecting =>
      (_status == 'connecting' || _status == 'reconnecting') &&
      !_userRequestedStop;

  // ── colors by status ──────────────────────────────────────
  Color get _accentColor {
    if (_userRequestedStop || !_svcRunning) return const Color(0xFF3D4557);
    return switch (_status) {
      'connected' => const Color(0xFF00F5C4),
      'connecting' || 'reconnecting' => const Color(0xFFFFB627),
      'error' => const Color(0xFFFF4560),
      _ => const Color(0xFF3D4557),
    };
  }

  // ── actions ───────────────────────────────────────────────
  Future<void> _toggleService() async {
    if (_svcRunning) {
      // UI فوری بروز شود
      setState(() {
        _userRequestedStop = true;
        _svcRunning = false;
        _status = 'stopped';
        _sessions = 0;
      });

      await BackgroundServiceManager.stopService();

      if (mounted) {
        setState(() {
          _status = 'disconnected';
        });
      }
    } else {
      // بررسی config
      final config = await SettingsService.instance.load();
      if (!config.isValid) {
        if (mounted) {
          _showConfigWarning();
        }
        return;
      }

      setState(() {
        _userRequestedStop = false;
        _status = 'connecting';
      });

      await BackgroundServiceManager.startService();

      for (int i = 0; i < 15; i++) {
        await Future.delayed(const Duration(milliseconds: 200));
        if (await BackgroundServiceManager.isRunning()) break;
      }

      final running = await BackgroundServiceManager.isRunning();
      if (mounted) {
        setState(() {
          _svcRunning = running;
          if (!running) _status = 'disconnected';
        });
      }
    }
  }

  void _showConfigWarning() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0D1117),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
              color: const Color(0xFFFFB627).withOpacity(.3), width: 1),
        ),
        title: const Row(children: [
          Icon(Icons.warning_amber_rounded,
              color: Color(0xFFFFB627), size: 20),
          SizedBox(width: 8),
          Text(
            'Config Required',
            style: TextStyle(
              color: Color(0xFFEAEEF4),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ]),
        content: const Text(
          'Please configure Auth Token and Connection Config in Settings before starting the service.',
          style: TextStyle(
            color: Color(0xFF6B7280),
            fontSize: 13,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Later',
                style: TextStyle(color: Color(0xFF4A5568))),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _openSettings();
            },
            child: const Text('Open Settings',
                style: TextStyle(
                    color: Color(0xFF00F5C4),
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _reconnect() {
    if (!_svcRunning) return;
    BackgroundServiceManager.reconnect();
  }

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }

  void _openLogs() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LogScreen()),
    );
  }

  // ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: const Color(0xFF080B10),
      body: Stack(children: [
        const _GridBackground(),
        SafeArea(
          child: Column(children: [
            _buildTopBar(),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(children: [
                  SizedBox(height: size.height * 0.04),
                  _buildOrb(),
                  const SizedBox(height: 40),
                  _buildStatusLabel(),
                  const SizedBox(height: 48),
                  _buildMetricsRow(),
                  const SizedBox(height: 48),
                  _buildActionRow(),
                  const SizedBox(height: 40),
                ]),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  // ── TOP BAR ───────────────────────────────────────────────

  Widget _buildTopBar() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            RichText(
              text: TextSpan(
                style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 18,
                    letterSpacing: 4),
                children: [
                  const TextSpan(
                    text: 'BRIDGE',
                    style: TextStyle(
                      color: Color(0xFFEAEEF4),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  TextSpan(
                    text: '.SVC',
                    style: TextStyle(color: _accentColor),
                  ),
                ],
              ),
            ),
            Row(children: [
              // Logs button
              _TopBarButton(
                icon: Icons.terminal_rounded,
                onTap: _openLogs,
                tooltip: 'Logs',
              ),
              const SizedBox(width: 8),
              // Settings button
              _TopBarButton(
                icon: Icons.settings_rounded,
                onTap: _openSettings,
                tooltip: 'Settings',
              ),
              const SizedBox(width: 8),
              // Service status pill
              AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: (_svcRunning && !_userRequestedStop
                          ? const Color(0xFF00F5C4)
                          : const Color(0xFF3D4557))
                      .withOpacity(.12),
                  border: Border.all(
                    color: (_svcRunning && !_userRequestedStop
                            ? const Color(0xFF00F5C4)
                            : const Color(0xFF3D4557))
                        .withOpacity(.4),
                    width: 1,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _svcRunning && !_userRequestedStop
                          ? const Color(0xFF00F5C4)
                          : const Color(0xFF3D4557),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    _svcRunning && !_userRequestedStop
                        ? 'ON'
                        : 'OFF',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 9,
                      letterSpacing: 2,
                      fontWeight: FontWeight.w600,
                      color: _svcRunning && !_userRequestedStop
                          ? const Color(0xFF00F5C4)
                          : const Color(0xFF3D4557),
                    ),
                  ),
                ]),
              ),
            ]),
          ],
        ),
      );

  // ── ORB ───────────────────────────────────────────────────

  Widget _buildOrb() => SizedBox(
        width: 200,
        height: 200,
        child: Stack(alignment: Alignment.center, children: [
          if (_isConnecting || _isConnected)
            AnimatedBuilder(
              animation: _ringAnim,
              builder: (_, __) => Transform.rotate(
                angle: _ringAnim.value * 2 * math.pi,
                child: CustomPaint(
                  size: const Size(200, 200),
                  painter: _ArcPainter(color: _accentColor.withOpacity(.3)),
                ),
              ),
            ),

          AnimatedBuilder(
            animation: _pulseAnim,
            builder: (_, __) => Container(
              width: 160 * _pulseAnim.value,
              height: 160 * _pulseAnim.value,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color:
                      _accentColor.withOpacity(0.15 * _pulseAnim.value),
                  width: 1,
                ),
              ),
            ),
          ),

          AnimatedContainer(
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeInOut,
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF0D1117),
              border: Border.all(
                  color: _accentColor.withOpacity(.6), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color:
                      _accentColor.withOpacity(_isConnected ? .25 : .08),
                  blurRadius: _isConnected ? 40 : 15,
                  spreadRadius: _isConnected ? 8 : 2,
                ),
              ],
            ),
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: _isConnecting
                    ? SizedBox(
                        key: const ValueKey('loading'),
                        width: 32,
                        height: 32,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _accentColor,
                        ),
                      )
                    : Icon(
                        key: ValueKey(_status + _userRequestedStop.toString()),
                        _isConnected
                            ? Icons.hub_rounded
                            : Icons.hub_outlined,
                        color: _accentColor,
                        size: 36,
                      ),
              ),
            ),
          ),

          if (_isConnected && _sessions > 0)
            Positioned(
              top: 22,
              right: 22,
              child: AnimatedScale(
                scale: _sessions > 0 ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _accentColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$_sessions',
                    style: const TextStyle(
                      color: Color(0xFF080B10),
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ),
            ),
        ]),
      );

  // ── STATUS LABEL ──────────────────────────────────────────

  Widget _buildStatusLabel() => Column(children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.3),
                end: Offset.zero,
              ).animate(anim),
              child: child,
            ),
          ),
          child: Text(
            key: ValueKey(_statusTitle()),
            _statusTitle(),
            style: const TextStyle(
              color: Color(0xFFEAEEF4),
              fontSize: 26,
              fontWeight: FontWeight.w300,
              letterSpacing: 1.5,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _statusSubtitle(),
          style: const TextStyle(
            color: Color(0xFF4A5568),
            fontSize: 12,
            letterSpacing: 1,
            fontFamily: 'monospace',
          ),
        ),
      ]);

  String _statusTitle() {
    if (_userRequestedStop || !_svcRunning) return 'Offline';
    return switch (_status) {
      'connected' => 'Connected',
      'connecting' => 'Connecting',
      'reconnecting' => 'Reconnecting',
      'error' => 'Error',
      'stopped' => 'Offline',
      _ => 'Offline',
    };
  }

  String _statusSubtitle() {
    if (_userRequestedStop || !_svcRunning) return 'SERVICE INACTIVE';
    return switch (_status) {
      'connected' => 'RELAY ACTIVE  •  TRAFFIC ROUTING',
      'connecting' => 'ESTABLISHING TUNNEL...',
      'reconnecting' => 'RECONNECTING...',
      'error' => 'CONNECTION FAILED',
      _ => 'SERVICE INACTIVE',
    };
  }

  // ── METRICS ───────────────────────────────────────────────

  Widget _buildMetricsRow() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Row(children: [
          Expanded(
            child: _MetricCard(
              label: 'DATA IN',
              value: _formatBytes(_bytesIn),
              icon: Icons.arrow_downward_rounded,
              accent: const Color(0xFF00F5C4),
              active: _isConnected,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _MetricCard(
              label: 'DATA OUT',
              value: _formatBytes(_bytesOut),
              icon: Icons.arrow_upward_rounded,
              accent: const Color(0xFF7B61FF),
              active: _isConnected,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _MetricCard(
              label: 'TOTAL',
              value: _total > 999
                  ? '${(_total / 1000).toStringAsFixed(1)}k'
                  : '$_total',
              icon: Icons.bolt_rounded,
              accent: const Color(0xFFFFB627),
              active: _isConnected,
            ),
          ),
        ]),
      );

  String _formatBytes(int b) {
    if (b < 1024) return '${b}B';
    if (b < 1048576) return '${(b / 1024).toStringAsFixed(1)}K';
    if (b < 1073741824) return '${(b / 1048576).toStringAsFixed(1)}M';
    return '${(b / 1073741824).toStringAsFixed(2)}G';
  }

  // ── ACTION BUTTONS ────────────────────────────────────────

  Widget _buildActionRow() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Row(children: [
          Expanded(
            flex: 3,
            child: _GlowButton(
              label: (_svcRunning && !_userRequestedStop)
                  ? 'Stop Service'
                  : 'Start Service',
              accent: (_svcRunning && !_userRequestedStop)
                  ? const Color(0xFFFF4560)
                  : const Color(0xFF00F5C4),
              onTap: _toggleService,
            ),
          ),
          const SizedBox(width: 12),
          _IconActionButton(
            icon: Icons.refresh_rounded,
            onTap: _reconnect,
            enabled: _svcRunning && !_userRequestedStop,
          ),
          const SizedBox(width: 12),
          _IconActionButton(
            icon: Icons.verified_user_outlined,
            onTap: () => PermissionManager.showPermissionDialog(context),
            enabled: true,
          ),
        ]),
      );
}

// ── Top bar button ────────────────────────────────────────

class _TopBarButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  const _TopBarButton(
      {required this.icon, required this.onTap, required this.tooltip});

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFF0D1117),
              border: Border.all(color: const Color(0xFF1C2333), width: 1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: const Color(0xFF4A5568), size: 16),
          ),
        ),
      );
}

// ═══════════════════════════════════════════════════════════
//  Sub-widgets (بدون تغییر ساختاری)
// ═══════════════════════════════════════════════════════════

class _MetricCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color accent;
  final bool active;
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
    required this.active,
  });

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        padding:
            const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF0D1117),
          border: Border.all(
            color: active
                ? accent.withOpacity(.25)
                : const Color(0xFF1C2333),
            width: 1,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: accent.withOpacity(.08),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ]
              : [],
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon,
                  color: active ? accent : const Color(0xFF2D3748),
                  size: 16),
              const SizedBox(height: 10),
              Text(
                value,
                style: TextStyle(
                  color: active
                      ? const Color(0xFFEAEEF4)
                      : const Color(0xFF2D3748),
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'monospace',
                  letterSpacing: .5,
                ),
              ),
              const SizedBox(height: 4),
              Text(label,
                  style: const TextStyle(
                    color: Color(0xFF4A5568),
                    fontSize: 8,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w600,
                  )),
            ]),
      );
}

class _GlowButton extends StatefulWidget {
  final String label;
  final Color accent;
  final VoidCallback onTap;
  const _GlowButton(
      {required this.label,
      required this.accent,
      required this.onTap});

  @override
  State<_GlowButton> createState() => _GlowButtonState();
}

class _GlowButtonState extends State<_GlowButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) {
          setState(() => _pressed = false);
          widget.onTap();
        },
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 52,
          decoration: BoxDecoration(
            color: _pressed
                ? widget.accent.withOpacity(.2)
                : widget.accent.withOpacity(.1),
            border: Border.all(
                color: widget.accent.withOpacity(.5), width: 1),
            borderRadius: BorderRadius.circular(14),
            boxShadow: _pressed
                ? []
                : [
                    BoxShadow(
                      color: widget.accent.withOpacity(.15),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
          ),
          child: Center(
            child: Text(
              widget.label,
              style: TextStyle(
                color: widget.accent,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
              ),
            ),
          ),
        ),
      );
}

class _IconActionButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool enabled;
  const _IconActionButton(
      {required this.icon,
      required this.onTap,
      required this.enabled});

  @override
  State<_IconActionButton> createState() => _IconActionButtonState();
}

class _IconActionButtonState extends State<_IconActionButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTapDown: (_) {
          if (widget.enabled) setState(() => _pressed = true);
        },
        onTapUp: (_) {
          setState(() => _pressed = false);
          if (widget.enabled) widget.onTap();
        },
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: _pressed
                ? const Color(0xFF1C2333)
                : const Color(0xFF0D1117),
            border:
                Border.all(color: const Color(0xFF1C2333), width: 1),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            widget.icon,
            color: widget.enabled
                ? const Color(0xFF6B7280)
                : const Color(0xFF2D3748),
            size: 20,
          ),
        ),
      );
}

// ── Animated grid background ──────────────────────────────

class _GridBackground extends StatefulWidget {
  const _GridBackground();
  @override
  State<_GridBackground> createState() => _GridBackgroundState();
}

class _GridBackgroundState extends State<_GridBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 8))
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => CustomPaint(
          size: MediaQuery.of(context).size,
          painter: _GridPainter(_ctrl.value),
        ),
      );
}

class _GridPainter extends CustomPainter {
  final double t;
  _GridPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF00F5C4).withOpacity(.04)
      ..strokeWidth = .5
      ..style = PaintingStyle.stroke;

    const step = 40.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    final dotX =
        size.width * (.2 + .6 * (math.sin(t * 2 * math.pi) * .5 + .5));
    final dotY = size.height *
        (.1 + .6 * (math.cos(t * 2 * math.pi * .7) * .5 + .5));
    final radPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF00F5C4).withOpacity(.12),
          const Color(0xFF00F5C4).withOpacity(0),
        ],
      ).createShader(
          Rect.fromCircle(center: Offset(dotX, dotY), radius: 120));
    canvas.drawCircle(Offset(dotX, dotY), 120, radPaint);
  }

  @override
  bool shouldRepaint(_GridPainter old) => old.t != t;
}

class _ArcPainter extends CustomPainter {
  final Color color;
  _ArcPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final rect = Rect.fromCircle(
      center: Offset(size.width / 2, size.height / 2),
      radius: size.width / 2 - 4,
    );

    for (int i = 0; i < 4; i++) {
      canvas.drawArc(rect, i * math.pi / 2, math.pi / 2 - 0.3, false, paint);
    }
  }

  @override
  bool shouldRepaint(_ArcPainter old) => old.color != color;
}