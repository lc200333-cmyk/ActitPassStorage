import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

void main() {
  test('Wallet.png is wired into every supported platform package', () {
    final sourceBytes = File('../docs/Wallet.png').readAsBytesSync();
    final source = image.decodePng(sourceBytes);
    expect(source, isNotNull);
    expect(source!.width, greaterThanOrEqualTo(256));
    expect(source.height, source.width);
    expect(source.numChannels, 4);

    final ico = File(
      'windows/runner/resources/app_icon.ico',
    ).readAsBytesSync();
    final icoHeader = ByteData.sublistView(ico);
    expect(icoHeader.getUint16(0, Endian.little), 0);
    expect(icoHeader.getUint16(2, Endian.little), 1);
    expect(icoHeader.getUint16(4, Endian.little), 7);

    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    expect(manifest, contains('android:icon="@mipmap/launcher_icon"'));
    expect(manifest, contains('android:roundIcon="@mipmap/launcher_icon"'));
    expect(
      File(
        'android/app/src/main/res/mipmap-anydpi-v26/launcher_icon.xml',
      ).existsSync(),
      isTrue,
    );

    final installer = File(
      '../tools/windows/ActitPassStorage.iss',
    ).readAsStringSync();
    expect(installer, contains('app_icon.ico'));
    final linuxPackage = File(
      '../tools/build_linux_deb.sh',
    ).readAsStringSync();
    expect(linuxPackage, contains('docs/Wallet.png'));
  });
}
