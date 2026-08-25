import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as image;
import 'package:pointycastle/digests/sha256.dart';

class IconProcessor {
  IconProcessor._();

  static final Map<String, Uint8List> _cache = {};
  static const int defaultSize = 128;
  static const double defaultCornerFraction = 0.10;

  static Future<Uint8List> normalize(
    Uint8List source, {
    int size = defaultSize,
    double cornerFraction = defaultCornerFraction,
  }) async {
    final key = _cacheKey(source, size, cornerFraction);
    final cached = _cache[key];
    if (cached != null) return Uint8List.fromList(cached);
    final result = await Isolate.run(
      () => normalizeSync(
        source,
        size: size,
        cornerFraction: cornerFraction,
      ),
    );
    _cache[key] = result;
    return Uint8List.fromList(result);
  }

  static Uint8List normalizeSync(
    Uint8List source, {
    int size = defaultSize,
    double cornerFraction = defaultCornerFraction,
  }) {
    image.Image? decoded;
    try {
      decoded = image.IcoDecoder().decodeImageLargest(source);
    } catch (_) {
      // The selected file can be a regular bitmap rather than ICO.
    }
    decoded ??= image.decodeImage(source);
    if (decoded == null) {
      throw const FormatException('Формат изображения не поддерживается.');
    }
    final scale = min(size / decoded.width, size / decoded.height);
    final width = max(1, (decoded.width * scale).round());
    final height = max(1, (decoded.height * scale).round());
    final resized = image.copyResize(
      decoded,
      width: width,
      height: height,
      interpolation: image.Interpolation.cubic,
    );
    final canvas = image.Image(width: size, height: size, numChannels: 4);
    final offsetX = (size - width) ~/ 2;
    final offsetY = (size - height) ~/ 2;
    final radius = max(1, (min(width, height) * cornerFraction).round());
    final cornerCenter = radius - 0.5;
    final radiusSquared = radius * radius;

    for (final pixel in resized) {
      final x = pixel.x;
      final y = pixel.y;
      final cornerX = x < radius
          ? cornerCenter
          : x >= width - radius
              ? width - radius - 0.5
              : null;
      final cornerY = y < radius
          ? cornerCenter
          : y >= height - radius
              ? height - radius - 0.5
              : null;
      final outsideRoundedCorner = cornerX != null &&
          cornerY != null &&
          ((x - cornerX) * (x - cornerX) + (y - cornerY) * (y - cornerY) >
              radiusSquared);
      canvas.setPixelRgba(
        offsetX + x,
        offsetY + y,
        pixel.r,
        pixel.g,
        pixel.b,
        outsideRoundedCorner ? 0 : pixel.a,
      );
    }
    return Uint8List.fromList(image.encodePng(canvas));
  }

  static String _cacheKey(
    Uint8List source,
    int size,
    double cornerFraction,
  ) {
    final parameters = Uint8List(12)
      ..buffer.asByteData().setUint32(0, size)
      ..buffer.asByteData().setFloat64(4, cornerFraction);
    final input = Uint8List(source.length + parameters.length)
      ..setAll(0, source)
      ..setAll(source.length, parameters);
    final digest = SHA256Digest().process(input);
    return digest.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }
}
