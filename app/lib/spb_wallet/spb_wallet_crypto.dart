import 'dart:typed_data';

import 'package:pointycastle/export.dart' as pc;

class SpbWalletCrypto {
  SpbWalletCrypto(String password) : _key = _deriveKey(password);

  static const int _blockSize = 16;
  final Uint8List _key;
  Endian _textEndian = Endian.big;

  Uint8List encryptText(String value) {
    final plain = _utf16Encode(value, _textEndian);
    final padding = _paddingLength(plain.length);
    final padded = Uint8List(plain.length + padding)..setAll(0, plain);
    final encrypted = _crypt(padded, encrypt: true);
    return _prefixPadding(encrypted, padding);
  }

  String decryptText(Object? blob) {
    final content = _decryptTextContent(blob);
    if (content.isEmpty) return '';
    return _utf16DecodeBest(content).value;
  }

  Uint8List encryptRawWithOuterPrefix(Uint8List plain) {
    final padding = _paddingLength(plain.length);
    final padded = Uint8List(plain.length + padding)..setAll(0, plain);
    return _prefixPadding(_crypt(padded, encrypt: true), padding);
  }

  Uint8List decryptRawWithOuterPrefix(Object? blob) {
    final bytes = _blobBytes(blob);
    if (bytes == null || bytes.isEmpty) return Uint8List(0);
    if (bytes.length < 4) throw const SpbWalletCryptoException('Некорректное вложение SPB Wallet.');
    final padding = ByteData.sublistView(bytes, 0, 4).getInt32(0, Endian.little);
    final decrypted = _crypt(Uint8List.sublistView(bytes, 4), encrypt: false);
    if (padding < 0 || padding > decrypted.length) {
      throw const SpbWalletCryptoException('Пароль не подходит или вложение повреждено.');
    }
    return Uint8List.sublistView(decrypted, 0, decrypted.length - padding);
  }

  bool looksLikeValidText(Object? blob) {
    try {
      final content = _decryptTextContent(blob);
      if (content.isEmpty) return false;
      final decoded = _utf16DecodeBest(content).value;
      final length = decoded.runes.length;
      if (length == 0) return false;
      final minimumScore = length < 3 ? length * 4 : length * 3;
      return _textScore(decoded) >= minimumScore;
    } catch (_) {
      return false;
    }
  }

  void detectTextEndian(Iterable<Object?> blobs) {
    var littleScore = 0;
    var bigScore = 0;
    var samples = 0;
    for (final blob in blobs) {
      try {
        final content = _decryptTextContent(blob);
        if (content.isEmpty) continue;
        littleScore += _textScore(_utf16Decode(content, Endian.little));
        bigScore += _textScore(_utf16Decode(content, Endian.big));
        samples++;
      } catch (_) {
        // Password validation reports bad samples separately.
      }
    }
    if (samples == 0) return;
    _textEndian = bigScore > littleScore ? Endian.big : Endian.little;
  }

  Uint8List _crypt(Uint8List input, {required bool encrypt}) {
    if (input.length % _blockSize != 0) {
      throw const SpbWalletCryptoException('Размер SPB-блока не кратен AES-блоку.');
    }
    final cipher = pc.ECBBlockCipher(pc.AESEngine())
      ..init(encrypt, pc.KeyParameter(_key));
    final output = Uint8List(input.length);
    for (var offset = 0; offset < input.length; offset += _blockSize) {
      cipher.processBlock(input, offset, output, offset);
    }
    return output;
  }

  static Uint8List _deriveKey(String password) {
    final passwordBytes = _utf16Encode('$password\u0000', Endian.little);
    final hash = pc.SHA1Digest().process(passwordBytes);
    return Uint8List(32)
      ..setRange(0, 20, hash)
      ..setRange(20, 32, hash.sublist(0, 12));
  }

  static int _paddingLength(int length) {
    final remainder = length % _blockSize;
    return remainder == 0 ? 0 : _blockSize - remainder;
  }

