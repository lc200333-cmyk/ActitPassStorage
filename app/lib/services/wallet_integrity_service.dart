// SQL fragments are composed only from private table/column allowlists.
// ignore_for_file: prefer_interpolation_to_compose_strings

import 'dart:convert';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

import '../data/legacy_swl/legacy_swl_codec.dart';
import '../spb_wallet/spb_wallet_attachment_codec.dart';
import '../spb_wallet/spb_wallet_crypto.dart';
import '../spb_wallet/wallet_image_codec.dart';
import 'wallet_migration_service.dart';

class WalletIntegrityReport {
  const WalletIntegrityReport({
    required this.orphanCards,
    required this.orphanValues,
    required this.blobIds,
    required this.nonIntegerColors,
    required this.pngIcons,
    this.sqliteErrors = const [],
    this.orphanCardViews = 0,
    this.brokenCategoryParents = 0,
    this.brokenDefaultTemplates = 0,
    this.orphanAttachments = 0,
    this.orphanTemplateFields = 0,
    this.orphanCardViewFields = 0,
    this.missingCardViewImages = 0,
    this.categoryCycles = 0,
    this.duplicateIds = 0,
    this.duplicateFieldValues = 0,
    this.invalidEncryptedText = 0,
    this.corruptAttachments = 0,
    this.corruptIcons = 0,
    this.corruptImages = 0,
    this.danglingStateReferences = 0,
    this.migrationVersion = 0,
    this.pendingMigrations = 0,
    this.repairedTemplates = 0,
    this.repairedFields = 0,
    this.appliedMigrations = const [],
  });

  final int orphanCards;
  final int orphanValues;
  final int blobIds;
  final int nonIntegerColors;
  final int pngIcons;
  final List<String> sqliteErrors;
  final int orphanCardViews;
  final int brokenCategoryParents;
  final int brokenDefaultTemplates;
  final int orphanAttachments;
  final int orphanTemplateFields;
  final int orphanCardViewFields;
  final int missingCardViewImages;
  final int categoryCycles;
  final int duplicateIds;
  final int duplicateFieldValues;
  final int invalidEncryptedText;
  final int corruptAttachments;
  final int corruptIcons;
  final int corruptImages;
  final int danglingStateReferences;
  final int migrationVersion;
  final int pendingMigrations;
  final int repairedTemplates;
  final int repairedFields;
  final List<String> appliedMigrations;

  int get problemCount =>
      sqliteErrors.length +
      orphanCards +
      orphanValues +
      blobIds +
      nonIntegerColors +
      pngIcons +
      orphanCardViews +
      brokenCategoryParents +
      brokenDefaultTemplates +
      orphanAttachments +
      orphanTemplateFields +
      orphanCardViewFields +
      missingCardViewImages +
      categoryCycles +
      duplicateIds +
      duplicateFieldValues +
      invalidEncryptedText +
      corruptAttachments +
      corruptIcons +
      corruptImages +
      danglingStateReferences;

  bool get hasProblems => problemCount > 0;

  String get diagnosticSummary {
    final values = <String, Object>{
      'sqlite': sqliteErrors.length,
      'orphanCards': orphanCards,
      'orphanValues': orphanValues,
      'blobIds': blobIds,
      'colors': nonIntegerColors,
      'pngIcons': pngIcons,
      'cardViews': orphanCardViews,
      'categoryParents': brokenCategoryParents,
      'defaultTemplates': brokenDefaultTemplates,
      'attachments': orphanAttachments,
      'templateFields': orphanTemplateFields,
      'cardViewFields': orphanCardViewFields,
      'images': missingCardViewImages,
      'cycles': categoryCycles,
      'duplicateIds': duplicateIds,
      'duplicates': duplicateFieldValues,
      'encryptedText': invalidEncryptedText,
      'corruptAttachments': corruptAttachments,
      'corruptIcons': corruptIcons,
      'corruptImages': corruptImages,
      'stateReferences': danglingStateReferences,
    };
    return values.entries
        .where((entry) => entry.value != 0)
        .map((entry) => '${entry.key}=${entry.value}')
        .join(', ');
  }

