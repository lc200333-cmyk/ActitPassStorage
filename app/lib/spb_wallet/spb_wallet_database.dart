import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as image;
import 'package:sqlite3/sqlite3.dart';

import '../data/legacy_swl/legacy_swl_codec.dart';
import '../domain/card_layout.dart';
import '../services/vault_persistence.dart';
import '../services/wallet_integrity_service.dart';
import '../services/wallet_migration_service.dart';
import 'spb_wallet_attachment_codec.dart';
import 'spb_wallet_crypto.dart';
import 'wallet_image_codec.dart';

class SpbWalletUndoSnapshot {
  SpbWalletUndoSnapshot._(this.filePath, this.byteLength);

  final String filePath;
  final int byteLength;
  bool _disposed = false;

  bool get isDisposed => _disposed;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final file = File(filePath);
    if (file.existsSync()) file.deleteSync();
  }
}

/// Proof that a byte-verified, SQLite-consistent backup exists for this
/// working wallet. Instances can only be created by [SpbWalletDatabase].
class WalletRepairBackup {
  const WalletRepairBackup._({
    required this.path,
    required this.sourcePath,
    required this.length,
    required this.sha256,
  });

  final String path;
  final String sourcePath;
  final int length;
  final String sha256;

  Future<void> _verifyFor(String expectedSourcePath) async {
    if (_canonicalPath(sourcePath) != _canonicalPath(expectedSourcePath)) {
      throw StateError('Резервная копия создана для другой базы.');
    }
    final file = File(path);
    if (!await file.exists() || await file.length() != length) {
      throw StateError('Проверенная резервная копия отсутствует или изменена.');
    }
    if (await sha256File(file) != sha256) {
      throw StateError('SHA-256 резервной копии не совпадает.');
    }
    Database? verification;
    try {
      verification = sqlite3.open(path, mode: OpenMode.readOnly);
      final result = verification
          .select('PRAGMA quick_check')
          .map((row) => row.values.first.toString())
          .toList(growable: false);
      if (result.length != 1 || result.single.toLowerCase() != 'ok') {
        throw StateError('Резервная копия не прошла SQLite quick_check.');
      }
    } finally {
      verification?.dispose();
    }
  }

  static String _canonicalPath(String value) =>
      File(value).absolute.path.replaceAll('\\', '/').toLowerCase();
}

class SpbWalletDatabase {
  SpbWalletDatabase._(this.path, this._db, this.crypto)
      : attachmentCodec = SpbWalletAttachmentCodec(crypto),
        imageCodec = WalletImageCodec(SpbWalletAttachmentCodec(crypto)),
        _directIdLookups = WalletMigrationService.readVersion(_db) >=
            WalletMigrationService.currentVersion;

  static const String defaultCardIconId = '62767D3E1BC8E2C8';
  static const String defaultFolderIconId = '0C1E037B56E9E59B';

  final String path;
  final Database _db;
  final SpbWalletCrypto crypto;
  final SpbWalletAttachmentCodec attachmentCodec;
  final WalletImageCodec imageCodec;
  Map<String, Uint8List>? _embeddedIconCache;
  int _transactionDepth = 0;
  bool _directIdLookups;

  // Тот же разделитель, что и в _categoryPath() при сборке пути для чтения.
  // Голый '/' не подходит: имя папки может содержать этот символ (например
  // "AC/DC"), и тогда оно ошибочно разбилось бы на две вложенные папки.
  static const String _categoryPathSeparator = ' / ';

  static SpbWalletDatabase open(String path, String password) {
    Database? db;
    try {
      db = sqlite3.open(path);
      final wallet = SpbWalletDatabase._(path, db, SpbWalletCrypto(password));
      wallet._validateSchema();
      wallet._validatePassword();
      return wallet;
    } on SpbWalletOpenException {
      db?.dispose();
      rethrow;
    } on SqliteException catch (error) {
      db?.dispose();
      throw SpbWalletOpenException(
        'Не удалось открыть SQLite базу SPB Wallet: ${error.message}',
      );
    } on SpbWalletCryptoException catch (error) {
      db?.dispose();
      throw SpbWalletOpenException(error.message);
    } catch (_) {
      db?.dispose();
      rethrow;
    }
  }

  static String makeId() => _makeSpbId();

  WalletIntegrityReport inspectIntegrity() {
    Database? readOnly;
    try {
      readOnly = sqlite3.open(path, mode: OpenMode.readOnly);
      return WalletIntegrityService.inspect(
        readOnly,
        crypto: crypto,
        attachments: attachmentCodec,
        images: imageCodec,
      );
    } finally {
      readOnly?.dispose();
    }
  }

  Future<WalletRepairBackup> createRepairBackup(String destinationPath) async {
    final destination = File(destinationPath);
    if (await destination.exists()) {
      throw StateError('Файл резервной копии уже существует.');
    }
    await destination.parent.create(recursive: true);
    final snapshot = await createVerifiedSnapshot(
      revision: -1,
      stagingDirectory: destination.parent.path,
    );
    try {
      if (!snapshot.isValid) {
        throw StateError(
          'Рабочая база не прошла SQLite quick_check: ${snapshot.quickCheck}',
        );
      }
      await File(snapshot.path).copy(destination.path);
      final length = await destination.length();
      final digest = await sha256File(destination);
      if (length != snapshot.length || digest != snapshot.sha256) {
        if (await destination.exists()) await destination.delete();
        throw StateError('Резервная копия не совпадает со снимком базы.');
      }
      return WalletRepairBackup._(
        path: destination.path,
        sourcePath: path,
        length: length,
        sha256: digest,
      );
    } finally {
      await snapshot.dispose();
    }
  }

  Future<WalletIntegrityReport> repairLegacyCompatibility({
    required WalletRepairBackup backup,
    void Function(String stage)? faultInjector,
  }) async {
    await backup._verifyFor(path);
    final report = WalletIntegrityService.repair(
      _db,
      crypto,
      attachmentCodec,
      imageCodec,
      faultInjector: faultInjector,
    );
    _embeddedIconCache = null;
    _directIdLookups = WalletMigrationService.readVersion(_db) >=
        WalletMigrationService.currentVersion;
    return report;
  }

  bool hasTemplate(String templateId) => _db.select(
        'SELECT 1 FROM spbwlt_Template WHERE ${_idEquals('ID')} LIMIT 1',
        [_idArgument(templateId)],
      ).isNotEmpty;

  static SpbWalletDatabase create(String path, String password) {
    final file = File(path);
    if (file.existsSync()) {
      throw const SpbWalletOpenException('База SPB Wallet уже существует.');
    }
    final db = sqlite3.open(path);
    final wallet = SpbWalletDatabase._(path, db, SpbWalletCrypto(password));
    wallet._createSchema();
    wallet._seedMeta();
    wallet.setImageEncodingPolicy(WalletImageEncoding.encrypted);
    WalletMigrationService.initializeCurrent(db);
    wallet._directIdLookups = true;
    return wallet;
  }

  static String readPasswordHint(String path) {
    Database? db;
    try {
      db = sqlite3.open(path, mode: OpenMode.readOnly);
      final table = db.select(
        '''SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1''',
        ['actitpass_State'],
      );
      if (table.isEmpty) return '';
      final rows = db.select(
        'SELECT StateValue FROM actitpass_State WHERE StateKey = ? LIMIT 1',
        ['password_hint'],
      );
      return rows.isEmpty ? '' : _string(rows.first['StateValue']);
    } catch (_) {
      return '';
    } finally {
      db?.dispose();
    }
  }

  SpbWalletSnapshot loadSnapshot() {
    final loadIssues = <WalletLoadIssue>[];
    final categories = _loadCategories(_loadCategoryColors(), loadIssues);
    final categoryPaths = _buildCategoryPaths(categories);
    final templates = _loadTemplates(categoryPaths, loadIssues);
    final embeddedIconPngs = _loadEmbeddedIconPngs(loadIssues);
    final cardStates = _loadCardStates();
    final fieldValuesByCard = _loadAllCardFieldValues(loadIssues);
    final attachmentsByCard = _loadAllAttachments(loadIssues);
    final cards = <SpbWalletCardRecord>[];
    final cardLoadFailures = <SpbWalletCardLoadFailure>[];

    for (final row in _db.select(
      'SELECT hex(spbwlt_Card.ID) AS ID, spbwlt_Card.Name AS Name, spbwlt_Card.Description AS Description, hex(spbwlt_Card.ParentCategoryID) AS ParentCategoryID, hex(spbwlt_Card.TemplateID) AS TemplateID, hex(spbwlt_Card.CardViewID) AS CardViewID, hex(spbwlt_Card.IconID) AS IconID, spbwlt_Card.HitCount AS HitCount, spbwlt_CardView.CardColor AS CardColor FROM spbwlt_Card LEFT JOIN spbwlt_CardView ON ${_idJoin('spbwlt_CardView.ID', 'spbwlt_Card.CardViewID')} ORDER BY spbwlt_Card.rowid',
    )) {
      try {
        final id = _string(row['ID']);
        final templateId = _string(row['TemplateID']);
        final cardState = cardStates[id];
        final values = fieldValuesByCard[id] ?? const <String, String>{};
        cards.add(
          SpbWalletCardRecord(
            id: id,
            title: crypto.decryptText(row['Name']),
            description: crypto.decryptText(row['Description']),
            categoryPath: categoryPaths[_string(row['ParentCategoryID'])] ?? '',
            templateId: templateId,
            fieldValues: values,
            attachments: attachmentsByCard[id] ?? const [],
            hitCount: (row['HitCount'] as int?) ?? 0,
            iconId: _string(row['IconID']),
            cardColor: _cardColorToInt(row['CardColor']),
            // Large background payloads are loaded only when a card is opened.
            backgroundImageBase64: null,
            fieldOrder: cardState?.fieldOrder ?? const [],
            hiddenFieldIds: cardState?.hiddenFieldIds ?? const {},
            modifiedAt: cardState?.modifiedAt,
          ),
        );
      } catch (error) {
        // Keep healthy records visible, but report every omitted card to the UI.
        cardLoadFailures.add(
          SpbWalletCardLoadFailure(
            cardId: _string(row['ID']),
            reason: error.toString(),
          ),
        );
        loadIssues.add(
          WalletLoadIssue(
            kind: WalletLoadIssueKind.card,
            entityId: _string(row['ID']),
            reason: error.toString(),
          ),
        );
      }
    }

    return SpbWalletSnapshot(
      templates: templates,
      cards: cards,
      categories: categories.values.toList(),
      embeddedIconPngs: embeddedIconPngs,
      cardLoadFailures: cardLoadFailures,
      loadReport: WalletLoadReport(loadIssues),
    );
  }

