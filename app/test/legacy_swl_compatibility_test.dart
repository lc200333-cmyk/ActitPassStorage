import 'dart:io';
import 'package:actit_pass_storage/main.dart';
import 'package:actit_pass_storage/spb_wallet/spb_wallet_attachment_codec.dart';
import 'package:actit_pass_storage/spb_wallet/spb_wallet_crypto.dart';
import 'package:actit_pass_storage/spb_wallet/spb_wallet_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:sqlite3/sqlite3.dart';

const _password = '0000';

File _fixture(String name) => File('../docs/$name');

Future<(Directory, File)> _copyFixture(String name) async {
  final directory =
      await Directory.systemTemp.createTemp('actitpass_legacy_fixture_');
  final target = File(
    '${directory.path}${Platform.pathSeparator}$name',
  );
  await _fixture(name).copy(target.path);
  return (directory, target);
}

List<Map<String, Object?>> _legacySchema(String path) {
  final database = sqlite3.open(path, mode: OpenMode.readOnly);
  try {
    return database
        .select(
          'SELECT type, name, tbl_name, sql FROM sqlite_master '
          "WHERE type IN ('table','trigger') AND name<>'actitpass_State' "
          "AND name NOT LIKE 'sqlite_%' ORDER BY type, name",
        )
        .map((row) => Map<String, Object?>.from(row))
        .toList();
  } finally {
    database.dispose();
  }
}

Map<String, Object?> _databaseVersion(Database database) =>
    Map<String, Object?>.from(
      database.select('SELECT * FROM spb_DatabaseVersion').single,
    );

int _count(Database database, String sql) =>
    database.select(sql).single['n'] as int;

