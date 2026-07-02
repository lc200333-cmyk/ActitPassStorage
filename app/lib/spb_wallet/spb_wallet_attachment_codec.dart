import 'dart:io';
import 'dart:typed_data';

import 'spb_wallet_crypto.dart';

class SpbWalletAttachmentCodec {
  const SpbWalletAttachmentCodec(this.crypto);

  final SpbWalletCrypto crypto;

  SpbAttachmentPayload decode(Object? encrypted) {
    final decrypted = crypto.decryptRawWithOuterPrefix(encrypted);
    if (decrypted.length <= 4) {
      throw const SpbWalletAttachmentException('Вложение SPB Wallet не содержит zlib payload.');
    }
    final expectedLength = ByteData.sublistView(decrypted, 0, 4).getUint32(0, Endian.little);
    try {
      final bytes = Uint8List.fromList(zlib.decode(Uint8List.sublistView(decrypted, 4)));
      if (bytes.length != expectedLength) {
        throw SpbWalletAttachmentException('Размер вложения SPB Wallet не совпал: ожидалось $expectedLength, получено ${bytes.length}.');
      }
      return SpbAttachmentPayload(bytes);
    } catch (error) {
      throw SpbWalletAttachmentException('Не удалось распаковать вложение SPB Wallet: $error');
    }
  }

  Uint8List encode(List<int> bytes) {
    final compressed = Uint8List.fromList(zlib.encode(bytes));
    final payload = Uint8List(compressed.length + 4);
    ByteData.sublistView(payload, 0, 4).setUint32(0, bytes.length, Endian.little);
    payload.setAll(4, compressed);
    return crypto.encryptRawWithOuterPrefix(payload);
  }
}

class SpbAttachmentPayload {
  const SpbAttachmentPayload(this.bytes);

  final Uint8List bytes;
}

class SpbWalletAttachmentException implements Exception {
  const SpbWalletAttachmentException(this.message);

  final String message;

  @override
  String toString() => message;
}