  String get userMessage {
    if (repairedTemplates > 0 ||
        repairedFields > 0 ||
        appliedMigrations.isNotEmpty) {
      return 'База восстановлена: шаблонов — $repairedTemplates, полей — '
          '$repairedFields, миграций — ${appliedMigrations.length}.';
    }
    if (!hasProblems) {
      final suffix = pendingMigrations == 0
          ? ''
          : ' Доступно миграций: $pendingMigrations; они не применялись.';
      return 'Проверка базы завершена: структура совместима.$suffix';
    }
    return 'Проверка обнаружила проблем: $problemCount. '
        'Исправление возможно только после проверенной резервной копии.';
  }

  WalletIntegrityReport withRepair({
    required int repairedTemplates,
    required int repairedFields,
    required WalletMigrationReport migration,
  }) =>
      WalletIntegrityReport(
        orphanCards: orphanCards,
        orphanValues: orphanValues,
        blobIds: blobIds,
        nonIntegerColors: nonIntegerColors,
        pngIcons: pngIcons,
        sqliteErrors: sqliteErrors,
        orphanCardViews: orphanCardViews,
        brokenCategoryParents: brokenCategoryParents,
        brokenDefaultTemplates: brokenDefaultTemplates,
        orphanAttachments: orphanAttachments,
        orphanTemplateFields: orphanTemplateFields,
        orphanCardViewFields: orphanCardViewFields,
        missingCardViewImages: missingCardViewImages,
        categoryCycles: categoryCycles,
        duplicateIds: duplicateIds,
        duplicateFieldValues: duplicateFieldValues,
        invalidEncryptedText: invalidEncryptedText,
        corruptAttachments: corruptAttachments,
        corruptIcons: corruptIcons,
        corruptImages: corruptImages,
        danglingStateReferences: danglingStateReferences,
        migrationVersion: migration.toVersion,
        pendingMigrations: 0,
        repairedTemplates: repairedTemplates,
        repairedFields: repairedFields,
        appliedMigrations: migration.applied,
      );
}

abstract final class WalletIntegrityService {
  static const Map<String, List<String>> _idColumns = {
    'spbwlt_Wallet': ['ID'],
    'spbwlt_Card': [
      'ID',
      'CardViewID',
      'TemplateID',
      'ParentCategoryID',
      'IconID',
    ],
    'spbwlt_CardAttachment': ['ID', 'CardID'],
    'spbwlt_CardFieldValue': ['ID', 'CardID', 'TemplateFieldID'],
    'spbwlt_CardView': ['ID', 'IconID', 'ImageID'],
    'spbwlt_Category': [
      'ID',
      'IconID',
      'DefaultTemplateID',
      'ParentCategoryID',
    ],
    'spbwlt_Icon': ['ID'],
    'spbwlt_Image': ['ID'],
    'spbwlt_Template': ['ID', 'CardViewID'],
    'spbwlt_TemplateField': ['ID', 'TemplateID'],
    'spbwlt_CardViewField': ['ID', 'CardViewID', 'TemplateFieldID'],
  };

  static const Map<String, List<String>> _encryptedTextColumns = {
    'spbwlt_Category': ['Name', 'Description'],
    'spbwlt_Card': ['Name', 'Description'],
    'spbwlt_CardAttachment': ['Name'],
    'spbwlt_CardFieldValue': ['ValueString'],
    'spbwlt_Template': ['Name', 'Description'],
    'spbwlt_TemplateField': ['Name', 'Description'],
    'spbwlt_Icon': ['Name'],
    'spbwlt_Image': ['Name'],
  };

