import 'dart:io';

void main() {
  final source = File('windows/runner/resources/app_icon.source.png');
  if (!source.existsSync()) {
    throw StateError('${source.path} not found.');
  }

  final output = File('assets/branding/wallet_android.png');
  output.parent.createSync(recursive: true);
  output.writeAsBytesSync(source.readAsBytesSync(), flush: true);
  stdout.writeln('Android icon source synchronized: ${output.path}');
}
