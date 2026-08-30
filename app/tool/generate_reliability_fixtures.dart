import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';
import 'package:wallet_aps/data/legacy_swl/legacy_swl_codec.dart';
import 'package:wallet_aps/services/vault_persistence.dart';
import 'package:wallet_aps/spb_wallet/spb_wallet_crypto.dart';
import 'package:wallet_aps/spb_wallet/spb_wallet_database.dart';

Future<void> main(List<String> arguments) async {
  final options = <String, String>{};
  for (final argument in arguments) {
    if (!argument.startsWith('--') || !argument.contains('=')) continue;
    final separator = argument.indexOf('=');
    options[argument.substring(2, separator)] =
        argument.substring(separator + 1);
  }
  final output = options['output'];
  if (output == null || output.trim().isEmpty) {
    stderr.writeln(
      'Usage: dart run tool/generate_reliability_fixtures.dart '
      '--output=<file.swl> [--cards=1000] [--attachment-mib=1,100,500] '
      '[--corrupt=true] [--legacy=true]',
    );
    exitCode = 64;
    return;
  }
  final cardCount = int.tryParse(options['cards'] ?? '') ?? 1000;
  final attachmentSizes = (options['attachment-mib'] ?? '')
      .split(',')
      .map((value) => int.tryParse(value.trim()))
      .whereType<int>()
      .where((value) => value > 0)
      .toList(growable: false);
  final file = File(output).absolute;
  await file.parent.create(recursive: true);
  if (await file.exists()) {
    throw StateError('Refusing to overwrite ${file.path}');
  }

  const password = 'fixture-password';
  final createWatch = Stopwatch()..start();
  final wallet = SpbWalletDatabase.create(file.path, password);
  const templateId = '1111111111111111';
  const fieldId = '2222222222222222';
  wallet.runTransaction<void>(() {
    wallet.saveTemplate(
      const SpbWalletTemplateDraft(
        id: templateId,
        name: 'Fixture Unicode 中文 😀',
        fields: [
          SpbWalletTemplateFieldRecord(
            id: fieldId,
            name: 'Логин / Login / 用户',
            templateId: templateId,
          ),
        ],
      ),
    );
    for (var index = 0; index < cardCount; index++) {
      final cardId = index.toRadixString(16).padLeft(16, '0').toUpperCase();
      wallet.saveCard(
        SpbWalletCardDraft(
          id: cardId,
          title: 'Карточка $index — 中文 😀',
          description: 'Описание fixture $index',
          categoryPath: 'Unicode / AC/DC / 中文 / 😀',
          templateId: templateId,
          fieldValues: {fieldId: 'fixture-value-$index'},
        ),
      );
    }
    for (final sizeMiB in attachmentSizes) {
      wallet.saveAttachment(
        cardId: '0000000000000000',
        fileName: 'attachment-${sizeMiB}MiB.bin',
        bytes: Uint8List(sizeMiB * 1024 * 1024),
      );
    }
  });
  wallet.close();
  createWatch.stop();

  final hashBeforeRead = await sha256File(file);
  final openWatch = Stopwatch()..start();
  final opened = SpbWalletDatabase.open(file.path, password);
  final snapshot = opened.loadSnapshot();
  openWatch.stop();
  final searchWatch = Stopwatch()..start();
  final matches = snapshot.cards.where((card) {
    return card.title.toLowerCase().contains('中文') ||
        card.description.toLowerCase().contains('fixture') ||
        card.fieldValues.values.any((value) => value.contains('999'));
  }).length;
  searchWatch.stop();
  opened.close(flush: false);
  final hashAfterRead = await sha256File(file);

  final saveWatch = Stopwatch()..start();
  final saveDatabase = SpbWalletDatabase.open(file.path, password);
  final saveSnapshot = await saveDatabase.createVerifiedSnapshot(
    revision: 1,
    stagingDirectory: file.parent.path,
  );
  final published = File('${file.path}.benchmark-published.swl');
  await LocalFileVaultPublisher(published.path).publish(saveSnapshot);
  await saveSnapshot.dispose();
  if (await published.exists()) await published.delete();
  saveDatabase.close(flush: false);
  saveWatch.stop();

  String? corruptPath;
  if (options['corrupt'] == 'true') {
    corruptPath = '${file.path}.corrupt.swl';
    await file.copy(corruptPath);
    _injectCorruption(corruptPath, password);
  }

  Map<String, Object?>? legacyResult;
  if (options['legacy'] == 'true') {
    final source = File('assets/base_wallet/MyWallet.swl');
    if (!source.existsSync()) {
      throw StateError('Legacy base fixture was not found: ${source.path}');
    }
    final legacy = File('${file.path}.legacy.swl');
    if (legacy.existsSync()) {
      throw StateError('Refusing to overwrite ${legacy.path}');
    }
    await source.copy(legacy.path);
    final before = await sha256File(legacy);
    final legacyWallet = SpbWalletDatabase.open(legacy.path, '0000');
    final legacySnapshot = legacyWallet.loadSnapshot();
    legacyWallet.close(flush: false);
    final after = await sha256File(legacy);
    legacyResult = {
      'path': legacy.path,
      'cards': legacySnapshot.cards.length,
      'templates': legacySnapshot.templates.length,
      'hashBeforeRead': before,
      'hashAfterRead': after,
      'readWasByteImmutable': before == after,
    };
  }

  stdout.writeln(
    const JsonEncoder.withIndent('  ').convert({
      'path': file.path,
      'cards': snapshot.cards.length,
      'attachmentsMiB': attachmentSizes,
      'hashBeforeRead': hashBeforeRead,
      'hashAfterRead': hashAfterRead,
      'readWasByteImmutable': hashBeforeRead == hashAfterRead,
      'createMilliseconds': createWatch.elapsedMilliseconds,
      'openMilliseconds': openWatch.elapsedMilliseconds,
      'searchMilliseconds': searchWatch.elapsedMilliseconds,
      'saveMilliseconds': saveWatch.elapsedMilliseconds,
      'searchMatches': matches,
      'residentMemoryBytes': ProcessInfo.currentRss,
      'corruptFixture': corruptPath,
      'legacyFixture': legacyResult,
    }),
  );
}

