// lib/screens/log_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/background_service_manager.dart';

class LogScreen extends StatefulWidget {
  const LogScreen({super.key});

  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> {
  final ScrollController _scrollCtrl = ScrollController();
  StreamSubscription? _sub;
  List<Map<String, dynamic>> _entries = [];
  bool _autoScroll = true;
  String _filter = 'ALL';

  static const _filters = ['ALL', 'INFO', 'WARN', 'ERR'];

  @override
  void initState() {
    super.initState();
    _sub = BackgroundServiceManager.logsStream.listen((entries) {
      if (!mounted) return;
      setState(() => _entries = entries);
      if (_autoScroll && _scrollCtrl.hasClients) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollCtrl.hasClients) {
            _scrollCtrl.animateTo(
              _scrollCtrl.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _scrollCtrl.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _filtered {
    if (_filter == 'ALL') return _entries;
    return _entries
        .where((e) => (e['level'] as String).trim() == _filter)
        .toList();
  }

  void _copyAll() {
    final text = _filtered
        .map((e) => '[${e['time']}] ${e['level']} ${e['msg']}')
        .join('\n');
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Logs copied to clipboard',
            style: TextStyle(fontFamily: 'monospace')),
        duration: Duration(seconds: 2),
        backgroundColor: Color(0xFF1B2D25),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;

    return Scaffold(
      backgroundColor: const Color(0xFF080B10),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1117),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded,
              color: Color(0xFF6B7280), size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'LOGS',
              style: TextStyle(
                color: Color(0xFFEAEEF4),
                fontFamily: 'monospace',
                fontSize: 14,
                letterSpacing: 4,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF00F5C4).withOpacity(.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${filtered.length}',
                style: const TextStyle(
                  color: Color(0xFF00F5C4),
                  fontFamily: 'monospace',
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_outlined,
                color: Color(0xFF6B7280), size: 18),
            onPressed: filtered.isEmpty ? null : _copyAll,
            tooltip: 'Copy logs',
          ),
          IconButton(
            icon: Icon(
              _autoScroll
                  ? Icons.vertical_align_bottom_rounded
                  : Icons.pause_rounded,
              color: _autoScroll
                  ? const Color(0xFF00F5C4)
                  : const Color(0xFF6B7280),
              size: 18,
            ),
            onPressed: () =>
                setState(() => _autoScroll = !_autoScroll),
            tooltip: _autoScroll ? 'Auto-scroll ON' : 'Auto-scroll OFF',
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter bar
          Container(
            color: const Color(0xFF0D1117),
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                ..._filters.map((f) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _FilterChip(
                        label: f,
                        selected: _filter == f,
                        onTap: () => setState(() => _filter = f),
                      ),
                    )),
                const Spacer(),
                // Server info protection notice
                Row(children: [
                  const Icon(Icons.shield_outlined,
                      color: Color(0xFF2D3748), size: 12),
                  const SizedBox(width: 4),
                  const Text(
                    'Server info hidden',
                    style: TextStyle(
                      color: Color(0xFF2D3748),
                      fontSize: 9,
                      fontFamily: 'monospace',
                      letterSpacing: 1,
                    ),
                  ),
                ]),
              ],
            ),
          ),

          const Divider(color: Color(0xFF1C2333), height: 1),

          // Log entries
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.terminal_rounded,
                            color: Color(0xFF1C2333), size: 48),
                        const SizedBox(height: 12),
                        Text(
                          _filter == 'ALL'
                              ? 'No logs yet'
                              : 'No $_filter logs',
                          style: const TextStyle(
                            color: Color(0xFF2D3748),
                            fontFamily: 'monospace',
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.all(12),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) => _LogRow(entry: filtered[i]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip(
      {required this.label,
      required this.selected,
      required this.onTap});

  Color get _color => switch (label) {
        'WARN' => const Color(0xFFFFB627),
        'ERR' => const Color(0xFFFF4560),
        'DBG' => const Color(0xFF7B61FF),
        _ => const Color(0xFF00F5C4),
      };

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: selected ? _color.withOpacity(.15) : Colors.transparent,
            border: Border.all(
              color: selected ? _color.withOpacity(.5) : const Color(0xFF1C2333),
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? _color : const Color(0xFF4A5568),
              fontFamily: 'monospace',
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
        ),
      );
}

class _LogRow extends StatelessWidget {
  final Map<String, dynamic> entry;
  const _LogRow({required this.entry});

  Color get _levelColor => switch ((entry['level'] as String).trim()) {
        'WARN' => const Color(0xFFFFB627),
        'ERR ' => const Color(0xFFFF4560),
        'DBG ' => const Color(0xFF7B61FF),
        _ => const Color(0xFF4A5568),
      };

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Time
            Text(
              entry['time'] as String? ?? '',
              style: const TextStyle(
                color: Color(0xFF2D3748),
                fontFamily: 'monospace',
                fontSize: 10,
              ),
            ),
            const SizedBox(width: 8),
            // Level
            Container(
              width: 32,
              child: Text(
                (entry['level'] as String? ?? '').trim(),
                style: TextStyle(
                  color: _levelColor,
                  fontFamily: 'monospace',
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Message
            Expanded(
              child: Text(
                entry['msg'] as String? ?? '',
                style: const TextStyle(
                  color: Color(0xFFEAEEF4),
                  fontFamily: 'monospace',
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      );
}