  /// Performs a strict audit only. The caller is responsible for passing a
  /// read-only database connection; this method never runs DDL/DML.
  static WalletIntegrityReport inspect(
    Database database, {
    required SpbWalletCrypto crypto,
    required SpbWalletAttachmentCodec attachments,
    required WalletImageCodec images,
  }) {
    final sqliteErrors = database
        .select('PRAGMA quick_check')
        .map((row) => row.values.first.toString())
        .where((value) => value.toLowerCase() != 'ok')
        .toList(growable: false);

    final orphanCards = _relationCount(
      database,
      childTable: 'spbwlt_Card',
      childColumn: 'TemplateID',
      parentTable: 'spbwlt_Template',
    );
    final orphanValues = _relationCount(
          database,
          childTable: 'spbwlt_CardFieldValue',
          childColumn: 'TemplateFieldID',
          parentTable: 'spbwlt_TemplateField',
        ) +
        _relationCount(
          database,
          childTable: 'spbwlt_CardFieldValue',
          childColumn: 'CardID',
          parentTable: 'spbwlt_Card',
        );
    final orphanCardViews = _relationCount(
          database,
          childTable: 'spbwlt_Card',
          childColumn: 'CardViewID',
          parentTable: 'spbwlt_CardView',
        ) +
        _relationCount(
          database,
          childTable: 'spbwlt_Template',
          childColumn: 'CardViewID',
          parentTable: 'spbwlt_CardView',
        );
    final brokenCategoryParents = _relationCount(
          database,
          childTable: 'spbwlt_Category',
          childColumn: 'ParentCategoryID',
          parentTable: 'spbwlt_Category',
          allowEmpty: true,
        ) +
        _relationCount(
          database,
          childTable: 'spbwlt_Card',
          childColumn: 'ParentCategoryID',
          parentTable: 'spbwlt_Category',
          allowEmpty: true,
        );
    final brokenDefaultTemplates = _relationCount(
      database,
      childTable: 'spbwlt_Category',
      childColumn: 'DefaultTemplateID',
      parentTable: 'spbwlt_Template',
      allowEmpty: true,
    );
    final orphanAttachments = _relationCount(
      database,
      childTable: 'spbwlt_CardAttachment',
      childColumn: 'CardID',
      parentTable: 'spbwlt_Card',
    );
    final orphanTemplateFields = _relationCount(
      database,
      childTable: 'spbwlt_TemplateField',
      childColumn: 'TemplateID',
      parentTable: 'spbwlt_Template',
    );
    final orphanCardViewFields = _relationCount(
          database,
          childTable: 'spbwlt_CardViewField',
          childColumn: 'CardViewID',
          parentTable: 'spbwlt_CardView',
        ) +
        _relationCount(
          database,
          childTable: 'spbwlt_CardViewField',
          childColumn: 'TemplateFieldID',
          parentTable: 'spbwlt_TemplateField',
        );
    // CardView.ImageID may legally point to an SPB built-in image which is
    // not represented by a row in spbwlt_Image. Without the built-in asset
    // registry such references cannot be classified as dangling safely.
    const missingCardViewImages = 0;

    var blobIds = 0;
    var duplicateIds = 0;
    for (final entry in _idColumns.entries) {
      if (!_hasTable(database, entry.key)) continue;
      final columns = _columns(database, entry.key);
      if (columns.contains('ID')) {
        duplicateIds += _count(
          database,
          'SELECT COUNT(*) AS n FROM ('
          'SELECT hex(ID) FROM "${entry.key}" '
          'GROUP BY hex(ID) HAVING COUNT(*)>1)',
        );
      }
      for (final column in entry.value.where(columns.contains)) {
        for (final row in database.select(
          'SELECT hex("$column") AS id_hex, '
          'typeof("$column") AS storage_type FROM "${entry.key}" '
          'WHERE "$column" IS NOT NULL',
        )) {
          final canonical = _canonicalIdFromHex(row['id_hex'].toString());
          final storage = row['storage_type'].toString();
          final isCanonical =
              canonical is String ? storage == 'text' : storage == 'blob';
          if (!isCanonical) blobIds++;
        }
      }
    }
    final nonIntegerColors = _count(
      database,
      'SELECT COUNT(*) AS n FROM spbwlt_CardView '
      "WHERE typeof(CardColor)<>'integer'",
    );

    var pngIcons = 0;
    var corruptIcons = 0;
    for (final row in database.select(
      'SELECT Data FROM spbwlt_Icon WHERE Data IS NOT NULL',
    )) {
      try {
        final data = attachments.decode(row['Data']).bytes;
        if (!LegacySwlCodec.isIco(data)) pngIcons++;
      } catch (_) {
        corruptIcons++;
      }
    }
    var corruptAttachments = 0;
    for (final row in database.select(
      'SELECT Data FROM spbwlt_CardAttachment WHERE Data IS NOT NULL',
    )) {
      try {
        attachments.decode(row['Data']);
      } catch (_) {
        corruptAttachments++;
      }
    }
    var corruptImages = 0;
    for (final row in database.select(
      'SELECT Data FROM spbwlt_Image WHERE Data IS NOT NULL',
    )) {
      try {
        images.decode(row['Data']);
      } catch (_) {
        corruptImages++;
      }
    }

    var invalidEncryptedText = 0;
    for (final entry in _encryptedTextColumns.entries) {
      if (!_hasTable(database, entry.key)) continue;
      final columns = _columns(database, entry.key);
      for (final column in entry.value.where(columns.contains)) {
        for (final row in database.select(
          'SELECT "$column" AS encrypted_value FROM "${entry.key}" '
          'WHERE "$column" IS NOT NULL',
        )) {
          try {
            crypto.decryptText(row['encrypted_value']);
          } catch (_) {
            invalidEncryptedText++;
          }
        }
      }
    }

    final duplicateFieldValues = _count(
      database,
      'SELECT COUNT(*) AS n FROM ('
      'SELECT hex(CardID), hex(TemplateFieldID) '
      'FROM spbwlt_CardFieldValue '
      'GROUP BY hex(CardID), hex(TemplateFieldID) HAVING COUNT(*)>1)',
    );
    final migrationVersion = WalletMigrationService.readVersion(database);
    return WalletIntegrityReport(
      orphanCards: orphanCards,
      orphanValues: orphanValues,
      blobIds: blobIds,
      nonIntegerColors: nonIntegerColors,
      pngIcons: pngIcons,
      sqliteErrors: sqliteErrors,
      orphanCardViews: orphanCardViews,
      brokenCategoryParents: brokenCategoryParents,
      brokenDefaultTemplates: brokenDefaultTemplates,
      orphanAttachments: orphanAttachments,
      orphanTemplateFields: orphanTemplateFields,
      orphanCardViewFields: orphanCardViewFields,
      missingCardViewImages: missingCardViewImages,
      categoryCycles: _countCategoryCycles(database),
      duplicateIds: duplicateIds,
      duplicateFieldValues: duplicateFieldValues,
      invalidEncryptedText: invalidEncryptedText,
      corruptAttachments: corruptAttachments,
      corruptIcons: corruptIcons,
      corruptImages: corruptImages,
      danglingStateReferences: _countDanglingStateReferences(database),
      migrationVersion: migrationVersion,
      pendingMigrations:
          (WalletMigrationService.currentVersion - migrationVersion)
              .clamp(0, 1 << 20),
    );
  }