  Map<String, Uint8List> _loadEmbeddedIconPngs(List<WalletLoadIssue> issues) {
    final cached = _embeddedIconCache;
    if (cached != null) return cached;
    final icons = <String, Uint8List>{};
    if (_columns('spbwlt_Icon').isEmpty) return icons;
    for (final row in _db.select(
      'SELECT hex(ID) AS ID, Data FROM spbwlt_Icon WHERE Data IS NOT NULL',
    )) {
      try {
        final iconBytes = attachmentCodec.decode(row['Data']).bytes;
        image.Image? decoded;
        try {
          decoded = image.IcoDecoder().decodeImageLargest(iconBytes);
        } catch (_) {
          // The payload can be PNG rather than ICO.
        }
        decoded ??= image.decodeImage(iconBytes);
        if (decoded == null) continue;
        icons[_string(row['ID']).toUpperCase()] = Uint8List.fromList(
          image.encodePng(decoded),
        );
      } catch (error) {
        // A damaged custom icon must not prevent the wallet from opening.
        issues.add(
          WalletLoadIssue(
            kind: WalletLoadIssueKind.icon,
            entityId: _string(row['ID']),
            reason: error.toString(),
          ),
        );
      }
    }
    _embeddedIconCache = icons;
    return icons;
  }

  List<SpbWalletAttachmentRecord> loadAttachments(String cardId) {
    return _db.select(
      'SELECT hex(ID) AS ID, hex(CardID) AS CardID, Name '
      'FROM spbwlt_CardAttachment WHERE ${_idEquals('CardID')} ORDER BY rowid',
      [_idArgument(cardId)],
    ).map((row) {
      return SpbWalletAttachmentRecord(
        id: _string(row['ID']),
        cardId: _string(row['CardID']),
        fileName: crypto.decryptText(row['Name']),
        // Attachment payloads can be very large. Decode them only when the
        // user opens or exports a particular attachment.
        size: -1,
      );
    }).toList();
  }

  List<SpbWalletCategoryRecord> loadCategories() => _loadCategories(
        _loadCategoryColors(),
        <WalletLoadIssue>[],
      ).values.toList(growable: false);

  String? loadCardBackgroundBase64(String cardId) {
    final rows = _db.select(
      'SELECT i.Data AS BackgroundData FROM spbwlt_Card c '
      'LEFT JOIN spbwlt_CardView v ON ${_idJoin('v.ID', 'c.CardViewID')} '
      'LEFT JOIN spbwlt_Image i ON ${_idJoin('i.ID', 'v.ImageID')} '
      'WHERE ${_idEquals('c.ID')} LIMIT 1',
      [_idArgument(cardId)],
    );
    if (rows.isEmpty) return null;
    return _imageDataToBase64(rows.first['BackgroundData']);
  }

  Uint8List readAttachmentBytes(String attachmentId) {
    final rows = _db.select(
      'SELECT Data FROM spbwlt_CardAttachment WHERE ${_idEquals('ID')}',
      [_idArgument(attachmentId)],
    );
    if (rows.isEmpty) {
      throw const SpbWalletOpenException('Вложение SPB Wallet не найдено.');
    }
    return attachmentCodec.decode(rows.first['Data']).bytes;
  }

  void _saveCardBackground(String cardId, String? backgroundImageBase64) {
    if (backgroundImageBase64 == null || backgroundImageBase64.isEmpty) return;
    final cardRows = _db.select(
      'SELECT hex(CardViewID) AS CardViewID FROM spbwlt_Card '
      'WHERE ${_idEquals('ID')}',
      [_idArgument(cardId)],
    );
    if (cardRows.isEmpty) return;
    final cardViewId = _string(cardRows.first['CardViewID']);
    final imageBytes = base64Decode(backgroundImageBase64);
    final viewRows = _db.select(
      'SELECT hex(ImageID) AS ImageID FROM spbwlt_CardView '
      'WHERE ${_idEquals('ID')}',
      [_idArgument(cardViewId)],
    );
    final currentImageId =
        viewRows.isEmpty ? '' : _string(viewRows.first['ImageID']);
    final currentRows = currentImageId.isEmpty
        ? const <Row>[]
        : _db.select(
            'SELECT Data FROM spbwlt_Image WHERE ${_idEquals('ID')}',
            [_idArgument(currentImageId)],
          );
    if (currentRows.isNotEmpty && _imageReferenceCount(currentImageId) == 1) {
      final encoding = imageCodec.detect(currentRows.first['Data']);
      _db.execute(
        'UPDATE spbwlt_Image SET Name = ?, Data = ? '
        'WHERE ${_idEquals('ID')}',
        [
          crypto.encryptText('card-background.png'),
          imageCodec.encode(imageBytes, encoding),
          _idArgument(currentImageId),
        ],
      );
      return;
    }
    final imageId = _makeSpbId();
    final encoding = _preferredImageEncoding();
    _db.execute('INSERT INTO spbwlt_Image (ID, Name, Data) VALUES (?, ?, ?)', [
      _idFromHex(imageId),
      crypto.encryptText('card-background.png'),
      imageCodec.encode(imageBytes, encoding),
    ]);
    _db.execute(
        'UPDATE spbwlt_CardView SET ImageID = ? '
        'WHERE ${_idEquals('ID')}',
        [
          _idFromHex(imageId),
          _idArgument(cardViewId),
        ]);
  }

  int _imageReferenceCount(String imageId) {
    final rows = _db.select(
      'SELECT COUNT(*) AS ReferenceCount FROM spbwlt_CardView '
      'WHERE ${_idEquals('ImageID')}',
      [_idArgument(imageId)],
    );
    return rows.isEmpty ? 0 : (rows.first['ReferenceCount'] as int? ?? 0);
  }

  WalletImageEncoding _preferredImageEncoding() {
    if (_hasLegacyStateTable()) {
      final rows = _db.select(
        'SELECT StateValue FROM actitpass_State WHERE StateKey = ? LIMIT 1',
        ['image_encoding'],
      );
      if (rows.isNotEmpty) {
        return _string(rows.first['StateValue']) == 'raw'
            ? WalletImageEncoding.raw
            : WalletImageEncoding.encrypted;
      }
    }
    for (final row in _db.select(
      'SELECT Data FROM spbwlt_Image WHERE Data IS NOT NULL LIMIT 16',
    )) {
      try {
        return imageCodec.detect(row['Data']);
      } catch (_) {
        // Damaged images do not define the encoding policy for new records.
      }
    }
    return WalletImageEncoding.encrypted;
  }

  void setImageEncodingPolicy(WalletImageEncoding encoding) {
    _ensureLegacyStateTable();
    _db.execute(
      'INSERT OR REPLACE INTO actitpass_State (StateKey, StateValue) '
      'VALUES (?, ?)',
      [
        'image_encoding',
        encoding == WalletImageEncoding.raw ? 'raw' : 'encrypted',
      ],
    );
  }

  void saveTemplate(SpbWalletTemplateDraft draft) {
    _transaction(() {
      final templateExists = _db.select(
        'SELECT 1 FROM spbwlt_Template WHERE ${_idEquals('ID')}',
        [_idArgument(draft.id)],
      ).isNotEmpty;
      if (templateExists) {
        _db.execute(
            'UPDATE spbwlt_Template SET Name = ? '
            'WHERE ${_idEquals('ID')}',
            [
              crypto.encryptText(draft.name),
              _idArgument(draft.id),
            ]);
        _saveEmbeddedIcon(draft);
        _saveTemplateIcon(draft.id, draft.iconId);
        _saveTemplateColor(draft.id, draft.cardColor);
      } else {
        final cardViewId = _createCardView();
        _db.execute(
          'INSERT INTO spbwlt_Template (ID, Name, Description, CardViewID) VALUES (?, ?, ?, ?)',
          [
            _idFromHex(draft.id),
            crypto.encryptText(draft.name),
            null,
            _idFromHex(cardViewId),
          ],
        );
        _saveEmbeddedIcon(draft);
        _saveTemplateIcon(draft.id, draft.iconId);
        _saveTemplateColor(draft.id, draft.cardColor);
      }
      _saveTemplateCategory(draft.id, draft.categoryPath);
      final existingIds = _db
          .select(
            'SELECT hex(ID) AS ID FROM spbwlt_TemplateField '
            'WHERE ${_idEquals('TemplateID')}',
            [_idArgument(draft.id)],
          )
          .map((row) => _string(row['ID']))
          .toSet();
      var priority = 0;
      final desiredIds = draft.fields.map((field) => field.id).toSet();
      for (final field in draft.fields) {
        final encryptedName = crypto.encryptText(field.name);
        if (existingIds.contains(field.id)) {
          _db.execute(
            'UPDATE spbwlt_TemplateField SET Name = ?, FieldTypeID = ?, '
            'Priority = ? WHERE ${_idEquals('ID')}',
            [
              encryptedName,
              field.fieldTypeId,
              priority,
              _idArgument(field.id),
            ],
          );
        } else {
          _db.execute(
            'INSERT INTO spbwlt_TemplateField (ID, Name, TemplateID, FieldTypeID, Priority) VALUES (?, ?, ?, ?, ?)',
            [
              _idFromHex(field.id),
              encryptedName,
              _idFromHex(draft.id),
              field.fieldTypeId,
              priority,
            ],
          );
          _createCardViewFieldForTemplateField(draft.id, field.id, priority);
        }
        priority++;
      }
      for (final fieldId in existingIds.difference(desiredIds)) {
        _db.execute(
          'DELETE FROM spbwlt_CardFieldValue '
          'WHERE ${_idEquals('TemplateFieldID')}',
          [_idArgument(fieldId)],
        );
        _db.execute(
          'DELETE FROM spbwlt_CardViewField '
          'WHERE ${_idEquals('TemplateFieldID')}',
          [_idArgument(fieldId)],
        );
        _db.execute(
          'DELETE FROM spbwlt_TemplateField WHERE ${_idEquals('ID')}',
          [_idArgument(fieldId)],
        );
      }
    });
  }

