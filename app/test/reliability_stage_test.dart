import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:sqlite3/sqlite3.dart';
import 'package:wallet_aps/services/vault_operation_coordinator.dart';
import 'package:wallet_aps/services/vault_persistence.dart';
import 'package:wallet_aps/services/wallet_rekey_service.dart';
import 'package:wallet_aps/spb_wallet/spb_wallet_attachment_codec.dart';
import 'package:wallet_aps/spb_wallet/spb_wallet_crypto.dart';
import 'package:wallet_aps/spb_wallet/spb_wallet_database.dart';
import 'package:wallet_aps/spb_wallet/wallet_image_codec.dart';

Uint8List _png(int red, int green, int blue) {
  final value = image.Image(width: 2, height: 2);
  image.fill(value, color: image.ColorRgb8(red, green, blue));
  return Uint8List.fromList(image.encodePng(value));
}

void main() {
  test('coordinator does not acknowledge a mutation arriving during save',
      () async {
    final coordinator = VaultOperationCoordinator();
    coordinator.markDirty();
    final started = Completer<void>();
    final finish = Completer<void>();

    final firstSave = coordinator.save((revision) async {
      expect(revision, 1);
      started.complete();
      await finish.future;
    });
    await started.future;
    coordinator.markDirty();
    finish.complete();

    expect(await firstSave, isTrue);
    expect(coordinator.publishedRevision, 1);
    expect(coordinator.dirtyRevision, 2);
    expect(coordinator.isDirty, isTrue);
    expect(await coordinator.save((revision) async => expect(revision, 2)),
        isTrue);
    expect(coordinator.isDirty, isFalse);
  });

  test('coordinator keeps failed revision dirty and allows retry', () async {
    final coordinator = VaultOperationCoordinator()..markDirty();
    expect(
      await coordinator.save((_) => throw StateError('injected failure')),
      isFalse,
    );
    expect(coordinator.isDirty, isTrue);
    expect(coordinator.lastError, isA<StateError>());
    expect(await coordinator.save((_) async {}), isTrue);
    expect(coordinator.isDirty, isFalse);
  });

  test('coordinator does not lock or close after a failed publication',
      () async {
    final coordinator = VaultOperationCoordinator()..markDirty();
    expect(
      await coordinator.lock(
        publish: (_) => throw StateError('injected lock failure'),
      ),
      isFalse,
    );
    expect(coordinator.state, VaultOperationState.failed);
    expect(coordinator.isDirty, isTrue);
    expect(await coordinator.close(publish: (_) async {}), isTrue);
    expect(coordinator.state, VaultOperationState.closed);
    expect(coordinator.isDirty, isFalse);
  });

  test('verified snapshot publishes without changing the source database',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('wallet_aps_snapshot_test_');
    addTearDown(() => directory.deleteSync(recursive: true));
    final sourcePath = '${directory.path}${Platform.pathSeparator}source.swl';
    final targetPath =
        '${directory.path}${Platform.pathSeparator}published.swl';
    final wallet = SpbWalletDatabase.create(sourcePath, '2468');
    wallet.saveTemplate(
      const SpbWalletTemplateDraft(
        id: '1111111111111111',
        name: 'Шаблон',
        fields: [],
      ),
    );
    wallet.saveCard(
      const SpbWalletCardDraft(
        id: '2222222222222222',
        title: 'Карточка',
        description: '',
        categoryPath: '',
        templateId: '1111111111111111',
        fieldValues: {},
      ),
    );
    final sourceHash = await sha256File(File(sourcePath));
    final snapshot = await wallet.createVerifiedSnapshot(
      revision: 7,
      stagingDirectory: directory.path,
    );
    expect(snapshot.isValid, isTrue);
    expect(snapshot.revision, 7);
    await LocalFileVaultPublisher(targetPath).publish(snapshot);
    await snapshot.dispose();
    expect(await sha256File(File(sourcePath)), sourceHash);
    final published = SpbWalletDatabase.open(targetPath, '2468');
    expect(published.loadSnapshot().cards.single.title, 'Карточка');
    published.close(flush: false);
    wallet.close(flush: false);
  });

  test('invalid snapshot never replaces the previously published file',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('wallet_aps_publish_failure_');
    addTearDown(() => directory.deleteSync(recursive: true));
    final source = File('${directory.path}${Platform.pathSeparator}new.swl')
      ..writeAsBytesSync([1, 2, 3, 4]);
    final destination =
        File('${directory.path}${Platform.pathSeparator}current.swl')
          ..writeAsBytesSync([9, 8, 7]);
    final before = destination.readAsBytesSync();
    final invalid = VaultSnapshot(
      path: source.path,
      revision: 1,
      length: source.lengthSync(),
      sha256: 'not-the-real-hash',
      quickCheck: 'ok',
    );
    await expectLater(
      LocalFileVaultPublisher(destination.path).publish(invalid),
      throwsA(isA<VaultPersistenceException>()),
    );
    expect(destination.readAsBytesSync(), before);
  });

  test('desktop publisher refuses to overwrite an externally changed file',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('wallet_aps_conflict_test_');
    addTearDown(() => directory.deleteSync(recursive: true));
    final source = File('${directory.path}${Platform.pathSeparator}new.swl')
      ..writeAsBytesSync([1, 2, 3, 4]);
    final destination =
        File('${directory.path}${Platform.pathSeparator}current.swl')
          ..writeAsBytesSync([9, 8, 7]);
    final expectedLength = destination.lengthSync();
    final expectedHash = await sha256File(destination);
    destination.writeAsBytesSync([6, 6, 6]);
    final snapshot = VaultSnapshot(
      path: source.path,
      revision: 1,
      length: source.lengthSync(),
      sha256: await sha256File(source),
      quickCheck: 'ok',
    );
    await expectLater(
      LocalFileVaultPublisher(
        destination.path,
        expectedExistingLength: expectedLength,
        expectedExistingSha256: expectedHash,
      ).publish(snapshot),
      throwsA(isA<VaultPersistenceException>()),
    );
    expect(destination.readAsBytesSync(), [6, 6, 6]);
  });

  test('desktop recovery manifest restores the previous confirmed file',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('wallet_aps_recovery_test_');
    addTearDown(() => directory.deleteSync(recursive: true));
    final destination =
        File('${directory.path}${Platform.pathSeparator}wallet.swl')
          ..writeAsBytesSync([9, 9, 9]);
    final backup = File('${destination.path}.walletaps.backup')
      ..writeAsBytesSync([1, 2, 3]);
    final manifest = File('${destination.path}.walletaps.recovery.json');
    await manifest.writeAsString(jsonEncode({
      'destinationPath': destination.path,
      'stagedPath': '${destination.path}.walletaps.tmp',
      'backupPath': backup.path,
      'previousLength': backup.lengthSync(),
      'previousSha256': await sha256File(backup),
      'expectedLength': destination.lengthSync(),
      'expectedSha256': await sha256File(destination),
    }));
    final recovery =
        await LocalFileVaultPublisher.pendingRecovery(destination.path);
    expect(recovery, isNotNull);
    await recovery!.restorePrevious();
    expect(destination.readAsBytesSync(), [1, 2, 3]);
    expect(manifest.existsSync(), isFalse);
    expect(backup.existsSync(), isFalse);
  });

  test('desktop recovery preserves an untouched destination before rename',
      () async {
    final directory = await Directory.systemTemp
        .createTemp('wallet_aps_pre_rename_recovery_test_');
    addTearDown(() => directory.deleteSync(recursive: true));
    final destination =
        File('${directory.path}${Platform.pathSeparator}wallet.swl')
          ..writeAsBytesSync([4, 5, 6]);
    final staged = File('${destination.path}.walletaps.tmp')
      ..writeAsBytesSync([7, 8, 9]);
    final manifest = File('${destination.path}.walletaps.recovery.json');
    await manifest.writeAsString(jsonEncode({
      'destinationPath': destination.path,
      'stagedPath': staged.path,
      'backupPath': '${destination.path}.walletaps.backup',
      'previousLength': destination.lengthSync(),
      'previousSha256': await sha256File(destination),
      'expectedLength': staged.lengthSync(),
      'expectedSha256': await sha256File(staged),
    }));
    final recovery =
        await LocalFileVaultPublisher.pendingRecovery(destination.path);
    expect(recovery!.canRestorePrevious, isTrue);
    await recovery.restorePrevious();
    expect(destination.readAsBytesSync(), [4, 5, 6]);
    expect(staged.existsSync(), isFalse);
    expect(manifest.existsSync(), isFalse);
  });

  test('WebDAV publisher uploads a temporary file and conditionally moves it',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('wallet_aps_webdav_test_');
    addTearDown(() => directory.deleteSync(recursive: true));
    final source = File('${directory.path}${Platform.pathSeparator}source.swl')
      ..writeAsBytesSync([1, 3, 3, 7]);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    List<int>? temporaryBytes;
    List<int>? publishedBytes;
    String? moveCondition;
    server.listen((request) async {
      if (request.method == 'PUT') {
        temporaryBytes = await request.fold<List<int>>(
          <int>[],
          (all, chunk) => all..addAll(chunk),
        );
        request.response.statusCode = HttpStatus.created;
      } else if (request.method == 'MOVE') {
        moveCondition = request.headers.value(HttpHeaders.ifMatchHeader);
        publishedBytes = temporaryBytes;
        request.response
          ..statusCode = HttpStatus.created
          ..headers.set(HttpHeaders.etagHeader, '"new-etag"');
      } else if (request.method == 'HEAD') {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.set(HttpHeaders.etagHeader, '"new-etag"');
      } else {
        request.response.statusCode = HttpStatus.methodNotAllowed;
      }
      await request.response.close();
    });
    final destination = Uri.parse(
      'http://${server.address.address}:${server.port}/wallet.swl',
    );
    final snapshot = VaultSnapshot(
      path: source.path,
      revision: 2,
      length: source.lengthSync(),
      sha256: await sha256File(source),
      quickCheck: 'ok',
    );
    final result = await WebDavVaultPublisher(
      destination: destination,
      username: '',
      password: '',
      expectedEtag: '"old-etag"',
    ).publish(snapshot);
    expect(publishedBytes, source.readAsBytesSync());
    expect(moveCondition, '"old-etag"');
    expect(result.etag, '"new-etag"');
  });

  test('aggregate transaction rolls back card, template and attachment', () {
    final directory =
        Directory.systemTemp.createTempSync('wallet_aps_transaction_test_');
    addTearDown(() => directory.deleteSync(recursive: true));
    final wallet = SpbWalletDatabase.create(
      '${directory.path}${Platform.pathSeparator}rollback.swl',
      '2468',
    );
    addTearDown(() => wallet.close(flush: false));

    expect(
      () => wallet.runTransaction<void>(() {
        wallet.saveTemplate(
          const SpbWalletTemplateDraft(
            id: '1111111111111111',
            name: 'Rollback',
            fields: [],
          ),
        );
        wallet.saveCardWithAttachments(
          const SpbWalletCardDraft(
            id: '2222222222222222',
            title: 'Rollback',
            description: '',
            categoryPath: '',
            templateId: '1111111111111111',
            fieldValues: {},
          ),
          attachments: const [
            SpbWalletAttachmentDraft(fileName: 'a.txt', bytes: [1, 2, 3]),
          ],
        );
        throw StateError('injected failure');
      }),
      throwsStateError,
    );
    final snapshot = wallet.loadSnapshot();
    expect(snapshot.templates, isEmpty);
    expect(snapshot.cards, isEmpty);
  });

  test(
      'raw and encrypted images survive rekey and shared IDs use copy-on-write',
      () {
    final directory =
        Directory.systemTemp.createTempSync('wallet_aps_image_codec_test_');
    addTearDown(() => directory.deleteSync(recursive: true));
    final path = '${directory.path}${Platform.pathSeparator}images.swl';
    final firstPng = _png(20, 100, 200);
    final secondPng = _png(200, 50, 80);
    var wallet = SpbWalletDatabase.create(path, 'old-password');
    wallet.saveTemplate(
      const SpbWalletTemplateDraft(
        id: '1111111111111111',
        name: 'Images',
        fields: [],
      ),
    );
    wallet.saveCard(
      SpbWalletCardDraft(
        id: '2222222222222222',
        title: 'First',
        description: '',
        categoryPath: '',
        templateId: '1111111111111111',
        fieldValues: const {},
        backgroundImageBase64: base64Encode(firstPng),
      ),
    );
    wallet.saveCard(
      const SpbWalletCardDraft(
        id: '3333333333333333',
        title: 'Second',
        description: '',
        categoryPath: '',
        templateId: '1111111111111111',
        fieldValues: {},
      ),
    );
    wallet.close();

    final raw = sqlite3.open(path);
    final firstImageId = raw.select(
      'SELECT v.ImageID AS ImageID FROM spbwlt_Card c '
      'JOIN spbwlt_CardView v ON v.ID=c.CardViewID WHERE hex(c.ID)=?',
      ['2222222222222222'],
    ).single['ImageID'];
    final initialPayload = raw.select(
      'SELECT Data FROM spbwlt_Image WHERE ID=?',
      [firstImageId],
    ).single['Data'];
    expect(
      WalletImageCodec(
        SpbWalletAttachmentCodec(SpbWalletCrypto('old-password')),
      ).detect(initialPayload),
      WalletImageEncoding.encrypted,
    );
    raw.execute(
      'UPDATE spbwlt_CardView SET ImageID=? WHERE ID=('
      'SELECT CardViewID FROM spbwlt_Card WHERE hex(ID)=?)',
      [firstImageId, '3333333333333333'],
    );
    raw.dispose();

    wallet = SpbWalletDatabase.open(path, 'old-password');
    wallet.saveCard(
      SpbWalletCardDraft(
        id: '3333333333333333',
        title: 'Second',
        description: '',
        categoryPath: '',
        templateId: '1111111111111111',
        fieldValues: const {},
        backgroundImageBase64: base64Encode(secondPng),
      ),
    );
    expect(
      base64Decode(wallet.loadCardBackgroundBase64('2222222222222222')!),
      firstPng,
    );
    expect(
      base64Decode(wallet.loadCardBackgroundBase64('3333333333333333')!),
      secondPng,
    );
    wallet.close();

    final makeFirstRaw = sqlite3.open(path);
    makeFirstRaw.execute(
      'UPDATE spbwlt_Image SET Data=? WHERE ID=?',
      [firstPng, firstImageId],
    );
    makeFirstRaw.dispose();
    WalletRekeyService.rekeyFile(
      path,
      oldPassword: 'old-password',
      newPassword: 'new-password',
    );
    wallet = SpbWalletDatabase.open(path, 'new-password');
    expect(
      base64Decode(wallet.loadCardBackgroundBase64('2222222222222222')!),
      firstPng,
    );
    expect(
      base64Decode(wallet.loadCardBackgroundBase64('3333333333333333')!),
      secondPng,
    );
    wallet.close(flush: false);
  });
}