  static WalletIntegrityReport repair(
    Database database,
    SpbWalletCrypto crypto,
    SpbWalletAttachmentCodec attachments,
    WalletImageCodec images, {
    void Function(String stage)? faultInjector,
  }) {
    final before = inspect(
      database,
      crypto: crypto,
      attachments: attachments,
      images: images,
    );
    var repairedTemplates = 0;
    var repairedFields = 0;
    late WalletMigrationReport migration;
    database.execute('BEGIN IMMEDIATE');
    try {
      faultInjector?.call('repair-started');
      migration = WalletMigrationService.applyPending(
        database,
        images: images,
        faultInjector: faultInjector,
      );
      _normalizeIds(database);
      faultInjector?.call('ids-normalized');
      final orphanCards = database.select(
        'SELECT c.rowid AS card_rowid, c.TemplateID AS TemplateID, '
        'c.CardViewID AS CardViewID, c.Name AS Name '
        'FROM spbwlt_Card c LEFT JOIN spbwlt_Template t '
        'ON hex(t.ID)=hex(c.TemplateID) WHERE t.ID IS NULL',
      );
      for (final card in orphanCards) {
        final title = crypto.decryptText(card['Name']);
        database.execute(
          'INSERT INTO spbwlt_Template '
          '(ID, Name, Description, CardViewID, SyncID, CreateSyncID) '
          'VALUES (CAST(? AS TEXT), ?, NULL, CAST(? AS TEXT), -1, -1)',
          [
            _bytes(card['TemplateID']),
            crypto.encryptText('Восстановлено: $title'),
            _bytes(card['CardViewID']),
          ],
        );
        repairedTemplates++;
        final fields = database.select(
          'SELECT DISTINCT v.TemplateFieldID AS FieldID '
          'FROM spbwlt_CardFieldValue v '
          'LEFT JOIN spbwlt_TemplateField f '
          'ON hex(f.ID)=hex(v.TemplateFieldID) '
          'WHERE hex(v.CardID)=('
          'SELECT hex(ID) FROM spbwlt_Card WHERE rowid=?) '
          'AND f.ID IS NULL ORDER BY hex(v.TemplateFieldID)',
          [card['card_rowid']],
        );
        for (var index = 0; index < fields.length; index++) {
          final fieldId = _bytes(fields[index]['FieldID']);
          database.execute(
            'INSERT INTO spbwlt_TemplateField '
            '(ID, Name, TemplateID, FieldTypeID, Priority, SyncID, CreateSyncID) '
            'VALUES (CAST(? AS TEXT), ?, CAST(? AS TEXT), 1, ?, -1, -1)',
            [
              fieldId,
              crypto.encryptText('Сохранённое поле ${index + 1}'),
              _bytes(card['TemplateID']),
              index,
            ],
          );
          database.execute(
            'INSERT INTO spbwlt_CardViewField '
            '(ID, CardViewID, TemplateFieldID, PositionX, PositionY, '
            'FontFamily, FontSize, FontColor, TextStyle, TextAlign, '
            'ShowFieldName, SyncID, CreateSyncID) '
            'VALUES (CAST(? AS TEXT), CAST(? AS TEXT), CAST(? AS TEXT), '
            '0, ?, \'Tahoma\', 10, \'0\', 0, 0, 1, -1, -1)',
            [
              LegacySwlCodec.idBytes(LegacySwlCodec.makeHexId()),
              _bytes(card['CardViewID']),
              fieldId,
              index * 24,
            ],
          );
          repairedFields++;
        }
      }
      _normalizeIds(database);
      database.execute(
        'UPDATE spbwlt_CardView '
        'SET CardColor=CAST(CAST(CardColor AS TEXT) AS INTEGER) '
        'WHERE typeof(CardColor)<>\'integer\'',
      );
      for (final row in database.select(
        'SELECT rowid AS source_rowid, Name, Data FROM spbwlt_Icon '
        'WHERE Data IS NOT NULL',
      )) {
        final decoded = attachments.decode(row['Data']).bytes;
        if (LegacySwlCodec.isIco(decoded)) continue;
        final ico = LegacySwlCodec.embeddedIconIco(decoded);
        final oldName = crypto.decryptText(row['Name']);
        final dot = oldName.lastIndexOf('.');
        final name = '${dot < 0 ? oldName : oldName.substring(0, dot)}.ico';
        database.execute(
          'UPDATE spbwlt_Icon SET Name=?, Data=? WHERE rowid=?',
          [
            crypto.encryptText(name),
            attachments.encode(ico),
            row['source_rowid']
          ],
        );
      }
      faultInjector?.call('before-validation');
      final remaining = inspect(
        database,
        crypto: crypto,
        attachments: attachments,
        images: images,
      );
      if (remaining.hasProblems) {
        throw StateError(
          'Repair left ${remaining.problemCount} unresolved integrity '
          'problems: ${remaining.diagnosticSummary}.',
        );
      }
      database.execute('COMMIT');
    } catch (_) {
      database.execute('ROLLBACK');
      rethrow;
    }
    return before.withRepair(
      repairedTemplates: repairedTemplates,
      repairedFields: repairedFields,
      migration: migration,
    );
  }

