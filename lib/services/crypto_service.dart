// lib/services/crypto_service.dart
// رمزگذاری/رمزگشایی config با AES-256-CBC
// کلید ثابت داخل برنامه — فقط obfuscation است، نه security کامل

import 'dart:convert';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';

/// فرمت پیام رمزگذاری شده:
/// base64( IV[16] + AES-256-CBC(json) )
///
/// JSON فیلدها: serverHost, serverPort, wsPath, isSSL
class CryptoService {
  // کلید 32 بایتی ثابت — در production می‌توان از keystore استفاده کرد
  static final Uint8List _key = Uint8List.fromList([
    0x42, 0x72, 0x69, 0x64, 0x67, 0x65, 0x41, 0x70,
    0x70, 0x4B, 0x65, 0x79, 0x32, 0x30, 0x32, 0x34,
    0x53, 0x65, 0x63, 0x72, 0x65, 0x74, 0x58, 0x59,
    0x5A, 0x21, 0x40, 0x23, 0x24, 0x25, 0x5E, 0x26,
  ]);

  /// رمزگشایی رشته base64(IV+ciphertext) و برگرداندن Map
  static Map<String, dynamic>? decrypt(String encoded) {
    try {
      final raw = base64.decode(encoded.trim());
      if (raw.length < 17) return null;

      final iv = raw.sublist(0, 16);
      final cipher = raw.sublist(16);

      final params = ParametersWithIV(KeyParameter(_key), iv);
      final cbcCipher = CBCBlockCipher(AESEngine());
      final paddedCipher = PaddedBlockCipherImpl(
        PKCS7Padding(),
        cbcCipher,
      );
      paddedCipher.init(false, PaddedBlockCipherParameters(params, null));

      final plain = paddedCipher.process(Uint8List.fromList(cipher));
      final jsonStr = utf8.decode(plain);
      final decoded = jsonDecode(jsonStr);
      if (decoded is Map<String, dynamic>) return decoded;
      return null;
    } catch (_) {
      return null;
    }
  }

  /// رمزگذاری Map و برگرداندن base64(IV+ciphertext)
  static String encrypt(Map<String, dynamic> data) {
    final jsonStr = jsonEncode(data);
    final plain = Uint8List.fromList(utf8.encode(jsonStr));

    // IV تصادفی
    final secureRandom = FortunaRandom();
    final seedSource = _key; // در production از SecureRandom واقعی استفاده کن
    secureRandom.seed(KeyParameter(seedSource));

    final iv = Uint8List(16);
    for (int i = 0; i < 16; i++) {
      iv[i] = secureRandom.nextUint8();
    }

    final params = ParametersWithIV(KeyParameter(_key), iv);
    final cbcCipher = CBCBlockCipher(AESEngine());
    final paddedCipher = PaddedBlockCipherImpl(
      PKCS7Padding(),
      cbcCipher,
    );
    paddedCipher.init(true, PaddedBlockCipherParameters(params, null));

    final encrypted = paddedCipher.process(plain);

    final combined = Uint8List(16 + encrypted.length);
    combined.setRange(0, 16, iv);
    combined.setRange(16, combined.length, encrypted);

    return base64.encode(combined);
  }
}