  void saveCard(SpbWalletCardDraft draft) {
    _transaction(() {
      final categoryId = _ensureCategoryPath(draft.categoryPath);
      final iconId = _resolvedCardIconId(draft.iconId, draft.templateId);
      _saveEmbeddedIconData(
        iconId,
        draft.iconBytes,
        draft.iconFileName ?? 'card-icon.png',
      );
      final description = draft.description.trim().isEmpty
          ? null
          : crypto.encryptText(draft.description);
      final exists = _db.select(
        'SELECT 1 FROM spbwlt_Card WHERE ${_idEquals('ID')}',
        [_idArgument(draft.id)],
      ).isNotEmpty;
      if (exists) {
        if (draft.preserveExistingDescriptionWhenEmpty &&
            draft.description.trim().isEmpty) {
          _db.execute(
            'UPDATE spbwlt_Card SET Name = ?, ParentCategoryID = ?, '
            'TemplateID = ? WHERE ${_idEquals('ID')}',
            [
              crypto.encryptText(draft.title),
              _idFromHex(categoryId),
              _idFromHex(draft.templateId),
              _idArgument(draft.id),
            ],
          );
        } else {
          _db.execute(
            'UPDATE spbwlt_Card SET Name = ?, Description = ?, '
            'ParentCategoryID = ?, TemplateID = ? '
            'WHERE ${_idEquals('ID')}',
            [
              crypto.encryptText(draft.title),
              description,
              _idFromHex(categoryId),
              _idFromHex(draft.templateId),
              _idArgument(draft.id),
            ],
          );
        }
      } else {
        final templateRows = _db.select(
          'SELECT hex(CardViewID) AS CardViewID FROM spbwlt_Template '
          'WHERE ${_idEquals('ID')}',
          [_idArgument(draft.templateId)],
        );
        final templateCardViewId = templateRows.isEmpty
            ? ''
            : _string(templateRows.first['CardViewID']);
        if (templateCardViewId.isEmpty) {
          throw StateError(
            'Шаблон карточки отсутствует в базе. '
            'Сначала восстановите или сохраните шаблон.',
          );
        }
        final cardViewId = _copyCardView(templateCardViewId);
        _db.execute(
          'INSERT INTO spbwlt_Card (ID, Name, Description, CardViewID, HasOwnCardView, TemplateID, ParentCategoryID, IconID) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
          [
            _idFromHex(draft.id),
            crypto.encryptText(draft.title),
            description,
            _idFromHex(cardViewId),
            0,
            _idFromHex(draft.templateId),
            _idFromHex(categoryId),
            _idFromHex(iconId),
          ],
        );
      }

      final existingValues = <String, String>{};
      final valueIdsByField = <String, List<String>>{};
      for (final row in _db.select(
        'SELECT hex(ID) AS ID, hex(TemplateFieldID) AS TemplateFieldID '
        'FROM spbwlt_CardFieldValue WHERE ${_idEquals('CardID')}',
        [_idArgument(draft.id)],
      )) {
        final fieldId = _string(row['TemplateFieldID']);
        final valueId = _string(row['ID']);
        valueIdsByField.putIfAbsent(fieldId, () => []).add(valueId);
        existingValues.putIfAbsent(fieldId, () => valueId);
      }
      final desiredFieldIds = draft.fieldValues.keys.toSet();
      for (final entry in valueIdsByField.entries) {
        final ids = entry.value;
        // Values unknown to the current UI/template are intentionally kept.
        // Old SPB Wallet databases may contain custom or legacy fields, and
        // opening and saving a card must never delete them implicitly.
        if (!desiredFieldIds.contains(entry.key)) continue;
        for (final duplicateId in ids.skip(1)) {
          _db.execute(
            'DELETE FROM spbwlt_CardFieldValue WHERE ${_idEquals('ID')}',
            [_idArgument(duplicateId)],
          );
        }
      }
      for (final entry in draft.fieldValues.entries) {
        final valueId = existingValues[entry.key];
        if (valueId == null) {
          _db.execute(
            'INSERT INTO spbwlt_CardFieldValue (ID, CardID, TemplateFieldID, ValueString) VALUES (?, ?, ?, ?)',
            [
              _idFromHex(_makeSpbId()),
              _idFromHex(draft.id),
              _idFromHex(entry.key),
              crypto.encryptText(entry.value),
            ],
          );
        } else {
          _db.execute(
            'UPDATE spbwlt_CardFieldValue SET ValueString = ? '
            'WHERE ${_idEquals('ID')}',
            [crypto.encryptText(entry.value), _idArgument(valueId)],
          );
        }
      }
      _saveCardBackground(draft.id, draft.backgroundImageBase64);
      _saveCardColor(draft.id, draft.cardColor);
      _saveCardIcon(draft.id, iconId);
      _saveCardState(draft);
    });
  }

  void saveCardWithAttachments(
    SpbWalletCardDraft draft, {
    Iterable<SpbWalletAttachmentDraft> attachments = const [],
    Iterable<String> deletedAttachmentIds = const [],
  }) {
    runTransaction<void>(() {
      saveCard(draft);
      for (final attachmentId in deletedAttachmentIds) {
        if (attachmentId.isNotEmpty) deleteAttachment(attachmentId);
      }
      for (final attachment in attachments) {
        saveAttachment(
          cardId: draft.id,
          fileName: attachment.fileName,
          bytes: attachment.bytes,
          attachmentId: attachment.id,
        );
      }
    });
  }

  void deleteCard(String cardId) {
    _transaction(() {
      _deleteCardById(cardId);
    });
  }

  void deleteTemplate(String templateId) {
    _transaction(() {
      final cardRows = _db.select(
        'SELECT hex(ID) AS ID FROM spbwlt_Card '
        'WHERE ${_idEquals('TemplateID')}',
        [_idArgument(templateId)],
      );
      for (final row in cardRows) {
        _deleteCardById(_string(row['ID']));
      }
      final templateRows = _db.select(
        'SELECT hex(CardViewID) AS CardViewID FROM spbwlt_Template '
        'WHERE ${_idEquals('ID')}',
        [_idArgument(templateId)],
      );
      final cardViewId =
          templateRows.isEmpty ? '' : _string(templateRows.first['CardViewID']);
      _db.execute(
        _directIdLookups
            ? 'DELETE FROM spbwlt_CardViewField WHERE TemplateFieldID IN '
                '(SELECT ID FROM spbwlt_TemplateField WHERE TemplateID = ?)'
            : 'DELETE FROM spbwlt_CardViewField '
                'WHERE hex(TemplateFieldID) IN (SELECT hex(ID) '
                'FROM spbwlt_TemplateField WHERE hex(TemplateID) = ?)',
        [_idArgument(templateId)],
      );
      _db.execute(
        'DELETE FROM spbwlt_TemplateField '
        'WHERE ${_idEquals('TemplateID')}',
        [_idArgument(templateId)],
      );
      _db.execute(
        'DELETE FROM spbwlt_Template WHERE ${_idEquals('ID')}',
        [_idArgument(templateId)],
      );
      final stateTable = _db.select(
        '''SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1''',
        ['actitpass_State'],
      );
      if (stateTable.isNotEmpty) {
        _db.execute('DELETE FROM actitpass_State WHERE StateKey = ?', [
          'template_category_$templateId',
        ]);
      }
      if (cardViewId.isNotEmpty) {
        _db.execute(
          'DELETE FROM spbwlt_CardViewField '
          'WHERE ${_idEquals('CardViewID')}',
          [_idArgument(cardViewId)],
        );
        _db.execute(
          'DELETE FROM spbwlt_CardView WHERE ${_idEquals('ID')}',
          [_idArgument(cardViewId)],
        );
      }
    });
  }

  void ensureCategoryPath(String path) {
    if (path.trim().isEmpty) return;
    _transaction(() => _ensureCategoryPath(path));
  }

  void _deleteCardById(String cardId) {
    final rows = _db.select(
      'SELECT hex(CardViewID) AS CardViewID FROM spbwlt_Card '
      'WHERE ${_idEquals('ID')}',
      [_idArgument(cardId)],
    );
    final cardViewId = rows.isEmpty ? '' : _string(rows.first['CardViewID']);
    _db.execute(
      'DELETE FROM spbwlt_CardFieldValue WHERE ${_idEquals('CardID')}',
      [_idArgument(cardId)],
    );
    _db.execute(
      'DELETE FROM spbwlt_CardAttachment WHERE ${_idEquals('CardID')}',
      [_idArgument(cardId)],
    );
    _db.execute(
      'DELETE FROM spbwlt_Card WHERE ${_idEquals('ID')}',
      [_idArgument(cardId)],
    );
    if (_hasLegacyStateTable()) {
      _db.execute('DELETE FROM actitpass_State WHERE StateKey IN (?, ?)', [
        'card_layout_$cardId',
        'card_modified_$cardId',
      ]);
    }
    if (cardViewId.isNotEmpty) {
      final stillUsed = _db.select(
        'SELECT 1 FROM spbwlt_Card WHERE ${_idEquals('CardViewID')} '
        'UNION SELECT 1 FROM spbwlt_Template '
        'WHERE ${_idEquals('CardViewID')} LIMIT 1',
        [_idArgument(cardViewId), _idArgument(cardViewId)],
      ).isNotEmpty;
      if (!stillUsed) {
        _db.execute(
          'DELETE FROM spbwlt_CardViewField '
          'WHERE ${_idEquals('CardViewID')}',
          [_idArgument(cardViewId)],
        );
        _db.execute(
          'DELETE FROM spbwlt_CardView WHERE ${_idEquals('ID')}',
          [_idArgument(cardViewId)],
        );
      }
    }
  }

  void saveAttachment({
    required String cardId,
    required String fileName,
    required List<int> bytes,
    String? attachmentId,
  }) {
    _transaction(() {
      final data = attachmentCodec.encode(bytes);
      final name = crypto.encryptText(fileName);
      if (attachmentId != null &&
          _db.select(
            'SELECT 1 FROM spbwlt_CardAttachment '
            'WHERE ${_idEquals('ID')}',
            [_idArgument(attachmentId)],
          ).isNotEmpty) {
        _db.execute(
          'UPDATE spbwlt_CardAttachment SET Name = ?, Data = ? '
          'WHERE ${_idEquals('ID')}',
          [name, data, _idArgument(attachmentId)],
        );
      } else {
        _db.execute(
          'INSERT INTO spbwlt_CardAttachment (ID, CardID, Name, Data) VALUES (?, ?, ?, ?)',
          [
            _idFromHex(attachmentId ?? _makeSpbId()),
            _idFromHex(cardId),
            name,
            data,
          ],
        );
      }
    });
  }

  void deleteAttachment(String attachmentId) {
    _transaction(() {
      _db.execute(
        'DELETE FROM spbwlt_CardAttachment WHERE ${_idEquals('ID')}',
        [_idArgument(attachmentId)],
      );
    });
  }

  int deleteOrphanImages() {
    return runTransaction<int>(() {
      final before = _db
          .select('SELECT COUNT(*) AS C FROM spbwlt_Image')
          .first['C'] as int;
      _db.execute(
        'DELETE FROM spbwlt_Image WHERE NOT EXISTS ('
        'SELECT 1 FROM spbwlt_CardView WHERE '
        '${_idJoin('spbwlt_CardView.ImageID', 'spbwlt_Image.ID')})',
      );
      final after = _db
          .select('SELECT COUNT(*) AS C FROM spbwlt_Image')
          .first['C'] as int;
      return before - after;
    });
  }

