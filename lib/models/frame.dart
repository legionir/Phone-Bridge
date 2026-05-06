// lib/models/frame.dart
// Binary frame protocol — matches ir-server/src/frame.js exactly.
//
// Layout: [1B type][36B sessionId UTF-8][4B payloadLen big-endian][payload]
//
// Type codes:
//   OPEN     = 0x01   IR → Phone : open TCP to host:port
//   DATA     = 0x02   both ways  : raw bytes
//   ACK_OPEN = 0x03   Phone → IR : stream ready
//   CLOSE    = 0x04   both ways  : tear down

import 'dart:convert';
import 'dart:typed_data';

enum FrameType {
  open(0x01),
  data(0x02),
  ackOpen(0x03),
  close(0x04);

  final int code;
  const FrameType(this.code);

  static FrameType? fromCode(int code) {
    for (final t in FrameType.values) {
      if (t.code == code) return t;
    }
    return null;
  }
}

class Frame {
  static const int sessionIdLen = 36;
  static const int headerLen = 41; // 1 + 36 + 4

  final FrameType type;
  final String sessionId;
  final Uint8List payload;

  const Frame({
    required this.type,
    required this.sessionId,
    required this.payload,
  });

  Uint8List toBytes() {
    final sidBytes = utf8.encode(sessionId);
    if (sidBytes.length > sessionIdLen) {
      throw ArgumentError.value(
        sessionId,
        'sessionId',
        'must be <= 36 UTF-8 bytes',
      );
    }

    final out = Uint8List(headerLen + payload.length);
    out[0] = type.code;

    // Node side uses zero-filled 36B buffer
    out.setRange(1, 1 + sidBytes.length, sidBytes);

    ByteData.sublistView(out, 37, 41).setUint32(
      0,
      payload.length,
      Endian.big,
    );

    out.setRange(headerLen, headerLen + payload.length, payload);
    return out;
  }

  static Frame ackOpen(String sessionId) => Frame(
        type: FrameType.ackOpen,
        sessionId: sessionId,
        payload: Uint8List(0),
      );

  static Frame data(String sessionId, Uint8List bytes) => Frame(
        type: FrameType.data,
        sessionId: sessionId,
        payload: bytes,
      );

  static Frame close(String sessionId) => Frame(
        type: FrameType.close,
        sessionId: sessionId,
        payload: Uint8List(0),
      );
}

typedef FrameCallback = void Function(
  FrameType type,
  String sessionId,
  Uint8List payload,
);

class FrameBuffer {
  final FrameCallback onFrame;
  Uint8List _buf = Uint8List(0);

  FrameBuffer(this.onFrame);

  void push(Uint8List chunk) {
    if (_buf.isEmpty) {
      _buf = chunk;
    } else {
      final merged = Uint8List(_buf.length + chunk.length);
      merged.setRange(0, _buf.length, _buf);
      merged.setRange(_buf.length, merged.length, chunk);
      _buf = merged;
    }

    while (_buf.length >= Frame.headerLen) {
      final type = FrameType.fromCode(_buf[0]);
      if (type == null) {
        _buf = _buf.sublist(1);
        continue;
      }

      final payloadLen =
          ByteData.sublistView(_buf, 37, 41).getUint32(0, Endian.big);
      final totalLen = Frame.headerLen + payloadLen;

      if (_buf.length < totalLen) break;

      final sidRaw = _buf.sublist(1, 37);
      final zeroPos = sidRaw.indexOf(0);
      final sessionId = utf8.decode(
        zeroPos >= 0 ? sidRaw.sublist(0, zeroPos) : sidRaw,
      );

      final payload = Uint8List.fromList(
        _buf.sublist(Frame.headerLen, totalLen),
      );

      _buf = _buf.sublist(totalLen);
      onFrame(type, sessionId, payload);
    }
  }

  void reset() {
    _buf = Uint8List(0);
  }
}