  static Uint8List _prefixPadding(Uint8List payload, int padding) {
    final result = Uint8List(payload.length + 4);
    ByteData.sublistView(result, 0, 4).setInt32(0, padding, Endian.little);
    result.setAll(4, payload);
    return result;
  }

  static Uint8List _utf16Encode(String value, Endian endian) {
    final units = value.codeUnits;
    final bytes = Uint8List(units.length * 2);
    final data = ByteData.sublistView(bytes);
    for (var i = 0; i < units.length; i++) {
      data.setUint16(i * 2, units[i], endian);
    }
    return bytes;
  }

  static _DecodedText _utf16DecodeBest(Uint8List bytes) {
    final little = _utf16Decode(bytes, Endian.little);
    final big = _utf16Decode(bytes, Endian.big);
    return _textScore(big) > _textScore(little)
        ? _DecodedText(big, Endian.big)
        : _DecodedText(little, Endian.little);
  }

  static String _utf16Decode(Uint8List bytes, Endian endian) {
    if (bytes.length.isOdd) {
      throw const SpbWalletCryptoException('Некорректная UTF-16 строка SPB Wallet.');
    }
    final data = ByteData.sublistView(bytes);
    final units = List<int>.generate(bytes.length ~/ 2, (index) {
      return data.getUint16(index * 2, endian);
    });
    return String.fromCharCodes(units);
  }

  Uint8List _decryptTextContent(Object? blob) {
    final bytes = _blobBytes(blob);
    if (bytes == null || bytes.isEmpty) return Uint8List(0);
    if (bytes.length < 4) {
      throw const SpbWalletCryptoException(
          'Некорректный зашифрованный текст SPB Wallet.');
    }
    final padding = ByteData.sublistView(bytes, 0, 4).getInt32(0, Endian.little);
    final decrypted = _crypt(Uint8List.sublistView(bytes, 4), encrypt: false);
    if (padding < 0 || padding > decrypted.length) {
      throw const SpbWalletCryptoException(
          'Пароль не подходит или база повреждена.');
    }
    final contentLength = decrypted.length - padding;
    if (contentLength < 0 || contentLength.isOdd) {
      throw const SpbWalletCryptoException(
          'Пароль не подходит или база повреждена.');
    }
    return Uint8List.sublistView(decrypted, 0, contentLength);
  }

  static int _textScore(String value) {
    if (value.isEmpty) return 0;
    var score = 0;
    for (final rune in value.runes) {
      if (rune == 0xfffd) return -100000;
      if (rune == 9 || rune == 10 || rune == 13) {
        score += 2;
      } else if (rune < 32) {
        score -= 50;
      } else if (rune >= 0x0400 && rune <= 0x052f) {
        score += 7;
      } else if (rune >= 0x00c0 && rune <= 0x024f) {
        score += 4;
      } else if ((rune >= 0x0041 && rune <= 0x005a) ||
          (rune >= 0x0061 && rune <= 0x007a) ||
          (rune >= 0x0030 && rune <= 0x0039)) {
        score += 5;
      } else if (rune == 0x20 ||
          rune == 0x2e ||
          rune == 0x2c ||
          rune == 0x3a ||
          rune == 0x3b ||
          rune == 0x2f ||
          rune == 0x5c ||
          rune == 0x2d ||
          rune == 0x5f ||
          rune == 0x40) {
        score += 4;
      } else if (rune >= 0x4e00 && rune <= 0x9fff) {
        score -= 8;
      } else if (rune >= 0x3000) {
        score -= 6;
      } else {
        score -= 1;
      }
    }
    return score;
  }

  static Uint8List? _blobBytes(Object? value) {
    if (value == null) return null;
    if (value is Uint8List) return value;
    if (value is List<int>) return Uint8List.fromList(value);
    throw const SpbWalletCryptoException('SQLite BLOB SPB Wallet имеет неожиданный тип.');
  }
}

class _DecodedText {
  const _DecodedText(this.value, this.endian);

  final String value;
  final Endian endian;
}

class SpbWalletCryptoException implements Exception {
  const SpbWalletCryptoException(this.message);

  final String message;

  @override
  String toString() => message;
}
