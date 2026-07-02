import 'dart:math';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

import 'spb_wallet_attachment_codec.dart';
import 'spb_wallet_crypto.dart';

class SpbWalletDatabase {
  SpbWalletDatabase._(this.path, this._db, this.crypto)
      : attachmentCodec = SpbWalletAttachmentCodec(crypto);

  final String path;
  final Database _db;
  final SpbWalletCrypto crypto;
  final SpbWalletAttachmentCodec attachmentCodec;

  static SpbWalletDatabase open(String path, String password) {
    try {
      final db = sqlite3.open(path);
      final wallet = SpbWalletDatabase._(path, db, SpbWalletCrypto(password));
      wallet._validateSchema();
      wallet._validatePassword();
      return wallet;
    } on SqliteException catch (error) {
      throw SpbWalletOpenException('Не удалось открыть SQLite базу SPB Wallet: ${error.message}');
    } on SpbWalletCryptoException catch (error) {
      throw SpbWalletOpenException(error.message);
    }
  }

  static String makeId() => _makeSpbId();

  SpbWalletSnapshot loadSnapshot() {
    final categories = _loadCategories();
    final templates = _loadTemplates();
    final cards = <SpbWalletCardRecord>[];

    for (final row in _db.select('SELECT hex(ID) AS ID, Name, Description, hex(ParentCategoryID) AS ParentCategoryID, hex(TemplateID) AS TemplateID, HitCount FROM spbwlt_Card')) {
      final id = _string(row['ID']);
      final templateId = _string(row['TemplateID']);
      final values = <String, String>{};
      for (final fieldRow in _db.select(
        'SELECT hex(TemplateFieldID) AS TemplateFieldID, ValueString FROM spbwlt_CardFieldValue WHERE hex(CardID) = ?',
        [id],
      )) {
        values[_string(fieldRow['TemplateFieldID'])] = crypto.decryptText(fieldRow['ValueString']);
      }
      cards.add(
        SpbWalletCardRecord(
          id: id,
          title: crypto.decryptText(row['Name']),
          description: crypto.decryptText(row['Description']),
          categoryPath: _categoryPath(categories, _string(row['ParentCategoryID'])),
          templateId: templateId,
          fieldValues: values,
          attachments: loadAttachments(id),
          hitCount: (row['HitCount'] as int?) ?? 0,
        ),
      );
    }

    return SpbWalletSnapshot(templates: templates, cards: cards);
  }

  List<SpbWalletAttachmentRecord> loadAttachments(String cardId) {
    return _db
        .select('SELECT hex(ID) AS ID, hex(CardID) AS CardID, Name, Data FROM spbwlt_CardAttachment WHERE hex(CardID) = ?', [cardId])
        .map((row) {
      var size = -1;
      String? error;
      try {
        size = attachmentCodec.decode(row['Data']).bytes.length;
      } catch (exception) {
        error = exception.toString();
      }
      return SpbWalletAttachmentRecord(
        id: _string(row['ID']),
        cardId: _string(row['CardID']),
        fileName: crypto.decryptText(row['Name']),
        size: size,
        decodeError: error,
      );
    }).toList();
  }

  Uint8List readAttachmentBytes(String attachmentId) {
    final rows = _db.select('SELECT Data FROM spbwlt_CardAttachment WHERE hex(ID) = ?', [attachmentId]);
    if (rows.isEmpty) throw const SpbWalletOpenException('Вложение SPB Wallet не найдено.');
    return attachmentCodec.decode(rows.first['Data']).bytes;
  }

  void saveTemplate(SpbWalletTemplateDraft draft) {
    _transaction(() {
      final templateExists = _db.select('SELECT 1 FROM spbwlt_Template WHERE hex(ID) = ?', [draft.id]).isNotEmpty;
      if (templateExists) {
        _db.execute('UPDATE spbwlt_Template SET Name = ? WHERE hex(ID) = ?', [crypto.encryptText(draft.name), draft.id]);
      } else {
        final cardViewId = _createCardView();
        _db.execute(
          'INSERT INTO spbwlt_Template (ID, Name, Description, CardViewID) VALUES (?, ?, ?, ?)',
          [_idFromHex(draft.id), crypto.encryptText(draft.name), null, _idFromHex(cardViewId)],
        );
      }
      final existingIds = _db
          .select('SELECT hex(ID) AS ID FROM spbwlt_TemplateField WHERE hex(TemplateID) = ?', [draft.id])
          .map((row) => _string(row['ID']))
          .toSet();
      var priority = 0;
      for (final field in draft.fields) {
        final encryptedName = crypto.encryptText(field.name);
        if (existingIds.contains(field.id)) {
          _db.execute(
            'UPDATE spbwlt_TemplateField SET Name = ?, FieldTypeID = ?, Priority = ? WHERE hex(ID) = ?',
            [encryptedName, field.fieldTypeId, priority, field.id],
          );
        } else {
          _db.execute(
            'INSERT INTO spbwlt_TemplateField (ID, Name, TemplateID, FieldTypeID, Priority) VALUES (?, ?, ?, ?, ?)',
            [_idFromHex(field.id), encryptedName, _idFromHex(draft.id), field.fieldTypeId, priority],
          );
          _createCardViewFieldForTemplateField(draft.id, field.id, priority);
        }
        priority++;
      }
    });
  }