void _injectCorruption(String path, String password) {
  final database = sqlite3.open(path);
  final crypto = SpbWalletCrypto(password);
  try {
    final firstBytes = LegacySwlCodec.idBytes('AAAAAAAAAAAAAAAA');
    final secondBytes = LegacySwlCodec.idBytes('BBBBBBBBBBBBBBBB');
    final firstText = String.fromCharCodes(firstBytes);
    database.execute(
      'INSERT INTO spbwlt_Category '
      '(ID, Name, Description, IconID, ParentCategoryID) VALUES (?, ?, ?, ?, ?)',
      [firstText, crypto.encryptText('Cycle A'), null, '', secondBytes],
    );
    database.execute(
      'INSERT INTO spbwlt_Category '
      '(ID, Name, Description, IconID, ParentCategoryID) VALUES (?, ?, ?, ?, ?)',
      [secondBytes, crypto.encryptText('Cycle B'), null, '', firstText],
    );
    database.execute(
      'INSERT INTO spbwlt_CardFieldValue '
      '(ID, CardID, TemplateFieldID, ValueString) VALUES (?, ?, ?, ?)',
      [
        LegacySwlCodec.idBytes('CCCCCCCCCCCCCCCC'),
        LegacySwlCodec.idBytes('DDDDDDDDDDDDDDDD'),
        LegacySwlCodec.idBytes('EEEEEEEEEEEEEEEE'),
        crypto.encryptText('orphan'),
      ],
    );
  } finally {
    database.dispose();
  }
}
