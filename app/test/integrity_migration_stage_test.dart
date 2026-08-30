import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:wallet_aps/services/vault_persistence.dart';
import 'package:wallet_aps/services/wallet_migration_service.dart';
import 'package:wallet_aps/spb_wallet/spb_wallet_database.dart';

void main() {
  const password = 'stage-two-password';

  test('strict audit is byte-for-byte read-only and reports corruption',
      () async {
    final directory = await Directory.systemTemp.createTemp(
      'wallet_aps_integrity_audit_',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final path = '${directory.path}${Platform.pathSeparator}audit.swl';
    final created = SpbWalletDatabase.create(path, password);
    final crypto = created.crypto;
    created.close();

    final raw = sqlite3.open(path);
    try {
      raw.execute(
        'INSERT INTO spbwlt_Category '
        '(ID, Name, Description, IconID, DefaultTemplateID, '
        'ParentCategoryID, SyncID, CreateSyncID) '
        'VALUES (?, ?, NULL, ?, NULL, ?, -1, -1)',
        ['AAAAAAAA', crypto.encryptText('A'), '', 'BBBBBBBB'],
      );
      raw.execute(
        'INSERT INTO spbwlt_Category '
        '(ID, Name, Description, IconID, DefaultTemplateID, '
        'ParentCategoryID, SyncID, CreateSyncID) '
        'VALUES (?, ?, ?, ?, NULL, ?, -1, -1)',
        [
          'BBBBBBBB',
          crypto.encryptText('B'),
          Uint8List.fromList([1, 2, 3]),
          '',
          'AAAAAAAA',
        ],
      );
      raw.execute(
        'INSERT INTO spbwlt_CardAttachment '
        '(ID, CardID, Name, Data, SyncID, CreateSyncID) '
        'VALUES (?, ?, ?, ?, -1, -1)',
        [
          'ATTACH01',
          'MISSING1',
          crypto.encryptText('broken.bin'),
          Uint8List.fromList([1, 2, 3]),
        ],
      );
      for (final id in <Object>[
        'DUPLID01',
        Uint8List.fromList('DUPLID01'.codeUnits),
      ]) {
        raw.execute(
          'INSERT INTO spbwlt_Category '
          '(ID, Name, Description, IconID, DefaultTemplateID, '
          'ParentCategoryID, SyncID, CreateSyncID) '
          'VALUES (?, ?, NULL, ?, NULL, ?, -1, -1)',
          [id, crypto.encryptText('Duplicate'), '', ''],
        );
      }
      raw.execute(
        'INSERT INTO spbwlt_Image (ID, Name, Data, SyncID, CreateSyncID) '
        'VALUES (?, ?, ?, -1, -1)',
        [
          'IMAGE001',
          crypto.encryptText('broken.png'),
          Uint8List.fromList([1, 2, 3]),
        ],
      );
      raw.execute(
        'INSERT INTO actitpass_State (StateKey, StateValue) VALUES (?, ?)',
        ['card_layout_DEADBEEFDEADBEEF', '{}'],
      );
    } finally {
      raw.dispose();
    }

    final wallet = SpbWalletDatabase.open(path, password);
    final beforeHash = await sha256File(File(path));
    final report = wallet.inspectIntegrity();
    final afterHash = await sha256File(File(path));
    wallet.close(flush: false);

    expect(afterHash, beforeHash);
    expect(report.categoryCycles, 2);
    expect(report.duplicateIds, 1);
    expect(report.orphanAttachments, 1);
    expect(report.invalidEncryptedText, 1);
    expect(report.corruptAttachments, 1);
    expect(report.corruptImages, 1);
    expect(report.danglingStateReferences, 1);
    expect(report.hasProblems, isTrue);
  });

  test('opening and auditing never apply pending migrations', () async {
    final directory = await Directory.systemTemp.createTemp(
      'wallet_aps_no_auto_migration_',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final path = '${directory.path}${Platform.pathSeparator}legacy.swl';
    SpbWalletDatabase.create(path, password).close();
    final raw = sqlite3.open(path);
    raw.execute(
      'DELETE FROM actitpass_State WHERE StateKey=?',
      ['wallet_aps_migration_version'],
    );
    raw.dispose();

    final wallet = SpbWalletDatabase.open(path, password);
    final beforeHash = await sha256File(File(path));
    final report = wallet.inspectIntegrity();
    wallet.close(flush: false);
    expect(report.migrationVersion, 0);
    expect(report.pendingMigrations, WalletMigrationService.currentVersion);
    expect(await sha256File(File(path)), beforeHash);
  });

  test('repair requires an untampered verified backup', () async {
    final directory = await Directory.systemTemp.createTemp(
      'wallet_aps_verified_repair_',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final path = '${directory.path}${Platform.pathSeparator}wallet.swl';
    final wallet = SpbWalletDatabase.create(path, password);
    final backup = await wallet.createRepairBackup(
      '${directory.path}${Platform.pathSeparator}wallet.backup.swl',
    );
    await File(backup.path).writeAsBytes([0], mode: FileMode.append);

    await expectLater(
      wallet.repairLegacyCompatibility(backup: backup),
      throwsA(isA<StateError>()),
    );
    expect(
      wallet.inspectIntegrity().migrationVersion,
      WalletMigrationService.currentVersion,
    );
    wallet.close(flush: false);
  });

  test('migration and repair roll back together after injected failure',
      () async {
    final directory = await Directory.systemTemp.createTemp(
      'wallet_aps_repair_rollback_',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final path = '${directory.path}${Platform.pathSeparator}wallet.swl';
    SpbWalletDatabase.create(path, password).close();
    final raw = sqlite3.open(path);
    raw.execute(
      'DELETE FROM actitpass_State WHERE StateKey=?',
      ['wallet_aps_migration_version'],
    );
    raw.dispose();

    final wallet = SpbWalletDatabase.open(path, password);
    final backup = await wallet.createRepairBackup(
      '${directory.path}${Platform.pathSeparator}wallet.backup.swl',
    );
    await expectLater(
      wallet.repairLegacyCompatibility(
        backup: backup,
        faultInjector: (stage) {
          if (stage == 'migration-2-before-version') {
            throw StateError('injected migration failure');
          }
        },
      ),
      throwsA(isA<StateError>()),
    );
    expect(wallet.inspectIntegrity().migrationVersion, 0);

    final repaired = await wallet.repairLegacyCompatibility(backup: backup);
    expect(repaired.appliedMigrations, hasLength(3));
    expect(
      wallet.inspectIntegrity().migrationVersion,
      WalletMigrationService.currentVersion,
    );
    wallet.close();
  });
}