  void saveCard(SpbWalletCardDraft draft) {
    _transaction(() {
      final categoryId = _ensureCategoryPath(draft.categoryPath);
      final description = draft.description.trim().isEmpty ? null : crypto.encryptText(draft.description);
      final exists = _db.select('SELECT 1 FROM spbwlt_Card WHERE hex(ID) = ?', [draft.id]).isNotEmpty;
      if (exists) {
        _db.execute(
          'UPDATE spbwlt_Card SET Name = ?, Description = ?, ParentCategoryID = ?, TemplateID = ? WHERE hex(ID) = ?',
          [crypto.encryptText(draft.title), description, _idFromHex(categoryId), _idFromHex(draft.templateId), draft.id],
        );
      } else {
        final templateRows = _db.select('SELECT hex(CardViewID) AS CardViewID FROM spbwlt_Template WHERE hex(ID) = ?', [draft.templateId]);
        final templateCardViewId = templateRows.isEmpty ? '' : _string(templateRows.first['CardViewID']);
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
            _idFromHex(_defaultIconId()),
          ],
        );
      }

      final existingValues = <String, String>{};
      for (final row in _db.select('SELECT hex(ID) AS ID, hex(TemplateFieldID) AS TemplateFieldID FROM spbwlt_CardFieldValue WHERE hex(CardID) = ?', [draft.id])) {
        existingValues[_string(row['TemplateFieldID'])] = _string(row['ID']);
      }
      for (final entry in draft.fieldValues.entries) {
        final valueId = existingValues[entry.key];
        if (valueId == null) {
          _db.execute(
            'INSERT INTO spbwlt_CardFieldValue (ID, CardID, TemplateFieldID, ValueString) VALUES (?, ?, ?, ?)',
            [_idFromHex(_makeSpbId()), _idFromHex(draft.id), _idFromHex(entry.key), crypto.encryptText(entry.value)],
          );
        } else {
          _db.execute(
            'UPDATE spbwlt_CardFieldValue SET ValueString = ? WHERE hex(ID) = ?',
            [crypto.encryptText(entry.value), valueId],
          );
        }
      }
    });
  }

  void deleteCard(String cardId) {
    _transaction(() {
      _db.execute('DELETE FROM spbwlt_Card WHERE hex(ID) = ?', [cardId]);
    });
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
          _db.select('SELECT 1 FROM spbwlt_CardAttachment WHERE hex(ID) = ?', [attachmentId]).isNotEmpty) {
        _db.execute('UPDATE spbwlt_CardAttachment SET Name = ?, Data = ? WHERE hex(ID) = ?', [name, data, attachmentId]);
      } else {
        _db.execute(
          'INSERT INTO spbwlt_CardAttachment (ID, CardID, Name, Data) VALUES (?, ?, ?, ?)',
          [_idFromHex(attachmentId ?? _makeSpbId()), _idFromHex(cardId), name, data],
        );
      }
    });
  }

  void deleteAttachment(String attachmentId) {
    _db.execute('DELETE FROM spbwlt_CardAttachment WHERE hex(ID) = ?', [attachmentId]);
  }

  void recordCardHit(String cardId) {
    _db.execute('UPDATE spbwlt_Card SET HitCount = HitCount + 1 WHERE hex(ID) = ?', [cardId]);
  }

  void close() {
    _db.dispose();
  }

  void _validateSchema() {
    final required = {
      'spbwlt_Category': ['ID', 'Name', 'ParentCategoryID'],
      'spbwlt_Card': ['ID', 'Name', 'Description', 'ParentCategoryID', 'TemplateID'],
      'spbwlt_CardFieldValue': ['ID', 'CardID', 'TemplateFieldID', 'ValueString'],
      'spbwlt_TemplateField': ['ID', 'Name', 'TemplateID'],
      'spbwlt_CardAttachment': ['ID', 'CardID', 'Name', 'Data'],
    };
    for (final entry in required.entries) {
      final columns = _columns(entry.key);
      if (columns.isEmpty) {
        throw SpbWalletOpenException('В файле нет таблицы ${entry.key}. Это не поддерживаемая база SPB Wallet.');
      }
      for (final column in entry.value) {
        if (!columns.contains(column)) {
          throw SpbWalletOpenException('В таблице ${entry.key} нет колонки $column.');
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
      final rows = _db.select('SELECT ${tableAndColumn[1]} AS value FROM ${tableAndColumn[0]} LIMIT 3');
      samples.addAll(rows.map((row) => row['value']));
    }
    if (samples.isEmpty) return;
    if (!samples.any(crypto.looksLikeValidText)) {
      throw const SpbWalletOpenException('Пароль SPB Wallet не подходит или база повреждена.');
    }
  }

  Map<String, SpbWalletCategoryRecord> _loadCategories() {
    final result = <String, SpbWalletCategoryRecord>{};
    for (final row in _db.select('SELECT hex(ID) AS ID, Name, hex(ParentCategoryID) AS ParentCategoryID FROM spbwlt_Category')) {
      final id = _string(row['ID']);
      result[id] = SpbWalletCategoryRecord(
        id: id,
        name: crypto.decryptText(row['Name']),
        parentId: _string(row['ParentCategoryID']),
      );
    }
    return result;
  }

  List<SpbWalletTemplateRecord> _loadTemplates() {
    final fields = _loadTemplateFields();
    final byTemplate = <String, List<SpbWalletTemplateFieldRecord>>{};
    for (final field in fields) {
      byTemplate.putIfAbsent(field.templateId, () => []).add(field);
    }
    final templates = <SpbWalletTemplateRecord>[];
    for (final row in _db.select('SELECT hex(ID) AS ID, Name FROM spbwlt_Template')) {
      final id = _string(row['ID']);
      templates.add(
        SpbWalletTemplateRecord(
          id: id,
          name: crypto.decryptText(row['Name']),
          fields: byTemplate[id] ?? const [],
        ),
      );
    }
    return templates;
  }

  List<SpbWalletTemplateFieldRecord> _loadTemplateFields() {
    return _db.select('SELECT hex(ID) AS ID, Name, hex(TemplateID) AS TemplateID, FieldTypeID, Priority FROM spbwlt_TemplateField ORDER BY hex(TemplateID), Priority').map((row) {
      return SpbWalletTemplateFieldRecord(
        id: _string(row['ID']),
        name: crypto.decryptText(row['Name']),
        templateId: _string(row['TemplateID']),
        fieldTypeId: (row['FieldTypeID'] as int?) ?? 1,
      );
    }).toList();
  }

  String _ensureCategoryPath(String path) {
    final cleanParts = path
        .split('/')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    if (cleanParts.isEmpty) return '';

    var parentId = '';
    for (final part in cleanParts) {
      final rows = _db.select('SELECT hex(ID) AS ID, Name FROM spbwlt_Category WHERE hex(ParentCategoryID) = ?', [parentId]);
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
            _idFromHex(_defaultIconId()),
            _idFromHex(_defaultTemplateId()),
            _idFromHex(parentId),
          ],
        );
      }
      parentId = found;
    }
    return parentId;
  }

  String _categoryPath(Map<String, SpbWalletCategoryRecord> categories, String categoryId) {
    if (categoryId.isEmpty || !categories.containsKey(categoryId)) return '';
    final names = <String>[];
    var current = categories[categoryId];
    var guard = 0;
    while (current != null && guard++ < 64) {
      if (current.name.isNotEmpty) names.add(current.name);
      current = categories[current.parentId];
    }
    return names.reversed.join(' / ');
  }

  Set<String> _columns(String table) {
    return _db.select('PRAGMA table_info($table)').map((row) => _string(row['name'])).toSet();
  }

  void _transaction(void Function() action) {
    _db.execute('BEGIN IMMEDIATE');
    try {
      action();
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  String _createCardView() {
    final id = _makeSpbId();
    _db.execute(
      'INSERT INTO spbwlt_CardView (ID, CardColor, CornerType, ShowHiddenFields, IconID, ImageID, ImgPosition, ShowCardBorder, FillCardWithColor) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        _idFromHex(id),
        Uint8List.fromList('16777215'.codeUnits),
        1,
        0,
        _idFromHex(_defaultIconId()),
        _idFromHex(_defaultImageId()),
        4,
        1,
        1,
      ],
    );
    return id;
  }

  String _copyCardView(String sourceCardViewId) {
    if (sourceCardViewId.isEmpty) return _createCardView();
    final rows = _db.select(
      'SELECT CardColor, CornerType, ShowHiddenFields, hex(IconID) AS IconID, hex(ImageID) AS ImageID, ImgPosition, ShowCardBorder, FillCardWithColor FROM spbwlt_CardView WHERE hex(ID) = ?',
      [sourceCardViewId],
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
    for (final field in _db.select('SELECT hex(TemplateFieldID) AS TemplateFieldID, PositionX, PositionY, FontFamily, FontSize, FontColor, TextStyle, TextAlign, ShowFieldName FROM spbwlt_CardViewField WHERE hex(CardViewID) = ?', [sourceCardViewId])) {
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

  void _createCardViewFieldForTemplateField(String templateId, String fieldId, int priority) {
    final rows = _db.select('SELECT hex(CardViewID) AS CardViewID FROM spbwlt_Template WHERE hex(ID) = ?', [templateId]);
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

  String _defaultIconId() {
    final cardRows = _db.select('SELECT hex(IconID) AS ID FROM spbwlt_Card WHERE length(IconID) > 0 LIMIT 1');
    if (cardRows.isNotEmpty) return _string(cardRows.first['ID']);
    final viewRows = _db.select('SELECT hex(IconID) AS ID FROM spbwlt_CardView WHERE length(IconID) > 0 LIMIT 1');
    if (viewRows.isNotEmpty) return _string(viewRows.first['ID']);
    return '';
  }

  String _defaultImageId() {
    final rows = _db.select('SELECT hex(ImageID) AS ID FROM spbwlt_CardView WHERE length(ImageID) > 0 LIMIT 1');
    return rows.isEmpty ? '' : _string(rows.first['ID']);
  }

  String _defaultTemplateId() {
    final rows = _db.select('SELECT hex(ID) AS ID FROM spbwlt_Template LIMIT 1');
    return rows.isEmpty ? '' : _string(rows.first['ID']);
  }

  static String _string(Object? value) => value == null ? '' : value.toString();

  static Uint8List _idFromHex(String hex) {
    if (hex.isEmpty) return Uint8List(0);
    final result = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < result.length; i++) {
      result[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return result;
  }

  static String _makeSpbId() {
    final random = Random.secure();
    const alphabet = '0123456789abcdef';
    return List.generate(16, (_) => alphabet[random.nextInt(alphabet.length)]).join().toUpperCase();
  }
}

class SpbWalletSnapshot {
  const SpbWalletSnapshot({required this.templates, required this.cards});

  final List<SpbWalletTemplateRecord> templates;
  final List<SpbWalletCardRecord> cards;
}

class SpbWalletTemplateRecord {
  const SpbWalletTemplateRecord({required this.id, required this.name, required this.fields});

  final String id;
  final String name;
  final List<SpbWalletTemplateFieldRecord> fields;
}

class SpbWalletTemplateFieldRecord {
  const SpbWalletTemplateFieldRecord({required this.id, required this.name, required this.templateId, this.fieldTypeId = 1});

  final String id;
  final String name;
  final String templateId;
  final int fieldTypeId;
}

class SpbWalletTemplateDraft {
  const SpbWalletTemplateDraft({required this.id, required this.name, required this.fields});

  final String id;
  final String name;
  final List<SpbWalletTemplateFieldRecord> fields;
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
  });

  final String id;
  final String title;
  final String description;
  final String categoryPath;
  final String templateId;
  final Map<String, String> fieldValues;
  final List<SpbWalletAttachmentRecord> attachments;
  final int hitCount;
}

class SpbWalletCardDraft {
  const SpbWalletCardDraft({
    required this.id,
    required this.title,
    required this.description,
    required this.categoryPath,
    required this.templateId,
    required this.fieldValues,
  });

  final String id;
  final String title;
  final String description;
  final String categoryPath;
  final String templateId;
  final Map<String, String> fieldValues;
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
  const SpbWalletCategoryRecord({required this.id, required this.name, required this.parentId});

  final String id;
  final String name;
  final String parentId;
}

class SpbWalletOpenException implements Exception {
  const SpbWalletOpenException(this.message);

  final String message;

  @override
  String toString() => message;
}
