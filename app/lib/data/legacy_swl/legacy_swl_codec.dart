import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as image;

abstract final class LegacySwlCodec {
  static final Random _random = Random.secure();
  static const String _idAlphabet =
      '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';

  static Uint8List idBytes(String hex) {
    if (hex.isEmpty) return Uint8List(0);
    if (hex.length.isOdd) {
      throw const FormatException('SPB Wallet ID must contain full bytes.');
    }
    final bytes = Uint8List(hex.length ~/ 2);
    for (var index = 0; index < bytes.length; index++) {
      bytes[index] =
          int.parse(hex.substring(index * 2, index * 2 + 2), radix: 16);
    }
    return bytes;
  }

  static String makeHexId() {
    final text = List.generate(
      8,
      (_) => _idAlphabet[_random.nextInt(_idAlphabet.length)],
    ).join();
    return text.codeUnits
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();
  }

  static String makeWalletId() => List.generate(
        22,
        (_) => _idAlphabet[_random.nextInt(_idAlphabet.length)],
      ).join();

  static int cardColor(int value) => value & 0xffffff;

  static bool isIco(List<int> bytes) =>
      bytes.length >= 4 &&
      bytes[0] == 0 &&
      bytes[1] == 0 &&
      bytes[2] == 1 &&
      bytes[3] == 0;

  static Uint8List embeddedIconIco(List<int> bytes) {
    if (isIco(bytes)) return Uint8List.fromList(bytes);
    final decoded = image.decodeImage(Uint8List.fromList(bytes));
    if (decoded == null) {
      throw const FormatException('The custom icon is not a supported image.');
    }
    final square = image.copyResize(
      decoded,
      width: 64,
      height: 64,
      interpolation: image.Interpolation.cubic,
    );
    return image.encodeIco(square);
  }

  static Uint8List windowsMultiResolutionIco(List<int> bytes) {
    final decoded = image.decodeImage(Uint8List.fromList(bytes));
    if (decoded == null) {
      throw const FormatException('The Windows app icon cannot be decoded.');
    }
    final side = max(decoded.width, decoded.height);
    final square = image.Image(width: side, height: side, numChannels: 4);
    image.compositeImage(
      square,
      decoded,
      dstX: (side - decoded.width) ~/ 2,
      dstY: (side - decoded.height) ~/ 2,
    );
    const sizes = [16, 24, 32, 48, 64, 128, 256];
    final first = image.copyResize(
      square,
      width: sizes.first,
      height: sizes.first,
      interpolation: image.Interpolation.cubic,
    );
    for (final size in sizes.skip(1)) {
      first.addFrame(
        image.copyResize(
          square,
          width: size,
          height: size,
          interpolation: image.Interpolation.cubic,
        ),
      );
    }
    return image.encodeIco(first);
  }
}
