import 'dart:typed_data';

import 'spb_wallet_attachment_codec.dart';

enum WalletImageEncoding { raw, encrypted }

class WalletImagePayload {
  const WalletImagePayload(this.bytes, this.encoding);

  final Uint8List bytes;
  final WalletImageEncoding encoding;
}

/// Reads both original SPB raw image BLOBs and Wallet APS encrypted payloads.
class WalletImageCodec {
  const WalletImageCodec(this.encryptedCodec);

  final SpbWalletAttachmentCodec encryptedCodec;

  WalletImagePayload decode(Object? value) {
    final bytes = _blobBytes(value);
    if (_looksLikeImage(bytes)) {
      return WalletImagePayload(bytes, WalletImageEncoding.raw);
    }
    try {
      final decoded = encryptedCodec.decode(bytes).bytes;
      if (!_looksLikeImage(decoded)) {
        throw const WalletImageCodecException(
          'Decrypted image payload has an unknown format.',
        );
      }
      return WalletImagePayload(decoded, WalletImageEncoding.encrypted);
    } catch (error) {
      if (error is WalletImageCodecException) rethrow;
      throw WalletImageCodecException('Invalid wallet image payload: $error');
    }
  }

  WalletImageEncoding detect(Object? value) => decode(value).encoding;

  Uint8List encode(List<int> bytes, WalletImageEncoding encoding) {
    final normalized = Uint8List.fromList(bytes);
    if (!_looksLikeImage(normalized)) {
      throw const WalletImageCodecException('Unsupported image payload.');
    }
    return encoding == WalletImageEncoding.raw
        ? normalized
        : encryptedCodec.encode(normalized);
  }

  static Uint8List _blobBytes(Object? value) {
    if (value is Uint8List) return value;
    if (value is List<int>) return Uint8List.fromList(value);
    throw const WalletImageCodecException('Image is not stored as a BLOB.');
  }

  static bool _looksLikeImage(Uint8List bytes) {
    if (bytes.length < 4) return false;
    final png = bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0d &&
        bytes[5] == 0x0a &&
        bytes[6] == 0x1a &&
        bytes[7] == 0x0a;
    final jpeg = bytes[0] == 0xff && bytes[1] == 0xd8 && bytes[2] == 0xff;
    final gif = bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x38;
    final bmp = bytes[0] == 0x42 && bytes[1] == 0x4d;
    final ico = bytes[0] == 0x00 &&
        bytes[1] == 0x00 &&
        (bytes[2] == 0x01 || bytes[2] == 0x02) &&
        bytes[3] == 0x00;
    final webp = bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50;
    return png || jpeg || gif || bmp || ico || webp;
  }
}

class WalletImageCodecException implements Exception {
  const WalletImageCodecException(this.message);

  final String message;

  @override
  String toString() => message;
}