  static void _normalizeIds(Database database) {
    for (final entry in _idColumns.entries) {
      if (!_hasTable(database, entry.key)) continue;
      final columns = _columns(database, entry.key);
      for (final column in entry.value.where(columns.contains)) {
        for (final row in database.select(
          'SELECT rowid AS source_rowid, '
          'hex("$column") AS id_hex, typeof("$column") AS storage_type '
          'FROM "${entry.key}" WHERE "$column" IS NOT NULL',
        )) {
          final canonical = _canonicalIdFromHex(row['id_hex'].toString());
          final storage = row['storage_type'].toString();
          final isCanonical =
              canonical is String ? storage == 'text' : storage == 'blob';
          if (isCanonical) continue;
          database.execute(
            'UPDATE "${entry.key}" SET "$column"=? WHERE rowid=?',
            [canonical, row['source_rowid']],
          );
        }
      }
    }
  }

  static Object _canonicalIdFromHex(String hex) {
    final bytes = LegacySwlCodec.idBytes(hex);
    try {
      return utf8.decode(bytes, allowMalformed: false);
    } on FormatException {
      return bytes;
    }
  }

  static int _relationCount(
    Database database, {
    required String childTable,
    required String childColumn,
    required String parentTable,
    bool allowEmpty = false,
  }) {
    if (!_hasTable(database, childTable) || !_hasTable(database, parentTable)) {
      return 0;
    }
    final empty = allowEmpty ? 'AND hex(c."$childColumn")<>\'\' ' : '';
    return _count(
      database,
      'SELECT COUNT(*) AS n FROM "$childTable" c '
      'LEFT JOIN "$parentTable" p '
      'ON hex(p.ID)=hex(c."$childColumn") '
      'WHERE c."$childColumn" IS NOT NULL $empty AND p.ID IS NULL',
    );
  }

