import 'dart:typed_data';

import 'package:pointycastle/export.dart' as pc;

class SpbWalletCrypto {
  SpbWalletCrypto(String password) : _key = _deriveKey(password);

  static const int _blockSize = 16;
  final Uint8List _key;

  Uint8List encryptText(String value) {
    final plain = _utf16LeEncode(value);
    final padding = _paddingLength(plain.length);
    final padded = Uint8List(plain.length + padding)..setAll(0, plain);
    final encrypted = _crypt(padded, encrypt: true);
    return _prefixPadding(encrypted, padding);
  }

  String decryptText(Object? blob) {
    final bytes = _blobBytes(blob);
    if (bytes == null || bytes.isEmpty) return '';
    if (bytes.length < 4) throw const SpbWalletCryptoException('Некорректный зашифрованный текст SPB Wallet.');
    final padding = ByteData.sublistView(bytes, 0, 4).getInt32(0, Endian.little);
    final decrypted = _crypt(Uint8List.sublistView(bytes, 4), encrypt: false);
    if (padding < 0 || padding > decrypted.length) {
      throw const SpbWalletCryptoException('Пароль не подходит или база повреждена.');
    }
    final contentLength = decrypted.length - padding;
    if (contentLength < 0 || contentLength.isOdd) {
      throw const SpbWalletCryptoException('Пароль не подходит или база повреждена.');
    }
    return _utf16LeDecode(Uint8List.sublistView(decrypted, 0, contentLength));
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
      final value = decryptText(blob);
      if (value.isEmpty) return true;
      var readable = 0;
      for (final rune in value.runes) {
        if (rune == 0xfffd) return false;
        if (rune == 9 || rune == 10 || rune == 13 || rune >= 32) readable++;
      }
      return readable / value.runes.length > 0.85;
    } catch (_) {
      return false;
    }
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
    final passwordBytes = _utf16LeEncode('$password\u0000');
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

  static Uint8List _utf16LeEncode(String value) {
    final units = value.codeUnits;
    final bytes = Uint8List(units.length * 2);
    final data = ByteData.sublistView(bytes);
    for (var i = 0; i < units.length; i++) {
      data.setUint16(i * 2, units[i], Endian.little);
    }
    return bytes;
  }

  static String _utf16LeDecode(Uint8List bytes) {
    if (bytes.length.isOdd) {
      throw const SpbWalletCryptoException('Некорректная UTF-16LE строка SPB Wallet.');
    }
    final data = ByteData.sublistView(bytes);
    final units = List<int>.generate(bytes.length ~/ 2, (index) {
      return data.getUint16(index * 2, Endian.little);
    });
    return String.fromCharCodes(units);
  }

  static Uint8List? _blobBytes(Object? value) {
    if (value == null) return null;
    if (value is Uint8List) return value;
    if (value is List<int>) return Uint8List.fromList(value);
    throw const SpbWalletCryptoException('SQLite BLOB SPB Wallet имеет неожиданный тип.');
  }
}

class SpbWalletCryptoException implements Exception {
  const SpbWalletCryptoException(this.message);

  final String message;

  @override
  String toString() => message;
}
