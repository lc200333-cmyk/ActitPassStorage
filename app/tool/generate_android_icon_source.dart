import 'dart:io';

import 'package:image/image.dart' as img;

void main() {
  final source = img.decodePng(File('../docs/Wallet.png').readAsBytesSync());
  if (source == null) throw StateError('Unable to decode docs/Wallet.png');

  const canvasSize = 1024;
  const contentSize = 900;
  final resized = img.copyResize(
    source,
    width: source.width >= source.height ? contentSize : null,
    height: source.height > source.width ? contentSize : null,
    interpolation: img.Interpolation.cubic,
  );
  final canvas = img.Image(
    width: canvasSize,
    height: canvasSize,
    numChannels: 4,
  );
  img.compositeImage(
    canvas,
    resized,
    dstX: (canvasSize - resized.width) ~/ 2,
    dstY: (canvasSize - resized.height) ~/ 2,
  );

  final output = File('assets/branding/wallet_android.png');
  output.parent.createSync(recursive: true);
  output.writeAsBytesSync(img.encodePng(canvas, level: 9));
}
