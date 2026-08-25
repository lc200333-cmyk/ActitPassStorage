import 'dart:typed_data';

import 'package:actit_pass_storage/services/icon_processor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

void main() {
  test('icon processor preserves aspect ratio and transparent padding',
      () async {
    final source = image.Image(width: 200, height: 100, numChannels: 4);
    image.fill(source, color: image.ColorRgba8(20, 80, 160, 255));
    final input = Uint8List.fromList(image.encodePng(source));
    final first = await IconProcessor.normalize(input);
    final second = await IconProcessor.normalize(input);
    expect(second, orderedEquals(first));
    final decoded = image.decodePng(first)!;
    expect(decoded.width, 128);
    expect(decoded.height, 128);
    expect(decoded.getPixel(64, 0).a, 0);
    expect(decoded.getPixel(64, 64).a, 255);
    expect(decoded.getPixel(0, 32).a, 0);
  });
}
