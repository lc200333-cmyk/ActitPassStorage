import 'package:sqlite3/sqlite3.dart';

import '../spb_wallet/wallet_image_codec.dart';

class WalletMigrationReport {
  const WalletMigrationReport({
    required this.fromVersion,
    required this.toVersion,
    required this.applied,
  });

  final int fromVersion;
  final int toVersion;
  final List<String> applied;

  bool get changed => applied.isNotEmpty;
}

/// Wallet APS metadata migrations.
///
/// Opening a wallet never invokes this registry. Pending migrations are only
/// applied as part of the explicit, backed-up compatibility repair flow.
abstract final class WalletMigrationService {
  static const int currentVersion = 3;
  static const String _versionKey = 'wallet_aps_migration_version';

  static int readVersion(Database database) {
    if (!_hasStateTable(database)) return 0;
    final rows = database.select(
      'SELECT StateValue FROM actitpass_State WHERE StateKey=? LIMIT 1',
      [_versionKey],
    );
    if (rows.isEmpty) return 0;
    return int.tryParse(rows.first['StateValue'].toString()) ?? 0;
  }

  static void initializeCurrent(Database database) {
    _ensureStateTable(database);
    _createPerformanceIndexes(database);
    _writeVersion(database, currentVersion);
  }

  static WalletMigrationReport applyPending(
    Database database, {
    required WalletImageCodec images,
    void Function(String stage)? faultInjector,
  }) {
    final fromVersion = readVersion(database);
    if (fromVersion > currentVersion) {
      throw StateError(
        'Wallet metadata version $fromVersion is newer than supported '
        'version $currentVersion.',
      );
    }
    final applied = <String>[];
    var version = fromVersion;
    if (version < 1) {
      _ensureStateTable(database);
      faultInjector?.call('migration-1-before-version');
      _writeVersion(database, 1);
      applied.add('1:create-wallet-aps-state');
      version = 1;
    }
    if (version < 2) {
      _recordImagePolicy(database, images);
      faultInjector?.call('migration-2-before-version');
      _writeVersion(database, 2);
      applied.add('2:record-image-encoding-policy');
      version = 2;
    }
    if (version < 3) {
      _createPerformanceIndexes(database);
      faultInjector?.call('migration-3-before-version');
      _writeVersion(database, 3);
      applied.add('3:canonical-id-performance-indexes');
      version = 3;
    }
    return WalletMigrationReport(
      fromVersion: fromVersion,
      toVersion: version,
      applied: List.unmodifiable(applied),
    );
  }

  static void _recordImagePolicy(Database database, WalletImageCodec images) {
    _ensureStateTable(database);
    final existing = database.select(
      'SELECT StateValue FROM actitpass_State WHERE StateKey=? LIMIT 1',
      ['image_encoding'],
    );
    if (existing.isNotEmpty) return;

    WalletImageEncoding? detected;
    if (_hasTable(database, 'spbwlt_Image')) {
      for (final row in database.select(
        'SELECT Data FROM spbwlt_Image WHERE Data IS NOT NULL ORDER BY rowid',
      )) {
        try {
          detected ??= images.detect(row['Data']);
        } catch (_) {
          // A damaged row cannot define policy. The strict audit reports it.
        }
      }
    }
    database.execute(
      'INSERT INTO actitpass_State (StateKey, StateValue) VALUES (?, ?)',
      [
        'image_encoding',
        detected == WalletImageEncoding.raw ? 'raw' : 'encrypted',
      ],
    );
  }

  static void _writeVersion(Database database, int version) {
    database.execute(
      'INSERT OR REPLACE INTO actitpass_State (StateKey, StateValue) '
      'VALUES (?, ?)',
      [_versionKey, version.toString()],
    );
  }

  static void _createPerformanceIndexes(Database database) {
    // The original SPB schema already contains these two equivalent indexes.
    database.execute('DROP INDEX IF EXISTS idx_CardFieldValue_Card');
    database.execute('DROP INDEX IF EXISTS idx_TemplateField_Template');
    database.execute('''
CREATE INDEX IF NOT EXISTS idx_Card_ParentCategory
  ON spbwlt_Card (ParentCategoryID);
CREATE INDEX IF NOT EXISTS idx_Card_Template
  ON spbwlt_Card (TemplateID);
CREATE INDEX IF NOT EXISTS idx_Category_Parent
  ON spbwlt_Category (ParentCategoryID);
CREATE INDEX IF NOT EXISTS idx_Attachment_Card
  ON spbwlt_CardAttachment (CardID);
CREATE INDEX IF NOT EXISTS idx_CardFieldValue_TemplateField
  ON spbwlt_CardFieldValue (TemplateFieldID);
CREATE INDEX IF NOT EXISTS idx_CardViewField_View
  ON spbwlt_CardViewField (CardViewID);
CREATE INDEX IF NOT EXISTS idx_CardViewField_TemplateField
  ON spbwlt_CardViewField (TemplateFieldID);
''');
  }

  static void _ensureStateTable(Database database) {
    database.execute('''
CREATE TABLE IF NOT EXISTS actitpass_State (
  StateKey TEXT NOT NULL PRIMARY KEY,
  StateValue TEXT NOT NULL
)''');
  }

  static bool _hasStateTable(Database database) =>
      _hasTable(database, 'actitpass_State');

  static bool _hasTable(Database database, String name) => database.select(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name=? LIMIT 1",
        [name],
      ).isNotEmpty;
}