void main() {
  test('supplied old and current wallets are immutable readable fixtures',
      () async {
    for (final name in ['Мой кошелёк.swl', 'Мой кошелёк1.swl']) {
      expect(_fixture(name).existsSync(), isTrue);
      final (directory, copy) = await _copyFixture(name);
      try {
        final before = copy.readAsBytesSync();
        final wallet = SpbWalletDatabase.open(copy.path, _password);
        final snapshot = wallet.loadSnapshot();
        expect(snapshot.cards, isNotEmpty);
        expect(snapshot.templates, isNotEmpty);
        wallet.close(flush: false);
        expect(copy.readAsBytesSync(), before);

        final raw = sqlite3.open(copy.path, mode: OpenMode.readOnly);
        try {
          expect(
              raw.select('PRAGMA integrity_check').single.values.single, 'ok');
          expect(
            _databaseVersion(raw),
            containsPair('CompatibilityVersion', 18),
          );
          expect(
            _databaseVersion(raw),
            containsPair('VersionString', '1.0.0'),
          );
          expect(
            _count(
              raw,
              "SELECT COUNT(*) AS n FROM sqlite_master WHERE type='trigger'",
            ),
            7,
          );
        } finally {
          raw.dispose();
        }
      } finally {
        await directory.delete(recursive: true);
      }
    }
  });

  test('rekey preserves legacy schema, metadata and unknown tables', () async {
    final (directory, source) = await _copyFixture('Мой кошелёк.swl');
    try {
      final sourceDatabase = sqlite3.open(source.path);
      sourceDatabase.execute(
        'CREATE TABLE compatibility_unknown (Value TEXT NOT NULL)',
      );
      sourceDatabase.execute(
        'INSERT INTO compatibility_unknown (Value) VALUES (?)',
        ['preserved'],
      );
      sourceDatabase.dispose();
      final schemaBefore = _legacySchema(source.path);
      final target = File(
        '${directory.path}${Platform.pathSeparator}rekeyed.swl',
      );

      expect(
        cloneSwlVaultWithPassword({
          'path': target.path,
          'password': 'new-compatible-password',
          'sourcePassword': _password,
          'passwordHint': 'Подсказка',
          'baseBytes': source.readAsBytesSync(),
        }),
        isTrue,
      );

      expect(
        () => SpbWalletDatabase.open(target.path, _password),
        throwsA(isA<SpbWalletOpenException>()),
      );
      final opened =
          SpbWalletDatabase.open(target.path, 'new-compatible-password');
      expect(opened.loadSnapshot().cards, hasLength(15));
      opened.close(flush: false);
      expect(_legacySchema(target.path), schemaBefore);

      final raw = sqlite3.open(target.path, mode: OpenMode.readOnly);
      try {
        expect(
          raw.select('SELECT Value FROM compatibility_unknown').single['Value'],
          'preserved',
        );
        expect(_databaseVersion(raw)['ProductName'], 'SpbWallet');
        expect(_databaseVersion(raw)['CompatibilityVersion'], 18);
        expect(
          _count(
            raw,
            "SELECT COUNT(*) AS n FROM sqlite_master WHERE type='trigger'",
          ),
          7,
        );
      } finally {
        raw.dispose();
      }
      expect(SpbWalletDatabase.readPasswordHint(target.path), 'Подсказка');
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('legacy repair restores current wallet ID relationships', () async {
    final (directory, copy) = await _copyFixture('Мой кошелёк1.swl');
    try {
      final wallet = SpbWalletDatabase.open(copy.path, _password);
      final before = wallet.inspectIntegrity();
      expect(before.orphanCards, 1);
      expect(before.orphanValues, 15);
      expect(before.blobIds, greaterThan(0));
      expect(before.nonIntegerColors, greaterThan(0));
      expect(before.pngIcons, 2);

      final repaired = wallet.repairLegacyCompatibility();
      expect(repaired.orphanCards, 1);
      expect(repaired.orphanValues, 15);
      expect(wallet.inspectIntegrity().hasProblems, isFalse);

      final snapshot = wallet.loadSnapshot();
      final warranty = snapshot.cards
          .singleWhere((card) => card.title == 'Другие: Гарантия');
      final template = snapshot.templates
          .singleWhere((entry) => entry.id == warranty.templateId);
      expect(template.fields, hasLength(15));
      expect(warranty.fieldValues, hasLength(15));
      wallet.close();

      final raw = sqlite3.open(copy.path, mode: OpenMode.readOnly);
      try {
        expect(
          _count(
            raw,
            'SELECT COUNT(*) AS n FROM spbwlt_Card c '
            'LEFT JOIN spbwlt_Template t ON t.ID=c.TemplateID '
            'WHERE t.ID IS NULL',
          ),
          0,
        );
        expect(
          _count(
            raw,
            'SELECT COUNT(*) AS n FROM spbwlt_CardFieldValue v '
            'LEFT JOIN spbwlt_TemplateField f ON f.ID=v.TemplateFieldID '
            'WHERE f.ID IS NULL',
          ),
          0,
        );
      } finally {
        raw.dispose();
      }
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('writer stores text IDs, integer colors and ICO custom icons', () async {
    final (directory, copy) = await _copyFixture('Мой кошелёк.swl');
    try {
      final wallet = SpbWalletDatabase.open(copy.path, _password);
      final templateId = SpbWalletDatabase.makeId();
      final fieldId = SpbWalletDatabase.makeId();
      final cardId = SpbWalletDatabase.makeId();
      final iconId = SpbWalletDatabase.makeId();
      final sourceIcon = image.Image(width: 32, height: 32);
      image.fill(sourceIcon, color: image.ColorRgb8(40, 120, 200));
      wallet.saveTemplate(
        SpbWalletTemplateDraft(
          id: templateId,
          name: 'Совместимый шаблон',
          iconId: iconId,
          iconBytes: image.encodePng(sourceIcon),
          cardColor: 0x8ac5ee,
          fields: [
            SpbWalletTemplateFieldRecord(
              id: fieldId,
              name: 'Поле',
              templateId: templateId,
              fieldTypeId: 1,
            ),
          ],
        ),
      );
      wallet.saveCard(
        SpbWalletCardDraft(
          id: cardId,
          title: 'Совместимая карточка',
          description: '',
          categoryPath: '',
          templateId: templateId,
          fieldValues: {fieldId: 'Значение'},
          cardColor: 0x8ac5ee,
          iconId: iconId,
        ),
      );
      wallet.close();

      final raw = sqlite3.open(copy.path, mode: OpenMode.readOnly);
      try {
        expect(
          raw.select(
            'SELECT typeof(ID) AS type FROM spbwlt_Card WHERE hex(ID)=?',
            [cardId],
          ).single['type'],
          'text',
        );
        expect(
          raw.select(
            'SELECT typeof(CardColor) AS type FROM spbwlt_CardView v '
            'JOIN spbwlt_Card c ON c.CardViewID=v.ID WHERE hex(c.ID)=?',
            [cardId],
          ).single['type'],
          'integer',
        );
        final icon = raw.select(
          'SELECT Data FROM spbwlt_Icon WHERE hex(ID)=?',
          [iconId],
        ).single;
        final codec = SpbWalletAttachmentCodec(SpbWalletCrypto(_password));
        final bytes = codec.decode(icon['Data']).bytes;
        expect(bytes.take(4), [0, 0, 1, 0]);
        expect(
          _count(
            raw,
            'SELECT COUNT(*) AS n FROM spbwlt_Card c '
            'LEFT JOIN spbwlt_Template t ON t.ID=c.TemplateID '
            'WHERE t.ID IS NULL',
          ),
          0,
        );
      } finally {
        raw.dispose();
      }
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('fresh export schema uses original SPB metadata and triggers', () async {
    final directory =
        await Directory.systemTemp.createTemp('actitpass_fresh_legacy_');
    final path = '${directory.path}${Platform.pathSeparator}fresh.swl';
    final wallet = SpbWalletDatabase.create(path, _password);
    wallet.close();
    try {
      final raw = sqlite3.open(path, mode: OpenMode.readOnly);
      try {
        expect(_databaseVersion(raw)['ProductName'], 'SpbWallet');
        expect(_databaseVersion(raw)['VersionString'], '1.0.0');
        expect(_databaseVersion(raw)['CompatibilityVersion'], 18);
        expect(
          _count(
            raw,
            "SELECT COUNT(*) AS n FROM sqlite_master WHERE type='trigger'",
          ),
          7,
        );
        expect(
          raw.select('SELECT length(ID) AS n FROM spbwlt_Wallet').single['n'],
          22,
        );
      } finally {
        raw.dispose();
      }
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