  void recordCardHit(String cardId) {
    _db.execute(
      'UPDATE spbwlt_Card SET HitCount = HitCount + 1 '
      'WHERE ${_idEquals('ID')}',
      [_idArgument(cardId)],
    );
  }

  void saveCategoryIcon(String categoryPath, String iconId) {
    _transaction(() {
      final categoryId = _ensureCategoryPath(categoryPath);
      if (categoryId.isEmpty) return;
      _db.execute(
          'UPDATE spbwlt_Category SET IconID = ? '
          'WHERE ${_idEquals('ID')}',
          [
            _idFromHex(iconId.isEmpty ? defaultFolderIconId : iconId),
            _idArgument(categoryId),
          ]);
    });
  }

  void createCategory(
    String categoryPath,
    String iconId, {
    List<int>? iconBytes,
    String? iconFileName,
    String? colorId,
  }) {
    _transaction(() {
      _saveEmbeddedIconData(
        iconId,
        iconBytes,
        iconFileName ?? 'folder-icon.png',
      );
      final categoryId = _ensureCategoryPath(categoryPath);
      if (categoryId.isEmpty) return;
      _saveCategoryColor(categoryId, colorId);
      _db.execute(
          'UPDATE spbwlt_Category SET IconID = ? '
          'WHERE ${_idEquals('ID')}',
          [
            _idFromHex(iconId.isEmpty ? defaultFolderIconId : iconId),
            _idArgument(categoryId),
          ]);
    });
  }

  void renameCategory(
    String categoryPath,
    String newName,
    String iconId, {
    List<int>? iconBytes,
    String? iconFileName,
    String? colorId,
  }) {
    _transaction(() {
      _saveEmbeddedIconData(
        iconId,
        iconBytes,
        iconFileName ?? 'folder-icon.png',
      );
      final categoryId = _categoryIdForPath(categoryPath);
      if (categoryId == null) {
        throw const SpbWalletOpenException('Папка SPB Wallet не найдена.');
      }
      _saveCategoryColor(categoryId, colorId);
      final cleanName = newName.trim();
      if (cleanName.isEmpty || cleanName.contains('/')) {
        throw const SpbWalletOpenException('Некорректное имя папки.');
      }
      final parentId = _categoryParentId(categoryId);
      final siblingRows = _db.select(
        'SELECT hex(ID) AS ID, Name FROM spbwlt_Category '
        'WHERE ${_idEquals('ParentCategoryID')}',
        [_idArgument(parentId)],
      );
      for (final row in siblingRows) {
        final id = _string(row['ID']);
        if (id != categoryId && crypto.decryptText(row['Name']) == cleanName) {
          throw const SpbWalletOpenException(
            'Папка с таким именем уже существует.',
          );
        }
      }
      _db.execute(
        'UPDATE spbwlt_Category SET Name = ?, IconID = ? '
        'WHERE ${_idEquals('ID')}',
        [
          crypto.encryptText(cleanName),
          _idFromHex(iconId.isEmpty ? defaultFolderIconId : iconId),
          _idArgument(categoryId),
        ],
      );
    });
  }

  void moveCategory(String categoryPath, String targetParentPath) {
    _transaction(() {
      final categoryId = _categoryIdForPath(categoryPath);
      if (categoryId == null) {
        throw const SpbWalletOpenException('Папка SPB Wallet не найдена.');
      }
      final targetId = targetParentPath.trim().isEmpty
          ? ''
          : _categoryIdForPath(targetParentPath);
      if (targetId == null) {
        throw const SpbWalletOpenException('Целевая папка не найдена.');
      }
      if (targetId == categoryId ||
          _categoryDescendantIds(categoryId).contains(targetId)) {
        throw const SpbWalletOpenException(
          'Нельзя переместить папку внутрь самой себя.',
        );
      }
      final nameRow = _db.select(
        'SELECT Name FROM spbwlt_Category WHERE ${_idEquals('ID')}',
        [_idArgument(categoryId)],
      );
      final name = crypto.decryptText(nameRow.single['Name']);
      final siblings = _db.select(
        'SELECT hex(ID) AS ID, Name FROM spbwlt_Category '
        'WHERE ${_idEquals('ParentCategoryID')}',
        [_idArgument(targetId)],
      );
      for (final row in siblings) {
        if (_string(row['ID']) != categoryId &&
            crypto.decryptText(row['Name']) == name) {
          throw const SpbWalletOpenException(
            'В целевой папке уже есть папка с таким именем.',
          );
        }
      }
      _db.execute(
        'UPDATE spbwlt_Category SET ParentCategoryID = ? '
        'WHERE ${_idEquals('ID')}',
        [_idFromHex(targetId), _idArgument(categoryId)],
      );
    });
  }

  void moveCard(String cardId, String targetCategoryPath) {
    _transaction(() {
      final exists = _db.select(
        'SELECT 1 FROM spbwlt_Card WHERE ${_idEquals('ID')}',
        [_idArgument(cardId)],
      ).isNotEmpty;
      if (!exists) {
        throw const SpbWalletOpenException('Карточка SPB Wallet не найдена.');
      }
      final categoryId = targetCategoryPath.trim().isEmpty
          ? ''
          : _categoryIdForPath(targetCategoryPath);
      if (categoryId == null) {
        throw const SpbWalletOpenException('Целевая папка не найдена.');
      }
      _db.execute(
        'UPDATE spbwlt_Card SET ParentCategoryID = ? '
        'WHERE ${_idEquals('ID')}',
        [_idFromHex(categoryId), _idArgument(cardId)],
      );
    });
  }

  void deleteCategory(String categoryPath) {
    _transaction(() {
      final categoryId = _categoryIdForPath(categoryPath);
      if (categoryId == null) {
        throw const SpbWalletOpenException('Папка SPB Wallet не найдена.');
      }
      final descendants = _categoryDescendantIds(categoryId);
      final ids = [...descendants, categoryId];
      final hasStateTable = _db.select(
        '''SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1''',
        ['actitpass_State'],
      ).isNotEmpty;
      for (final id in ids) {
        final cardRows = _db.select(
          'SELECT hex(ID) AS ID FROM spbwlt_Card '
          'WHERE ${_idEquals('ParentCategoryID')}',
          [_idArgument(id)],
        );
        for (final row in cardRows) {
          _deleteCardById(_string(row['ID']));
        }
      }
      for (final id in descendants.reversed) {
        _db.execute(
          'DELETE FROM spbwlt_Category WHERE ${_idEquals('ID')}',
          [_idArgument(id)],
        );
      }
      if (hasStateTable) {
        for (final id in ids) {
          _db.execute('DELETE FROM actitpass_State WHERE StateKey = ?', [
            'category_color_$id',
          ]);
        }
      }
      _db.execute(
        'DELETE FROM spbwlt_Category WHERE ${_idEquals('ID')}',
        [_idArgument(categoryId)],
      );
    });
  }

  void flushToDisk() {
    _db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
  }

  Future<SpbWalletUndoSnapshot> createUndoSnapshot() async {
    final directory = Directory(
      '${File(path).parent.path}${Platform.pathSeparator}.wallet_aps_undo',
    );
    await directory.create(recursive: true);
    final file = File(
      '${directory.path}${Platform.pathSeparator}'
      'undo_${DateTime.now().microsecondsSinceEpoch}.swl',
    );
    Database? snapshot;
    try {
      snapshot = sqlite3.open(file.path);
      await _db.backup(snapshot, nPage: -1).drain<void>();
      final quickCheck =
          snapshot.select('PRAGMA quick_check').single.values.first;
      if (quickCheck.toString().toLowerCase() != 'ok') {
        throw StateError('Undo snapshot failed SQLite quick_check.');
      }
      snapshot.dispose();
      snapshot = null;
      return SpbWalletUndoSnapshot._(file.path, await file.length());
    } catch (_) {
      snapshot?.dispose();
      if (await file.exists()) await file.delete();
      rethrow;
    }
  }

  Future<void> restoreUndoSnapshot(SpbWalletUndoSnapshot snapshot) async {
    if (snapshot._disposed) {
      throw StateError('Снимок истории изменений уже освобождён.');
    }
    final file = File(snapshot.filePath);
    if (!await file.exists() || await file.length() != snapshot.byteLength) {
      throw StateError('Undo snapshot is missing or has changed.');
    }
    final source = sqlite3.open(snapshot.filePath, mode: OpenMode.readOnly);
    try {
      final quickCheck =
          source.select('PRAGMA quick_check').single.values.first;
      if (quickCheck.toString().toLowerCase() != 'ok') {
        throw StateError('Undo snapshot failed SQLite quick_check.');
      }
      await source.backup(_db, nPage: -1).drain<void>();
    } finally {
      source.dispose();
    }
  }

  List<String> loadRecentlyOpenedCardIds() {
    final table = _db.select(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1",
      ['actitpass_State'],
    );
    if (table.isEmpty) return const [];
    final rows = _db.select(
      'SELECT StateValue FROM actitpass_State WHERE StateKey = ?',
      ['recently_opened_cards'],
    );
    if (rows.isEmpty) return const [];
    try {
      final decoded = jsonDecode(_string(rows.first['StateValue']));
      return decoded is List
          ? decoded.whereType<String>().take(10).toList()
          : const [];
    } catch (_) {
      return const [];
    }
  }

  void saveRecentlyOpenedCardIds(Iterable<String> cardIds) {
    _ensureLegacyStateTable();
    _db.execute(
      'INSERT OR REPLACE INTO actitpass_State (StateKey, StateValue) VALUES (?, ?)',
      ['recently_opened_cards', jsonEncode(cardIds.take(10).toList())],
    );
  }

  String loadPasswordHint() {
    if (!_hasLegacyStateTable()) return '';
    final rows = _db.select(
      'SELECT StateValue FROM actitpass_State WHERE StateKey = ? LIMIT 1',
      ['password_hint'],
    );
    return rows.isEmpty ? '' : _string(rows.first['StateValue']);
  }

  void savePasswordHint(String hint) {
    _ensureLegacyStateTable();
    final value = hint.trim();
    if (value.isEmpty) {
      _db.execute('DELETE FROM actitpass_State WHERE StateKey = ?', [
        'password_hint',
      ]);
      return;
    }
    _db.execute(
      'INSERT OR REPLACE INTO actitpass_State (StateKey, StateValue) VALUES (?, ?)',
      ['password_hint', value],
    );
  }

  void _ensureLegacyStateTable() {
    _db.execute('''
CREATE TABLE IF NOT EXISTS actitpass_State (
  StateKey TEXT NOT NULL PRIMARY KEY,
  StateValue TEXT NOT NULL
)''');
  }

