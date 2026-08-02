import 'dart:io';

import 'package:actit_pass_storage/data/legacy_swl/legacy_swl_codec.dart';

void main() {
  final source = File('../docs/Wallet.png');
  if (!source.existsSync()) {
    throw StateError('docs/Wallet.png not found.');
  }
  final target = File('windows/runner/resources/app_icon.ico');
  target.parent.createSync(recursive: true);
  target.writeAsBytesSync(
    LegacySwlCodec.windowsMultiResolutionIco(source.readAsBytesSync()),
    flush: true,
  );
  stdout.writeln('Windows multi-resolution icon generated: ${target.path}');
}