  static int _countCategoryCycles(Database database) {
    if (!_hasTable(database, 'spbwlt_Category')) return 0;
    final parents = <String, String>{};
    for (final row in database.select(
      'SELECT hex(ID) AS id, hex(ParentCategoryID) AS parent '
      'FROM spbwlt_Category',
    )) {
      parents[row['id'].toString()] = row['parent']?.toString() ?? '';
    }
    final cyclic = <String>{};
    for (final start in parents.keys) {
      final path = <String>[];
      final positions = <String, int>{};
      var current = start;
      while (current.isNotEmpty && parents.containsKey(current)) {
        final prior = positions[current];
        if (prior != null) {
          cyclic.addAll(path.skip(prior));
          break;
        }
        positions[current] = path.length;
        path.add(current);
        current = parents[current] ?? '';
      }
    }
    return cyclic.length;
  }

  static int _countDanglingStateReferences(Database database) {
    if (!_hasTable(database, 'actitpass_State')) return 0;
    var count = 0;
    final cardIds = database
        .select('SELECT hex(ID) AS id FROM spbwlt_Card')
        .map((row) => row['id'].toString())
        .toSet();
    final templateIds = database
        .select('SELECT hex(ID) AS id FROM spbwlt_Template')
        .map((row) => row['id'].toString())
        .toSet();
    final categoryIds = database
        .select('SELECT hex(ID) AS id FROM spbwlt_Category')
        .map((row) => row['id'].toString())
        .toSet();
    for (final row in database.select(
      'SELECT StateKey, StateValue FROM actitpass_State',
    )) {
      final key = row['StateKey'].toString();
      if (key.startsWith('card_layout_') || key.startsWith('card_modified_')) {
        final id = key.substring(key.indexOf('_', 5) + 1);
        if (!cardIds.contains(id.toUpperCase())) count++;
      } else if (key.startsWith('template_category_')) {
        final id = key.substring('template_category_'.length).toUpperCase();
        if (!templateIds.contains(id)) count++;
      } else if (key.startsWith('category_color_')) {
        final id = key.substring('category_color_'.length).toUpperCase();
        if (!categoryIds.contains(id)) count++;
      } else if (key == 'recently_opened_cards') {
        try {
          final values = jsonDecode(row['StateValue'].toString());
          if (values is! List) {
            count++;
          } else {
            count += values
                .whereType<String>()
                .where((id) => !cardIds.contains(id.toUpperCase()))
                .length;
          }
        } catch (_) {
          count++;
        }
      }
    }
    return count;
  }

  static Uint8List _bytes(Object? value) {
    if (value is Uint8List) return value;
    if (value is List<int>) return Uint8List.fromList(value);
    if (value is String) return Uint8List.fromList(value.codeUnits);
    throw StateError('Некорректный legacy ID.');
  }

  static int _count(Database database, String sql) =>
      database.select(sql).first['n'] as int;

  static bool _hasTable(Database database, String name) => database.select(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name=? LIMIT 1",
        [name],
      ).isNotEmpty;

  static Set<String> _columns(Database database, String table) => database
      .select('PRAGMA table_info("$table")')
      .map((row) => row['name'].toString())
      .toSet();
}