  Map<String, Map<String, String>> _loadAllCardFieldValues(
    List<WalletLoadIssue> issues,
  ) {
    final result = <String, Map<String, String>>{};
    for (final row in _db.select(
      'SELECT hex(CardID) AS CardID, hex(TemplateFieldID) AS TemplateFieldID, ValueString FROM spbwlt_CardFieldValue ORDER BY CardID, rowid',
    )) {
      try {
        result
            .putIfAbsent(_string(row['CardID']), () => <String, String>{})
            .putIfAbsent(
              _string(row['TemplateFieldID']),
              () => crypto.decryptText(row['ValueString']),
            );
      } catch (error) {
        // Preserve the rest of the wallet when one legacy value is damaged.
        issues.add(
          WalletLoadIssue(
            kind: WalletLoadIssueKind.field,
            entityId:
                '${_string(row['CardID'])}/${_string(row['TemplateFieldID'])}',
            reason: error.toString(),
          ),
        );
      }
    }
    return result;
  }

  Map<String, List<SpbWalletAttachmentRecord>> _loadAllAttachments(
    List<WalletLoadIssue> issues,
  ) {
    final result = <String, List<SpbWalletAttachmentRecord>>{};
    for (final row in _db.select(
      'SELECT hex(ID) AS ID, hex(CardID) AS CardID, Name FROM spbwlt_CardAttachment ORDER BY CardID, rowid',
    )) {
      final cardId = _string(row['CardID']);
      try {
        result.putIfAbsent(cardId, () => []).add(
              SpbWalletAttachmentRecord(
                id: _string(row['ID']),
                cardId: cardId,
                fileName: crypto.decryptText(row['Name']),
                size: -1,
              ),
            );
      } catch (error) {
        issues.add(
          WalletLoadIssue(
            kind: WalletLoadIssueKind.attachment,
            entityId: _string(row['ID']),
            reason: error.toString(),
          ),
        );
        result.putIfAbsent(cardId, () => []).add(
              SpbWalletAttachmentRecord(
                id: _string(row['ID']),
                cardId: cardId,
                fileName: 'Повреждённое вложение',
                size: -1,
                decodeError: '$error',
              ),
            );
      }
    }
    for (final attachments in result.values) {
      attachments.sort((a, b) {
        final byName = a.fileName.toLowerCase().compareTo(
              b.fileName.toLowerCase(),
            );
        return byName == 0 ? a.id.compareTo(b.id) : byName;
      });
    }
    return result;
  }

  String? _imageDataToBase64(Object? data) {
    if (data == null) return null;
    if (data is List<int> && data.isEmpty) return null;
    return base64Encode(imageCodec.decode(data).bytes);
  }

  Future<VaultSnapshot> createVerifiedSnapshot({
    required int revision,
    String? stagingDirectory,
  }) async {
    flushToDisk();
    final directory = Directory(stagingDirectory ?? Directory.systemTemp.path);
    await directory.create(recursive: true);
    final file = File(
      '${directory.path}${Platform.pathSeparator}'
      'wallet_aps_snapshot_${DateTime.now().microsecondsSinceEpoch}_$revision.swl',
    );
    Database? snapshotDatabase;
    try {
      snapshotDatabase = sqlite3.open(file.path);
      await _db.backup(snapshotDatabase, nPage: -1).drain<void>();
      final quickCheck = snapshotDatabase
          .select('PRAGMA quick_check')
          .map((row) => row.values.first.toString())
          .join('\n');
      snapshotDatabase.dispose();
      snapshotDatabase = null;
      return VaultSnapshot(
        path: file.path,
        revision: revision,
        length: await file.length(),
        sha256: await sha256File(file),
        quickCheck: quickCheck,
      );
    } catch (_) {
      snapshotDatabase?.dispose();
      if (await file.exists()) await file.delete();
      rethrow;
    }
  }

  bool _hasLegacyStateTable() => _db.select(
        '''SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1''',
        ['actitpass_State'],
      ).isNotEmpty;

  Map<String, CardLayoutState> _loadCardStates() {
    if (!_hasLegacyStateTable()) return const {};
    final states = <String, CardLayoutState>{};
    for (final row in _db.select(
      '''SELECT StateKey, StateValue FROM actitpass_State WHERE StateKey LIKE 'card_layout_%' OR StateKey LIKE 'card_modified_%' ''',
    )) {
      final key = _string(row['StateKey']);
      final value = _string(row['StateValue']);
      final isLayout = key.startsWith('card_layout_');
      final prefix = isLayout ? 'card_layout_' : 'card_modified_';
      final id = key.substring(prefix.length);
      final previous = states[id] ?? const CardLayoutState();
      if (isLayout) {
        states[id] = CardLayoutState.decodeLayout(value, previous);
      } else {
        states[id] = CardLayoutState(
          fieldOrder: previous.fieldOrder,
          hiddenFieldIds: previous.hiddenFieldIds,
          modifiedAt: DateTime.tryParse(value),
        );
      }
    }
    return states;
  }

  void _saveCardState(SpbWalletCardDraft draft) {
    _ensureLegacyStateTable();
    _db.execute(
      'INSERT OR REPLACE INTO actitpass_State (StateKey, StateValue) VALUES (?, ?)',
      [
        'card_layout_${draft.id}',
        CardLayoutState(
          fieldOrder: draft.fieldOrder,
          hiddenFieldIds: draft.hiddenFieldIds,
        ).encodeLayout(),
      ],
    );
    _db.execute(
      'INSERT OR REPLACE INTO actitpass_State (StateKey, StateValue) VALUES (?, ?)',
      [
        'card_modified_${draft.id}',
        (draft.modifiedAt ?? DateTime.now().toUtc()).toIso8601String(),
      ],
    );
  }

  void close({bool flush = true}) {
    if (flush) flushToDisk();
    _db.dispose();
  }

  void _createSchema() {
    _db.execute('''
CREATE TABLE spb_DatabaseVersion (
  ProductID INTEGER NOT NULL PRIMARY KEY,
  ProductName VARCHAR(256) NOT NULL,
  VersionString VARCHAR(256) NOT NULL,
  CompatibilityVersion INTEGER NOT NULL,
  ProductMajorVersion INTEGER NOT NULL,
  ProductMinorVersion INTEGER NOT NULL
);
CREATE TABLE spbwlt_Wallet (
  ID VARCHAR(22) UNIQUE NOT NULL PRIMARY KEY,
  AdvVersionInfo INTEGER NOT NULL,
  CurrentSyncID INTEGER NOT NULL DEFAULT -1,
  SyncID INTEGER DEFAULT -1,
  SyncInfo BLOB,
  CreateSyncID INTEGER NOT NULL DEFAULT -1
);
CREATE TABLE spbwlt_Card (
  ID VARCHAR(22) UNIQUE NOT NULL PRIMARY KEY,
  Name BLOB NOT NULL,
  Description BLOB NULL,
  CardViewID VARCHAR(22) NOT NULL,
  HasOwnCardView INTEGER NOT NULL DEFAULT 0,
  TemplateID VARCHAR(22) NOT NULL,
  ParentCategoryID VARCHAR(22) NOT NULL,
  IconID VARCHAR(22) NOT NULL,
  HitCount INTEGER DEFAULT 0 NOT NULL,
  SyncID INTEGER NOT NULL DEFAULT -1,
  CreateSyncID INTEGER NOT NULL DEFAULT -1
);
CREATE TABLE spbwlt_CardAttachment (
  ID VARCHAR(22) UNIQUE NOT NULL PRIMARY KEY,
  CardID VARCHAR(22) NOT NULL,
  Name BLOB NOT NULL,
  Data BLOB,
  SyncID INTEGER NOT NULL DEFAULT -1,
  CreateSyncID INTEGER NOT NULL DEFAULT -1
);
CREATE TABLE spbwlt_CardFieldValue (
  ID VARCHAR(22) UNIQUE NOT NULL PRIMARY KEY,
  CardID VARCHAR(22) NOT NULL,
  TemplateFieldID VARCHAR(22) NOT NULL,
  ValueString BLOB NULL,
  SyncID INTEGER NOT NULL DEFAULT -1,
  CreateSyncID INTEGER NOT NULL DEFAULT -1
);
CREATE TABLE spbwlt_CardView (
  ID VARCHAR(22) UNIQUE NOT NULL PRIMARY KEY,
  CardColor BLOB NOT NULL,
  CornerType INTEGER NOT NULL,
  ShowHiddenFields INTEGER NOT NULL,
  IconID VARCHAR(22) NOT NULL,
  ImageID VARCHAR(22) NOT NULL,
  ImgPosition INTEGER NOT NULL DEFAULT 4,
  ShowCardBorder INTEGER NOT NULL DEFAULT 1,
  FillCardWithColor INTEGER NOT NULL DEFAULT 1,
  SyncID INTEGER NOT NULL DEFAULT -1,
  CreateSyncID INTEGER NOT NULL DEFAULT -1
);
CREATE TABLE spbwlt_Category (
  ID VARCHAR(22) UNIQUE NOT NULL PRIMARY KEY,
  Name BLOB NOT NULL,
  Description BLOB NULL,
  IconID VARCHAR(22) NOT NULL,
  DefaultTemplateID VARCHAR(22),
  ParentCategoryID VARCHAR(22) NOT NULL,
  SyncID INTEGER NOT NULL DEFAULT -1,
  CreateSyncID INTEGER NOT NULL DEFAULT -1
);
CREATE TABLE spbwlt_Icon (
  ID VARCHAR(22) UNIQUE NOT NULL PRIMARY KEY,
  Name BLOB NOT NULL,
  Data BLOB,
  SyncID INTEGER NOT NULL DEFAULT -1,
  CreateSyncID INTEGER NOT NULL DEFAULT -1
);
CREATE TABLE spbwlt_Image (
  ID VARCHAR(22) UNIQUE NOT NULL PRIMARY KEY,
  Name BLOB NOT NULL,
  Data BLOB,
  SyncID INTEGER NOT NULL DEFAULT -1,
  CreateSyncID INTEGER NOT NULL DEFAULT -1
);
CREATE TABLE spbwlt_Template (
  ID VARCHAR(22) UNIQUE NOT NULL PRIMARY KEY,
  Name BLOB NOT NULL,
  Description BLOB NULL,
  CardViewID VARCHAR(22) NOT NULL,
  SyncID INTEGER NOT NULL DEFAULT -1,
  CreateSyncID INTEGER NOT NULL DEFAULT -1
);
CREATE TABLE spbwlt_TemplateField (
  ID VARCHAR(22) UNIQUE NOT NULL PRIMARY KEY,
  Name BLOB NOT NULL,
  TemplateID VARCHAR(22) NOT NULL,
  FieldTypeID INTEGER NOT NULL,
  Priority INTEGER DEFAULT 0 NOT NULL,
  SyncID INTEGER NOT NULL DEFAULT -1,
  AdvInfo BLOB,
  CreateSyncID INTEGER NOT NULL DEFAULT -1
);
CREATE TABLE spbwlt_TemplateFieldType (
  ID INTEGER PRIMARY KEY NOT NULL,
  Name NVARCHAR(256) NOT NULL,
  SyncID INTEGER NOT NULL DEFAULT -1,
  CreateSyncID INTEGER NOT NULL DEFAULT -1
);
CREATE TABLE spbwlt_CardViewField (
  ID VARCHAR(22) UNIQUE NOT NULL PRIMARY KEY,
  CardViewID VARCHAR(22) NOT NULL,
  TemplateFieldID VARCHAR(22) NOT NULL,
  PositionX INTEGER NOT NULL,
  PositionY INTEGER NOT NULL,
  FontFamily NVARCHAR(256) NOT NULL,
  FontSize INTEGER NOT NULL,
  FontColor VARCHAR(3) NOT NULL,
  TextStyle INTEGER NOT NULL DEFAULT 0,
  TextAlign INTEGER NOT NULL DEFAULT 0,
  ShowFieldName INTEGER NOT NULL DEFAULT 1,
  SyncID INTEGER NOT NULL DEFAULT -1,
  CreateSyncID INTEGER NOT NULL DEFAULT -1
);
CREATE INDEX idx_CardFieldValue ON spbwlt_CardFieldValue (CardID);
CREATE INDEX idx_TemplateField ON spbwlt_TemplateField (TemplateID);
CREATE TRIGGER on_delete_Card AFTER DELETE ON spbwlt_Card
BEGIN
  DELETE FROM spbwlt_CardAttachment WHERE CardID=OLD.ID;
  DELETE FROM spbwlt_CardFieldValue WHERE CardID=OLD.ID;
END;
CREATE TRIGGER on_delete_CardView BEFORE DELETE ON spbwlt_CardView
BEGIN
  DELETE FROM spbwlt_CardViewField WHERE CardViewID=OLD.ID;
END;
CREATE TRIGGER on_delete_Category BEFORE DELETE ON spbwlt_Category
BEGIN
  DELETE FROM spbwlt_Card WHERE ParentCategoryID=OLD.ID;
  DELETE FROM spbwlt_Category WHERE ParentCategoryID=OLD.ID;
END;
CREATE TRIGGER on_delete_Icon BEFORE DELETE ON spbwlt_Icon
BEGIN
  UPDATE spbwlt_Card SET IconID='' WHERE IconID=OLD.ID;
  UPDATE spbwlt_Category SET IconID='' WHERE IconID=OLD.ID;
  UPDATE spbwlt_CardView SET IconID='' WHERE IconID=OLD.ID;
END;
CREATE TRIGGER on_delete_Image BEFORE DELETE ON spbwlt_Image
BEGIN
  UPDATE spbwlt_CardView SET ImageID='' WHERE ImageID=OLD.ID;
END;
CREATE TRIGGER on_delete_Template BEFORE DELETE ON spbwlt_Template
BEGIN
  DELETE FROM spbwlt_Card WHERE TemplateID=OLD.ID;
  DELETE FROM spbwlt_TemplateField WHERE TemplateID=OLD.ID;
END;
CREATE TRIGGER on_delete_TemplateField BEFORE DELETE ON spbwlt_TemplateField
BEGIN
  DELETE FROM spbwlt_CardFieldValue WHERE TemplateFieldID=OLD.ID;
  DELETE FROM spbwlt_CardViewField WHERE TemplateFieldID=OLD.ID;
END;
''');
  }

