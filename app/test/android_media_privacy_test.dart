import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_aps/main.dart';

void main() {
  test('Android image attachment export is wrapped in a non-media archive', () {
    final source = Uint8List.fromList(<int>[137, 80, 78, 71, 1, 2, 3, 4]);

    final exported = gallerySafeAttachmentExport(
      'photo.png',
      source,
      isAndroid: true,
    );

    expect(exported.fileName, 'photo.apsattachment.zip');
    final archive = ZipDecoder().decodeBytes(exported.bytes, verify: true);
    expect(archive.files, hasLength(1));
    expect(archive.files.single.name, 'photo.png');
    expect(archive.files.single.content, source);
  });

  test('Android non-image attachment export remains unchanged', () {
    final source = Uint8List.fromList(<int>[1, 2, 3]);

    final exported = gallerySafeAttachmentExport(
      'document.pdf',
      source,
      isAndroid: true,
    );

    expect(exported.fileName, 'document.pdf');
    expect(exported.bytes, same(source));
  });
  test('non-Android attachment export remains unchanged', () {
    final source = Uint8List.fromList(<int>[1, 2, 3]);

    final exported = gallerySafeAttachmentExport(
      'photo.png',
      source,
      isAndroid: false,
    );

    expect(exported.fileName, 'photo.png');
    expect(exported.bytes, same(source));
  });

  test('Android storage configuration exposes no public media directory', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final paths =
        File('android/app/src/main/res/xml/file_paths.xml').readAsStringSync();
    final activity = File(
      'android/app/src/main/kotlin/com/lc200333cmyk/walletaps/MainActivity.kt',
    ).readAsStringSync();
    final appSource = File('lib/main.dart').readAsStringSync();

    for (final permission in <String>[
      'READ_MEDIA_IMAGES',
      'READ_EXTERNAL_STORAGE',
      'WRITE_EXTERNAL_STORAGE',
      'MANAGE_EXTERNAL_STORAGE',
    ]) {
      expect(manifest, isNot(contains(permission)));
    }
    expect(paths, isNot(contains('<external-path')));
    expect(paths, isNot(contains('<external-files-path')));
    expect(activity, contains('File(directory, ".nomedia")'));
    expect(activity, contains('externalCacheDir'));
    expect(activity, contains('getExternalFilesDirs(null)'));
    expect(activity, isNot(contains('MediaStore')));
    expect(activity, isNot(contains('FLAG_SECURE')));
    expect(appSource, contains('.apsblob'));
    expect(appSource, isNot(contains('getExternalStorageDirectory')));
    expect(appSource, isNot(contains('getExternalStorageDirectories')));
  });

  test('Synology-synchronized project and build tree are hidden from Gallery',
      () {
    expect(File('../.nomedia').existsSync(), isTrue);
    expect(File('.nomedia').existsSync(), isTrue);
  });
}
