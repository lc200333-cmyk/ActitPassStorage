import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:wallet_aps/spb_wallet/spb_wallet_database.dart';

const _password = 'sql-undo-stage';
const _templateId = '54454D504C303031';
const _fieldId = '4649454C44303031';
const _cardId = '4341524430303031';

SpbWalletDatabase _createPopulatedWallet(String path) {
  final wallet = SpbWalletDatabase.create(path, _password);
  wallet.saveTemplate(
    const SpbWalletTemplateDraft(
      id: _templateId,
      name: 'Template',
      fields: [
        SpbWalletTemplateFieldRecord(
          id: _fieldId,
          name: 'Login',
          templateId: _templateId,
          fieldTypeId: 1,
        ),
      ],
    ),
  );
  wallet.saveCard(
    const SpbWalletCardDraft(
      id: _cardId,
      title: 'Original',
      description: '',
      categoryPath: 'Root / Child',
      templateId: _templateId,
      fieldValues: {_fieldId: 'user'},
    ),
  );
  wallet.saveAttachment(
    cardId: _cardId,
    fileName: 'small.txt',
    bytes: [1, 2, 3],
  );
  return wallet;
}

void main() {
  test('undo snapshots are disk-backed, verified and deleted on dispose',
      () async {
    final directory = await Directory.systemTemp.createTemp(
      'wallet_aps_disk_undo_',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final path = '${directory.path}${Platform.pathSeparator}wallet.swl';
    final wallet = _createPopulatedWallet(path);

    final undo = await wallet.createUndoSnapshot();
    final undoFile = File(undo.filePath);
    expect(undoFile.existsSync(), isTrue);
    expect(undoFile.parent.path, contains('.wallet_aps_undo'));
    expect(undo.byteLength, greaterThan(0));
    expect(undoFile.lengthSync(), undo.byteLength);

    wallet.saveCard(
      const SpbWalletCardDraft(
        id: _cardId,
        title: 'Changed',
        description: '',
        categoryPath: 'Root / Child',
        templateId: _templateId,
        fieldValues: {_fieldId: 'changed'},
      ),
    );
    expect(wallet.loadSnapshot().cards.single.title, 'Changed');
    await wallet.restoreUndoSnapshot(undo);
    expect(wallet.loadSnapshot().cards.single.title, 'Original');

    undo.dispose();
    expect(undo.isDisposed, isTrue);
    expect(undoFile.existsSync(), isFalse);
    wallet.close();
  });

  test('hot direct-ID queries use indexes and transactions run no DDL',
      () async {
    final directory = await Directory.systemTemp.createTemp(
      'wallet_aps_sql_plan_',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final path = '${directory.path}${Platform.pathSeparator}wallet.swl';
    final wallet = _createPopulatedWallet(path);
    wallet.close();

    final before = sqlite3.open(path, mode: OpenMode.readOnly);
    final schemaVersion =
        before.select('PRAGMA schema_version').single.values.first;
    before.dispose();

    final reopened = SpbWalletDatabase.open(path, _password);
    reopened.recordCardHit(_cardId);
    reopened.saveAttachment(
      cardId: _cardId,
      fileName: 'second.txt',
      bytes: [4, 5, 6],
    );
    reopened.close();

    final database = sqlite3.open(path, mode: OpenMode.readOnly);
    try {
      expect(
        database.select('PRAGMA schema_version').single.values.first,
        schemaVersion,
      );
      final cardStorageId =
          database.select('SELECT ID FROM spbwlt_Card LIMIT 1').single['ID'];
      final categoryStorageId = database
          .select('SELECT ParentCategoryID FROM spbwlt_Category '
              'WHERE length(ParentCategoryID)>0 LIMIT 1')
          .single['ParentCategoryID'];

      _expectIndexed(
        database,
        'SELECT * FROM spbwlt_Card WHERE ID=?',
        cardStorageId,
        'sqlite_autoindex_spbwlt_Card',
      );
      _expectIndexed(
        database,
        'SELECT * FROM spbwlt_CardAttachment WHERE CardID=?',
        cardStorageId,
        'idx_Attachment_Card',
      );
      _expectIndexed(
        database,
        'SELECT * FROM spbwlt_CardFieldValue WHERE CardID=?',
        cardStorageId,
        'idx_CardFieldValue',
      );
      _expectIndexed(
        database,
        'SELECT * FROM spbwlt_Category WHERE ParentCategoryID=?',
        categoryStorageId,
        'idx_Category_Parent',
      );

      final indexNames = database
          .select("SELECT name FROM sqlite_master WHERE type='index'")
          .map((row) => row['name'].toString())
          .toSet();
      expect(indexNames, isNot(contains('idx_CardFieldValue_Card')));
      expect(indexNames, isNot(contains('idx_TemplateField_Template')));
      expect(indexNames, contains('idx_CardViewField_TemplateField'));
    } finally {
      database.dispose();
    }
  });
}

void _expectIndexed(
  Database database,
  String sql,
  Object? argument,
  String expectedIndex,
) {
  final details = database
      .select('EXPLAIN QUERY PLAN $sql', [argument])
      .map((row) => row['detail'].toString())
      .join('\n');
  expect(details, contains(expectedIndex));
  expect(details, isNot(contains('SCAN ')));
}