  void _seedMeta() {
    _db.execute(
      'INSERT INTO spb_DatabaseVersion (ProductID, ProductName, VersionString, CompatibilityVersion, ProductMajorVersion, ProductMinorVersion) VALUES (?, ?, ?, ?, ?, ?)',
      [1, 'SpbWallet', '1.0.0', 18, 1, 0],
    );
    _db.execute(
      'INSERT INTO spbwlt_Wallet (ID, AdvVersionInfo) VALUES (?, ?)',
      [LegacySwlCodec.makeWalletId(), -496552629],
    );
  }

  void _validateSchema() {
    final required = {
      'spbwlt_Category': ['ID', 'Name', 'ParentCategoryID'],
      'spbwlt_Card': [
        'ID',
        'Name',
        'Description',
        'ParentCategoryID',
        'TemplateID',
      ],
      'spbwlt_CardFieldValue': [
        'ID',
        'CardID',
        'TemplateFieldID',
        'ValueString',
      ],
      'spbwlt_TemplateField': ['ID', 'Name', 'TemplateID'],
      'spbwlt_CardAttachment': ['ID', 'CardID', 'Name', 'Data'],
    };
    for (final entry in required.entries) {
      final columns = _columns(entry.key);
      if (columns.isEmpty) {
        throw SpbWalletOpenException(
          'В файле нет таблицы ${entry.key}. Это не поддерживаемая база SPB Wallet.',
        );
      }
      for (final column in entry.value) {
        if (!columns.contains(column)) {
          throw SpbWalletOpenException(
            'В таблице ${entry.key} нет колонки $column.',
          );
        }
      }
    }
  }

  void _validatePassword() {
    final samples = <Object?>[];
    for (final tableAndColumn in const [
      ['spbwlt_Category', 'Name'],
      ['spbwlt_Card', 'Name'],
      ['spbwlt_TemplateField', 'Name'],
    ]) {
      final rows = _db.select(
        'SELECT ${tableAndColumn[1]} AS value FROM ${tableAndColumn[0]} LIMIT 3',
      );
      samples.addAll(rows.map((row) => row['value']));
    }
    if (samples.isEmpty) return;
    final validSamples =
        samples.where((sample) => crypto.looksLikeValidText(sample)).length;
    final requiredSamples = samples.length >= 3 ? 2 : 1;
    if (validSamples < requiredSamples) {
      throw const SpbWalletOpenException(
        'Пароль SPB Wallet не подходит или база повреждена.',
      );
    }
    crypto.detectTextEndian(samples);
  }

  Map<String, String> _loadCategoryColors() {
    final table = _db.select(
      '''SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1''',
      ['actitpass_State'],
    );
    if (table.isEmpty) return const {};
    final result = <String, String>{};
    for (final row in _db.select(
      '''SELECT StateKey, StateValue FROM actitpass_State WHERE StateKey LIKE 'category_color_%' ''',
    )) {
      final key = _string(row['StateKey']);
      final id = key.substring('category_color_'.length);
      result[id] = _string(row['StateValue']);
    }
    return result;
  }

  void _saveCategoryColor(String categoryId, String? colorId) {
    if (colorId == null || colorId.isEmpty) return;
    _ensureLegacyStateTable();
    _db.execute(
      'INSERT OR REPLACE INTO actitpass_State (StateKey, StateValue) VALUES (?, ?)',
      ['category_color_$categoryId', colorId],
    );
  }

  Map<String, SpbWalletCategoryRecord> _loadCategories(
    Map<String, String> colors,
    List<WalletLoadIssue> issues,
  ) {
    final result = <String, SpbWalletCategoryRecord>{};
    for (final row in _db.select(
      'SELECT hex(ID) AS ID, Name, hex(ParentCategoryID) AS ParentCategoryID, hex(IconID) AS IconID FROM spbwlt_Category ORDER BY hex(ID)',
    )) {
      try {
        final id = _string(row['ID']);
        result[id] = SpbWalletCategoryRecord(
          id: id,
          name: crypto.decryptText(row['Name']),
          parentId: _string(row['ParentCategoryID']),
          iconId: _string(row['IconID']),
          colorId: colors[id] ?? '',
        );
      } catch (error) {
        // A damaged category must not prevent the remaining wallet from opening.
        issues.add(
          WalletLoadIssue(
            kind: WalletLoadIssueKind.category,
            entityId: _string(row['ID']),
            reason: error.toString(),
          ),
        );
      }
    }
    return result;
  }

  Map<String, String> _loadTemplateCategoryIds() {
    final table = _db.select(
      '''SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1''',
      ['actitpass_State'],
    );
    if (table.isEmpty) return const {};
    final result = <String, String>{};
    for (final row in _db.select(
      '''SELECT StateKey, StateValue FROM actitpass_State WHERE StateKey LIKE 'template_category_%' ''',
    )) {
      final key = _string(row['StateKey']);
      result[key.substring('template_category_'.length)] = _string(
        row['StateValue'],
      );
    }
    return result;
  }

  void _saveTemplateCategory(String templateId, String categoryPath) {
    _ensureLegacyStateTable();
    final key = 'template_category_$templateId';
    if (categoryPath.trim().isEmpty) {
      _db.execute('DELETE FROM actitpass_State WHERE StateKey = ?', [key]);
      return;
    }
    final categoryId = _ensureCategoryPath(categoryPath);
    _db.execute(
      'INSERT OR REPLACE INTO actitpass_State (StateKey, StateValue) VALUES (?, ?)',
      [key, categoryId],
    );
  }

  List<SpbWalletTemplateRecord> _loadTemplates(
    Map<String, String> categoryPaths,
    List<WalletLoadIssue> issues,
  ) {
    final fields = _loadTemplateFields(issues);
    final categoryIds = _loadTemplateCategoryIds();
    final byTemplate = <String, List<SpbWalletTemplateFieldRecord>>{};
    for (final field in fields) {
      byTemplate.putIfAbsent(field.templateId, () => []).add(field);
    }
    final templates = <SpbWalletTemplateRecord>[];
    for (final row in _db.select(
      'SELECT hex(spbwlt_Template.ID) AS ID, Name, hex(spbwlt_CardView.IconID) AS IconID, spbwlt_CardView.CardColor AS CardColor FROM spbwlt_Template LEFT JOIN spbwlt_CardView ON ${_idJoin('spbwlt_CardView.ID', 'spbwlt_Template.CardViewID')} ORDER BY spbwlt_Template.rowid',
    )) {
      try {
        final id = _string(row['ID']);
        templates.add(
          SpbWalletTemplateRecord(
            id: id,
            name: crypto.decryptText(row['Name']),
            iconId: _string(row['IconID']),
            cardColor: _cardColorToInt(row['CardColor']),
            categoryPath: categoryPaths[categoryIds[id] ?? ''] ?? '',
            fields: byTemplate[id] ?? const [],
          ),
        );
      } catch (error) {
        // Keep valid templates available if a single encrypted row is damaged.
        issues.add(
          WalletLoadIssue(
            kind: WalletLoadIssueKind.template,
            entityId: _string(row['ID']),
            reason: error.toString(),
          ),
        );
      }
    }
    return templates;
  }

