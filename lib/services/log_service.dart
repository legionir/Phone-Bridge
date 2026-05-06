// lib/services/log_service.dart
// سرویس لاگ با حفظ حریم خصوصی — بدون نمایش اطلاعات سرور

import 'dart:collection';
import 'package:flutter/foundation.dart';

enum LogLevel { info, warning, error, debug }

class LogEntry {
  final DateTime time;
  final LogLevel level;
  final String message;

  LogEntry({
    required this.level,
    required this.message,
    DateTime? time,
  }) : time = time ?? DateTime.now();

  String get timeStr {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    final s = time.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  String get levelStr => switch (level) {
        LogLevel.info => 'INFO',
        LogLevel.warning => 'WARN',
        LogLevel.error => 'ERR ',
        LogLevel.debug => 'DBG ',
      };
}

class LogService extends ChangeNotifier {
  static final LogService instance = LogService._();
  LogService._();

  static const int _maxEntries = 200;

  final Queue<LogEntry> _entries = Queue();

  List<LogEntry> get entries => _entries.toList();

  void _add(LogLevel level, String message) {
    // فیلتر کردن اطلاعات حساس — هیچ host/IP/port نمایش داده نمی‌شود
    final safe = _sanitize(message);
    _entries.addLast(LogEntry(level: level, message: safe));
    if (_entries.length > _maxEntries) {
      _entries.removeFirst();
    }
    notifyListeners();
  }

  /// حذف اطلاعات سرور از پیام لاگ
  String _sanitize(String msg) {
    // IP addresses
    msg = msg.replaceAllMapped(
      RegExp(r'\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b'),
      (_) => '[SERVER]',
    );
    // Domain names (ساده‌سازی)
    msg = msg.replaceAllMapped(
      RegExp(r'\b([a-zA-Z0-9-]+\.)+[a-zA-Z]{2,}\b'),
      (m) {
        final s = m.group(0) ?? '';
        // localhost و موارد عمومی را نگه‌دار
        if (s == 'localhost' || s.startsWith('flutter')) return s;
        return '[HOST]';
      },
    );
    // port numbers بعد از :
    msg = msg.replaceAllMapped(
      RegExp(r':\d{2,5}\b'),
      (_) => ':[PORT]',
    );
    // wss/ws URLs
    msg = msg.replaceAllMapped(
      RegExp(r'wss?://[^\s]+'),
      (_) => '[WS_URL]',
    );
    return msg;
  }

  void info(String msg) => _add(LogLevel.info, msg);
  void warn(String msg) => _add(LogLevel.warning, msg);
  void error(String msg) => _add(LogLevel.error, msg);
  void debug(String msg) => _add(LogLevel.debug, msg);

  void clear() {
    _entries.clear();
    notifyListeners();
  }
}