// lib/services/socks5_connector.dart
// اتصال TCP از طریق SOCKS5 proxy محلی (v2rayNG)
//
// وقتی forward فعال باشد:
//   relay → SOCKS5(127.0.0.1:forwardPort) → v2rayNG → target
//
// مزیت: DNS resolution توسط v2rayNG انجام می‌شود
// و نیازی به Enable local DNS / Enable fake DNS نیست.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class Socks5Exception implements Exception {
  final String message;
  final int? replyCode;
  Socks5Exception(this.message, {this.replyCode});

  @override
  String toString() => 'SOCKS5: $message';

  static String replyMsg(int code) => switch (code) {
        0x00 => 'Succeeded',
        0x01 => 'General failure',
        0x02 => 'Not allowed',
        0x03 => 'Network unreachable',
        0x04 => 'Host unreachable',
        0x05 => 'Connection refused',
        0x06 => 'TTL expired',
        0x07 => 'Command not supported',
        0x08 => 'Address type not supported',
        _ => 'Unknown (0x${code.toRadixString(16)})',
      };
}

class Socks5Connector {
  /// اتصال به [targetHost]:[targetPort] از طریق SOCKS5 proxy
  /// در 127.0.0.1:[proxyPort]
  static Future<Socket> connect({
    required String targetHost,
    required int targetPort,
    required int proxyPort,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    // 1. TCP connect to local SOCKS5 proxy
    final socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      proxyPort,
      timeout: timeout,
    );

    try {
      socket.setOption(SocketOption.tcpNoDelay, true);
    } catch (_) {}

    try {
      // ── Collect all incoming data via stream ────────────
      final incoming = StreamController<Uint8List>();
      final sub = socket.listen(
        (d) => incoming.add(d is Uint8List ? d : Uint8List.fromList(d)),
        onError: (e) => incoming.addError(e),
        onDone: () => incoming.close(),
      );

      final reader = _StreamReader(incoming.stream);

      // 2. Handshake: No auth
      socket.add(Uint8List.fromList([0x05, 0x01, 0x00]));

      final authReply = await reader.read(2).timeout(timeout);
      if (authReply[0] != 0x05 || authReply[1] != 0x00) {
        throw Socks5Exception(
            'Auth rejected: ver=${authReply[0]} method=${authReply[1]}');
      }

      // 3. CONNECT request
      final req = BytesBuilder();
      req.addByte(0x05); // VER
      req.addByte(0x01); // CMD = CONNECT
      req.addByte(0x00); // RSV

      if (_isIPv4(targetHost)) {
        req.addByte(0x01); // ATYP = IPv4
        req.add(_parseIPv4(targetHost));
      } else if (_isIPv6(targetHost)) {
        req.addByte(0x04); // ATYP = IPv6
        req.add(InternetAddress(targetHost).rawAddress);
      } else {
        // Domain — DNS resolved by proxy
        final domain = utf8.encode(targetHost);
        if (domain.length > 255) throw Socks5Exception('Domain too long');
        req.addByte(0x03); // ATYP = Domain
        req.addByte(domain.length);
        req.add(domain);
      }

      // Port big-endian
      req.addByte((targetPort >> 8) & 0xFF);
      req.addByte(targetPort & 0xFF);

      socket.add(req.toBytes());

      // 4. Read reply
      final replyHead = await reader.read(4).timeout(timeout);
      if (replyHead[0] != 0x05) {
        throw Socks5Exception('Bad reply version: ${replyHead[0]}');
      }
      if (replyHead[1] != 0x00) {
        throw Socks5Exception(
          Socks5Exception.replyMsg(replyHead[1]),
          replyCode: replyHead[1],
        );
      }

      // Skip bound address
      final atyp = replyHead[3];
      switch (atyp) {
        case 0x01:
          await reader.read(4 + 2).timeout(timeout); // IPv4 + port
          break;
        case 0x03:
          final lenB = await reader.read(1).timeout(timeout);
          await reader.read(lenB[0] + 2).timeout(timeout);
          break;
        case 0x04:
          await reader.read(16 + 2).timeout(timeout); // IPv6 + port
          break;
        default:
          throw Socks5Exception('Unknown ATYP: $atyp');
      }

      // 5. Handshake complete — cancel our listener
      //    و socket آماده استفاده است
      await sub.cancel();
      await incoming.close();

      // اگر reader بافر اضافی دارد (بعید ولی ممکن)
      final leftover = reader.takeRemaining();
      if (leftover.isNotEmpty) {
        // This shouldn't happen in practice after SOCKS5 handshake
        // but handle gracefully
      }

      return socket;
    } catch (e) {
      try {
        socket.destroy();
      } catch (_) {}
      rethrow;
    }
  }

  static bool _isIPv4(String h) {
    final p = h.split('.');
    if (p.length != 4) return false;
    return p.every((s) {
      final n = int.tryParse(s);
      return n != null && n >= 0 && n <= 255;
    });
  }

  static bool _isIPv6(String h) {
    try {
      InternetAddress(h, type: InternetAddressType.IPv6);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Uint8List _parseIPv4(String h) =>
      Uint8List.fromList(h.split('.').map((s) => int.parse(s)).toList());
}

/// Buffered stream reader — reads exact number of bytes
class _StreamReader {
  final Stream<Uint8List> _stream;
  late final StreamIterator<Uint8List> _iter;
  final _buffer = BytesBuilder(copy: true);

  _StreamReader(this._stream) {
    _iter = StreamIterator(_stream);
  }

  Future<Uint8List> read(int count) async {
    while (_buffer.length < count) {
      final hasMore = await _iter.moveNext();
      if (!hasMore) {
        throw Socks5Exception('Connection closed during handshake');
      }
      _buffer.add(_iter.current);
    }

    final all = _buffer.toBytes();
    _buffer.clear();

    final result = Uint8List.fromList(all.sublist(0, count));
    if (all.length > count) {
      _buffer.add(all.sublist(count));
    }
    return result;
  }

  Uint8List takeRemaining() {
    final r = _buffer.toBytes();
    _buffer.clear();
    return r;
  }
}