  List<SpbWalletTemplateFieldRecord> _loadTemplateFields(
    List<WalletLoadIssue> issues,
  ) {
    final result = <SpbWalletTemplateFieldRecord>[];
    for (final row in _db.select(
      'SELECT hex(ID) AS ID, Name, hex(TemplateID) AS TemplateID, FieldTypeID, Priority FROM spbwlt_TemplateField ORDER BY hex(TemplateID), Priority',
    )) {
      try {
        result.add(
          SpbWalletTemplateFieldRecord(
            id: _string(row['ID']),
            name: crypto.decryptText(row['Name']),
            templateId: _string(row['TemplateID']),
            fieldTypeId: (row['FieldTypeID'] as int?) ?? 1,
          ),
        );
      } catch (error) {
        // Skip only the unreadable field definition.
        issues.add(
          WalletLoadIssue(
            kind: WalletLoadIssueKind.field,
            entityId: _string(row['ID']),
            reason: error.toString(),
          ),
        );
      }
    }
    return result;
  }

  String _ensureCategoryPath(String path) {
    final cleanParts = path
        .split(_categoryPathSeparator)
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    if (cleanParts.isEmpty) return '';

    var parentId = '';
    for (final part in cleanParts) {
      final rows = _db.select(
        'SELECT hex(ID) AS ID, Name FROM spbwlt_Category '
        'WHERE ${_idEquals('ParentCategoryID')}',
        [_idArgument(parentId)],
      );
      String? found;
      for (final row in rows) {
        if (crypto.decryptText(row['Name']) == part) {
          found = _string(row['ID']);
          break;
        }
      }
      if (found == null) {
        found = _makeSpbId();
        _db.execute(
          'INSERT INTO spbwlt_Category (ID, Name, Description, IconID, DefaultTemplateID, ParentCategoryID) VALUES (?, ?, ?, ?, ?, ?)',
          [
            _idFromHex(found),
            crypto.encryptText(part),
            null,
            _idFromHex(defaultFolderIconId),
            _idFromHex(_defaultTemplateId()),
            _idFromHex(parentId),
          ],
        );
      }
      parentId = found;
    }
    return parentId;
  }

  String? _categoryIdForPath(String path) {
    final cleanParts = path
        .split(_categoryPathSeparator)
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    if (cleanParts.isEmpty) return null;

    var parentId = '';
    String? currentId;
    for (final part in cleanParts) {
      currentId = null;
      final rows = _db.select(
        'SELECT hex(ID) AS ID, Name FROM spbwlt_Category '
        'WHERE ${_idEquals('ParentCategoryID')}',
        [_idArgument(parentId)],
      );
      for (final row in rows) {
        if (crypto.decryptText(row['Name']) == part) {
          currentId = _string(row['ID']);
          break;
        }
      }
      if (currentId == null) return null;
      parentId = currentId;
    }
    return currentId;
  }

  String _categoryParentId(String categoryId) {
    final rows = _db.select(
      'SELECT hex(ParentCategoryID) AS ParentCategoryID '
      'FROM spbwlt_Category WHERE ${_idEquals('ID')}',
      [_idArgument(categoryId)],
    );
    return rows.isEmpty ? '' : _string(rows.first['ParentCategoryID']);
  }

  List<String> _categoryDescendantIds(String categoryId) {
    final result = <String>[];
    void collect(String parentId) {
      final rows = _db.select(
        'SELECT hex(ID) AS ID FROM spbwlt_Category '
        'WHERE ${_idEquals('ParentCategoryID')}',
        [_idArgument(parentId)],
      );
      for (final row in rows) {
        final id = _string(row['ID']);
        result.add(id);
        collect(id);
      }
    }

    collect(categoryId);
    return result;
  }

  Map<String, String> _buildCategoryPaths(
    Map<String, SpbWalletCategoryRecord> categories,
  ) {
    final result = <String, String>{};
    final resolving = <String>{};

    String resolve(String categoryId) {
      if (categoryId.isEmpty) return '';
      final cached = result[categoryId];
      if (cached != null) return cached;
      final category = categories[categoryId];
      if (category == null || !resolving.add(categoryId)) return '';
      final parentPath = resolve(category.parentId);
      resolving.remove(categoryId);
      final name = category.name.trim();
      final path = parentPath.isEmpty
          ? name
          : name.isEmpty
              ? parentPath
              : '$parentPath$_categoryPathSeparator$name';
      result[categoryId] = path;
      return path;
    }

    for (final categoryId in categories.keys) {
      resolve(categoryId);
    }
    return result;
  }

  Set<String> _columns(String table) {
    return _db
        .select('PRAGMA table_info($table)')
        .map((row) => _string(row['name']))
        .toSet();
  }

  T runTransaction<T>(T Function() action) {
    if (_transactionDepth > 0) return action();
    _db.execute('BEGIN IMMEDIATE');
    _transactionDepth++;
    try {
      final result = action();
      _db.execute('COMMIT');
      return result;
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    } finally {
      _transactionDepth--;
    }
  }

  void _transaction(void Function() action) => runTransaction<void>(action);

  String _createCardView() {
    final id = _makeSpbId();
    _db.execute(
      'INSERT INTO spbwlt_CardView (ID, CardColor, CornerType, ShowHiddenFields, IconID, ImageID, ImgPosition, ShowCardBorder, FillCardWithColor) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        _idFromHex(id),
        Uint8List.fromList('16777215'.codeUnits),
        1,
        0,
        _idFromHex(defaultCardIconId),
        _idFromHex(_defaultImageId()),
        4,
        1,
        1,
      ],
    );
    return id;
  }

  void _saveCardColor(String cardId, int? cardColor) {
    if (cardColor == null) return;
    final rows = _db.select(
      'SELECT hex(CardViewID) AS CardViewID FROM spbwlt_Card '
      'WHERE ${_idEquals('ID')}',
      [_idArgument(cardId)],
    );
    if (rows.isEmpty) return;
    final cardViewId = _string(rows.first['CardViewID']);
    if (cardViewId.isEmpty) return;
    final viewRows = _db.select(
      'SELECT hex(ImageID) AS ImageID FROM spbwlt_CardView '
      'WHERE ${_idEquals('ID')}',
      [_idArgument(cardViewId)],
    );
    final hasBackgroundImage =
        viewRows.isNotEmpty && _string(viewRows.first['ImageID']).isNotEmpty;
    _db.execute(
      'UPDATE spbwlt_CardView SET CardColor = ?, FillCardWithColor = ? '
      'WHERE ${_idEquals('ID')}',
      [
        LegacySwlCodec.cardColor(cardColor),
        hasBackgroundImage ? 0 : 1,
        _idArgument(cardViewId),
      ],
    );
    _db.execute(
      'UPDATE spbwlt_Card SET HasOwnCardView = ? '
      'WHERE ${_idEquals('ID')}',
      [1, _idArgument(cardId)],
    );
  }

  void _saveCardIcon(String cardId, String iconId) {
    final rows = _db.select(
      'SELECT hex(CardViewID) AS CardViewID FROM spbwlt_Card '
      'WHERE ${_idEquals('ID')}',
      [_idArgument(cardId)],
    );
    if (rows.isEmpty) return;
    final cardViewId = _string(rows.first['CardViewID']);
    _db.execute(
      'UPDATE spbwlt_Card SET IconID = ?, HasOwnCardView = ? '
      'WHERE ${_idEquals('ID')}',
      [_idFromHex(iconId), 1, _idArgument(cardId)],
    );
    if (cardViewId.isNotEmpty) {
      _db.execute(
          'UPDATE spbwlt_CardView SET IconID = ? '
          'WHERE ${_idEquals('ID')}',
          [
            _idFromHex(iconId),
            _idArgument(cardViewId),
          ]);
    }
  }

  String _resolvedCardIconId(String? iconId, String templateId) {
    if (iconId != null && iconId.isNotEmpty) return iconId;
    final rows = _db.select(
      'SELECT hex(spbwlt_CardView.IconID) AS IconID '
      'FROM spbwlt_Template '
      'LEFT JOIN spbwlt_CardView '
      'ON ${_idJoin('spbwlt_CardView.ID', 'spbwlt_Template.CardViewID')} '
      'WHERE ${_idEquals('spbwlt_Template.ID')}',
      [_idArgument(templateId)],
    );
    if (rows.isNotEmpty) {
      final templateIconId = _string(rows.first['IconID']);
      if (templateIconId.isNotEmpty) return templateIconId;
    }
    return defaultCardIconId;
  }

  void _saveTemplateIcon(String templateId, String? iconId) {
    if (iconId == null || iconId.isEmpty) return;
    final rows = _db.select(
      'SELECT hex(CardViewID) AS CardViewID FROM spbwlt_Template '
      'WHERE ${_idEquals('ID')}',
      [_idArgument(templateId)],
    );
    if (rows.isEmpty) return;
    final cardViewId = _string(rows.first['CardViewID']);
    if (cardViewId.isEmpty) return;
    _db.execute(
        'UPDATE spbwlt_CardView SET IconID = ? '
        'WHERE ${_idEquals('ID')}',
        [
          _idFromHex(iconId),
          _idArgument(cardViewId),
        ]);
  }

  void _saveTemplateColor(String templateId, int? cardColor) {
    if (cardColor == null) return;
    final rows = _db.select(
      'SELECT hex(CardViewID) AS CardViewID FROM spbwlt_Template '
      'WHERE ${_idEquals('ID')}',
      [_idArgument(templateId)],
    );
    if (rows.isEmpty) return;
    final cardViewId = _string(rows.first['CardViewID']);
    if (cardViewId.isEmpty) return;
    _db.execute(
      'UPDATE spbwlt_CardView SET CardColor = ?, FillCardWithColor = 1 '
      'WHERE ${_idEquals('ID')}',
      [LegacySwlCodec.cardColor(cardColor), _idArgument(cardViewId)],
    );
  }

  void _saveEmbeddedIcon(SpbWalletTemplateDraft draft) {
    _saveEmbeddedIconData(
      draft.iconId,
      draft.iconBytes,
      draft.iconFileName ?? 'template-icon.png',
    );
  }

  void _saveEmbeddedIconData(
    String? iconId,
    List<int>? bytes,
    String fileName,
  ) {
    if (iconId == null || iconId.isEmpty || bytes == null || bytes.isEmpty) {
      return;
    }
    _embeddedIconCache = null;
    final icoBytes = LegacySwlCodec.embeddedIconIco(bytes);
    final dot = fileName.lastIndexOf('.');
    final legacyFileName =
        '${dot < 0 ? fileName : fileName.substring(0, dot)}.ico';
    final name = crypto.encryptText(legacyFileName);
    final data = attachmentCodec.encode(icoBytes);
    final exists = _db.select(
      'SELECT 1 FROM spbwlt_Icon WHERE ${_idEquals('ID')}',
      [_idArgument(iconId)],
    ).isNotEmpty;
    if (exists) {
      _db.execute(
        'UPDATE spbwlt_Icon SET Name = ?, Data = ? '
        'WHERE ${_idEquals('ID')}',
        [name, data, _idArgument(iconId)],
      );
    } else {
      _db.execute('INSERT INTO spbwlt_Icon (ID, Name, Data) VALUES (?, ?, ?)', [
        _idFromHex(iconId),
        name,
        data,
      ]);
    }
  }

  String _copyCardView(String sourceCardViewId) {
    if (sourceCardViewId.isEmpty) return _createCardView();
    final rows = _db.select(
      'SELECT CardColor, CornerType, ShowHiddenFields, hex(IconID) AS IconID, '
      'hex(ImageID) AS ImageID, ImgPosition, ShowCardBorder, '
      'FillCardWithColor FROM spbwlt_CardView '
      'WHERE ${_idEquals('ID')}',
      [_idArgument(sourceCardViewId)],
    );
    final id = _makeSpbId();
    if (rows.isEmpty) return _createCardView();
    final row = rows.first;
    _db.execute(
      'INSERT INTO spbwlt_CardView (ID, CardColor, CornerType, ShowHiddenFields, IconID, ImageID, ImgPosition, ShowCardBorder, FillCardWithColor) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        _idFromHex(id),
        row['CardColor'],
        row['CornerType'],
        row['ShowHiddenFields'],
        _idFromHex(_string(row['IconID'])),
        _idFromHex(_string(row['ImageID'])),
        row['ImgPosition'],
        row['ShowCardBorder'],
        row['FillCardWithColor'],
      ],
    );
    for (final field in _db.select(
      'SELECT hex(TemplateFieldID) AS TemplateFieldID, PositionX, PositionY, '
      'FontFamily, FontSize, FontColor, TextStyle, TextAlign, ShowFieldName '
      'FROM spbwlt_CardViewField WHERE ${_idEquals('CardViewID')}',
      [_idArgument(sourceCardViewId)],
    )) {
      _db.execute(
        'INSERT INTO spbwlt_CardViewField (ID, CardViewID, TemplateFieldID, PositionX, PositionY, FontFamily, FontSize, FontColor, TextStyle, TextAlign, ShowFieldName) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          _idFromHex(_makeSpbId()),
          _idFromHex(id),
          _idFromHex(_string(field['TemplateFieldID'])),
          field['PositionX'],
          field['PositionY'],
          field['FontFamily'],
          field['FontSize'],
          field['FontColor'],
          field['TextStyle'],
          field['TextAlign'],
          field['ShowFieldName'],
        ],
      );
    }
    return id;
  }

  void _createCardViewFieldForTemplateField(
    String templateId,
    String fieldId,
    int priority,
  ) {
    final rows = _db.select(
      'SELECT hex(CardViewID) AS CardViewID FROM spbwlt_Template '
      'WHERE ${_idEquals('ID')}',
      [_idArgument(templateId)],
    );
    if (rows.isEmpty) return;
    final cardViewId = _string(rows.first['CardViewID']);
    _db.execute(
      'INSERT INTO spbwlt_CardViewField (ID, CardViewID, TemplateFieldID, PositionX, PositionY, FontFamily, FontSize, FontColor, TextStyle, TextAlign, ShowFieldName) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        _idFromHex(_makeSpbId()),
        _idFromHex(cardViewId),
        _idFromHex(fieldId),
        12,
        18 + priority * 24,
        'Tahoma',
        12,
        '\u0000\u0000\u0000',
        0,
        0,
        1,
      ],
    );
  }

  String _defaultImageId() {
    final rows = _db.select(
      'SELECT hex(ImageID) AS ID FROM spbwlt_CardView WHERE length(ImageID) > 0 LIMIT 1',
    );
    return rows.isEmpty ? '' : _string(rows.first['ID']);
  }

  String _defaultTemplateId() {
    final rows = _db.select(
      'SELECT hex(ID) AS ID FROM spbwlt_Template LIMIT 1',
    );
    return rows.isEmpty ? '' : _string(rows.first['ID']);
  }

  static String _string(Object? value) => value == null ? '' : value.toString();

  static int _cardColorToInt(Object? value) {
    if (value == null) return 0xffffff;
    if (value is int) return value & 0xffffff;
    if (value is Uint8List) {
      return int.tryParse(String.fromCharCodes(value).trim()) ?? 0xffffff;
    }
    if (value is List<int>) {
      return int.tryParse(String.fromCharCodes(value).trim()) ?? 0xffffff;
    }
    return int.tryParse(value.toString().trim()) ?? 0xffffff;
  }

  static Object _idFromHex(String hex) {
    final bytes = LegacySwlCodec.idBytes(hex);
    try {
      return utf8.decode(bytes, allowMalformed: false);
    } on FormatException {
      return bytes;
    }
  }

  String _idEquals(String column) =>
      _directIdLookups ? '$column = ?' : 'hex($column) = ?';

  Object _idArgument(String hex) => _directIdLookups ? _idFromHex(hex) : hex;

  String _idJoin(String left, String right) =>
      _directIdLookups ? '$left = $right' : 'hex($left) = hex($right)';

  static String _makeSpbId() {
    return LegacySwlCodec.makeHexId();
  }
}

class SpbWalletSnapshot {
  const SpbWalletSnapshot({
    required this.templates,
    required this.cards,
    required this.categories,
    this.embeddedIconPngs = const {},
    this.cardLoadFailures = const [],
    this.loadReport = const WalletLoadReport([]),
  });

  final List<SpbWalletTemplateRecord> templates;
  final List<SpbWalletCardRecord> cards;
  final List<SpbWalletCategoryRecord> categories;
  final Map<String, Uint8List> embeddedIconPngs;
  final List<SpbWalletCardLoadFailure> cardLoadFailures;
  final WalletLoadReport loadReport;
}

enum WalletLoadIssueKind { card, field, attachment, category, template, icon }

class WalletLoadIssue {
  const WalletLoadIssue({
    required this.kind,
    required this.entityId,
    required this.reason,
  });

  final WalletLoadIssueKind kind;
  final String entityId;
  final String reason;
}

class WalletLoadReport {
  const WalletLoadReport(this.issues);

  final List<WalletLoadIssue> issues;
  bool get hasIssues => issues.isNotEmpty;
  int count(WalletLoadIssueKind kind) =>
      issues.where((issue) => issue.kind == kind).length;
}

class SpbWalletCardLoadFailure {
  const SpbWalletCardLoadFailure({required this.cardId, required this.reason});

  final String cardId;
  final String reason;
}

class SpbWalletTemplateRecord {
  const SpbWalletTemplateRecord({
    required this.id,
    required this.name,
    required this.iconId,
    this.cardColor = 0xffffff,
    this.categoryPath = '',
    required this.fields,
  });

  final String id;
  final String name;
  final String iconId;
  final int cardColor;
  final String categoryPath;
  final List<SpbWalletTemplateFieldRecord> fields;
}

class SpbWalletTemplateFieldRecord {
  const SpbWalletTemplateFieldRecord({
    required this.id,
    required this.name,
    required this.templateId,
    this.fieldTypeId = 1,
  });

  final String id;
  final String name;
  final String templateId;
  final int fieldTypeId;
}

class SpbWalletTemplateDraft {
  const SpbWalletTemplateDraft({
    required this.id,
    required this.name,
    required this.fields,
    this.iconId,
    this.cardColor,
    this.categoryPath = '',
    this.iconBytes,
    this.iconFileName,
  });

  final String id;
  final String name;
  final List<SpbWalletTemplateFieldRecord> fields;
  final String? iconId;
  final int? cardColor;
  final String categoryPath;
  final List<int>? iconBytes;
  final String? iconFileName;
}

class SpbWalletCardRecord {
  const SpbWalletCardRecord({
    required this.id,
    required this.title,
    required this.description,
    required this.categoryPath,
    required this.templateId,
    required this.fieldValues,
    required this.attachments,
    required this.hitCount,
    required this.iconId,
    required this.cardColor,
    this.backgroundImageBase64,
    this.fieldOrder = const [],
    this.hiddenFieldIds = const {},
    this.modifiedAt,
  });

  final String id;
  final String title;
  final String description;
  final String categoryPath;
  final String templateId;
  final Map<String, String> fieldValues;
  final List<SpbWalletAttachmentRecord> attachments;
  final int hitCount;
  final String iconId;
  final int cardColor;
  final String? backgroundImageBase64;
  final List<String> fieldOrder;
  final Set<String> hiddenFieldIds;
  final DateTime? modifiedAt;
}

class SpbWalletCardDraft {
  const SpbWalletCardDraft({
    required this.id,
    required this.title,
    required this.description,
    required this.categoryPath,
    required this.templateId,
    required this.fieldValues,
    this.iconId,
    this.iconBytes,
    this.iconFileName,
    this.cardColor,
    this.backgroundImageBase64,
    this.preserveExistingDescriptionWhenEmpty = false,
    this.fieldOrder = const [],
    this.hiddenFieldIds = const {},
    this.modifiedAt,
  });

  final String id;
  final String title;
  final String description;
  final String categoryPath;
  final String templateId;
  final Map<String, String> fieldValues;
  final String? iconId;
  final List<int>? iconBytes;
  final String? iconFileName;
  final int? cardColor;
  final String? backgroundImageBase64;
  final bool preserveExistingDescriptionWhenEmpty;
  final List<String> fieldOrder;
  final Set<String> hiddenFieldIds;
  final DateTime? modifiedAt;
}

class SpbWalletAttachmentDraft {
  const SpbWalletAttachmentDraft({
    required this.fileName,
    required this.bytes,
    this.id,
  });

  final String? id;
  final String fileName;
  final List<int> bytes;
}

class SpbWalletAttachmentRecord {
  const SpbWalletAttachmentRecord({
    required this.id,
    required this.cardId,
    required this.fileName,
    required this.size,
    this.decodeError,
  });

  final String id;
  final String cardId;
  final String fileName;
  final int size;
  final String? decodeError;
}

class SpbWalletCategoryRecord {
  const SpbWalletCategoryRecord({
    required this.id,
    required this.name,
    required this.parentId,
    required this.iconId,
    this.colorId = '',
  });

  final String id;
  final String name;
  final String parentId;
  final String iconId;
  final String colorId;
}

class SpbWalletOpenException implements Exception {
  const SpbWalletOpenException(this.message);

  final String message;

  @override
  String toString() => message;
}
