import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';

import 'spb_wallet/spb_wallet_database.dart';

void main() {
  runApp(const ActitPassApp());
}

class ActitPassApp extends StatelessWidget {
  const ActitPassApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ActitPassStorage',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff2d6f73),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xfff5f7f8),
        visualDensity: VisualDensity.standard,
      ),
      home: const VaultShell(),
    );
  }
}

class PaletteColor {
  const PaletteColor(this.id, this.label, this.bg, this.fg);

  final String id;
  final String label;
  final Color bg;
  final Color fg;
}

class TemplateIcon {
  const TemplateIcon(this.id, this.label, this.symbol);

  final String id;
  final String label;
  final String symbol;
}

class FieldDefinition {
  const FieldDefinition({
    required this.id,
    required this.label,
    required this.type,
    this.required = false,
    this.secret = false,
  });

  final String id;
  final String label;
  final String type;
  final bool required;
  final bool secret;

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'type': type,
        'required': required,
        'secret': secret,
      };

  factory FieldDefinition.fromJson(Map<String, dynamic> json) => FieldDefinition(
        id: json['id'] as String,
        label: json['label'] as String,
        type: json['type'] as String,
        required: json['required'] == true,
        secret: json['secret'] == true,
      );
}

class CardTemplate {
  const CardTemplate({
    required this.id,
    required this.name,
    required this.iconId,
    required this.colorId,
    required this.fields,
    this.builtIn = false,
  });

  final String id;
  final String name;
  final String iconId;
  final String colorId;
  final List<FieldDefinition> fields;
  final bool builtIn;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'iconId': iconId,
        'colorId': colorId,
        'builtIn': builtIn,
        'fields': fields.map((field) => field.toJson()).toList(),
      };

  factory CardTemplate.fromJson(Map<String, dynamic> json) => CardTemplate(
        id: json['id'] as String,
        name: json['name'] as String,
        iconId: json['iconId'] as String,
        colorId: json['colorId'] as String,
        builtIn: json['builtIn'] == true,
        fields: (json['fields'] as List<dynamic>)
            .map((field) => FieldDefinition.fromJson(field as Map<String, dynamic>))
            .toList(),
      );
}

class SecretItem {
  const SecretItem({
    required this.id,
    required this.templateId,
    required this.title,
    required this.category,
    required this.colorId,
    required this.values,
    required this.modifiedAt,
    this.attachments = const [],
    this.hitCount = 0,
  });

  final String id;
  final String templateId;
  final String title;
  final String category;
  final String colorId;
  final Map<String, String> values;
  final DateTime modifiedAt;
  final List<SecretAttachment> attachments;
  final int hitCount;

  Map<String, dynamic> toJson() => {
        'id': id,
        'templateId': templateId,
        'title': title,
        'category': category,
        'colorId': colorId,
        'values': values,
        'modifiedAt': modifiedAt.toIso8601String(),
        'attachments': attachments.map((attachment) => attachment.toJson()).toList(),
        'hitCount': hitCount,
      };

  factory SecretItem.fromJson(Map<String, dynamic> json) => SecretItem(
        id: json['id'] as String,
        templateId: json['templateId'] as String,
        title: json['title'] as String,
        category: json['category'] as String? ?? '',
        colorId: json['colorId'] as String? ?? 'neutral',
        values: Map<String, String>.from(json['values'] as Map<dynamic, dynamic>),
        modifiedAt: DateTime.parse(json['modifiedAt'] as String),
        attachments: (json['attachments'] as List<dynamic>? ?? [])
            .map((attachment) => SecretAttachment.fromJson(attachment as Map<String, dynamic>))
            .toList(),
        hitCount: json['hitCount'] as int? ?? 0,
      );
}

class SecretAttachment {
  const SecretAttachment({
    required this.id,
    required this.fileName,
    required this.size,
    this.decodeError,
    this.pendingBytes,
    this.deleted = false,
  });

  final String id;
  final String fileName;
  final int size;
  final String? decodeError;
  final List<int>? pendingBytes;
  final bool deleted;

  SecretAttachment copyWith({
    String? id,
    String? fileName,
    int? size,
    String? decodeError,
    List<int>? pendingBytes,
    bool? deleted,
  }) =>
      SecretAttachment(
        id: id ?? this.id,
        fileName: fileName ?? this.fileName,
        size: size ?? this.size,
        decodeError: decodeError,
        pendingBytes: pendingBytes ?? this.pendingBytes,
        deleted: deleted ?? this.deleted,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'fileName': fileName,
        'size': size,
        'decodeError': decodeError,
      };

  factory SecretAttachment.fromJson(Map<String, dynamic> json) => SecretAttachment(
        id: json['id'] as String,
        fileName: json['fileName'] as String,
        size: json['size'] as int? ?? -1,
        decodeError: json['decodeError'] as String?,
      );
}

class CategoryTreeNode {
  CategoryTreeNode(this.name);

  final String name;
  final Map<String, CategoryTreeNode> children = {};
  final List<SecretItem> cards = [];

  bool get isEmpty => children.isEmpty && cards.isEmpty;
}

abstract class VaultSession {
  Future<void> load();
  Future<void> saveItem(SecretItem item);
  Future<void> deleteItem(String itemId);
  Future<void> saveTemplate(CardTemplate template);
  Future<void> saveAttachment(String itemId, SecretAttachment attachment);
  Future<void> close();
}

class ActitPassJsonSession implements VaultSession {
  ActitPassJsonSession({required this.file, required this.password});

  final File file;
  final String password;
  List<CardTemplate> templates = [];
  List<SecretItem> items = [];
  List<ConflictRecord> conflicts = [];

  @override
  Future<void> load() async {
    final raw = await file.readAsString();
    final json = jsonDecode(utf8.decode(base64.decode(raw))) as Map<String, dynamic>;
    templates = (json['templates'] as List<dynamic>)
        .map((template) => CardTemplate.fromJson(template as Map<String, dynamic>))
        .toList();
    items = (json['items'] as List<dynamic>)
        .map((item) => SecretItem.fromJson(item as Map<String, dynamic>))
        .toList();
    conflicts = (json['conflicts'] as List<dynamic>? ?? [])
        .map((conflict) => ConflictRecord.fromJson(conflict as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> saveItem(SecretItem item) async {
    items = [...items.where((entry) => entry.id != item.id), item];
    await _persist();
  }

  @override
  Future<void> deleteItem(String itemId) async {
    items = items.where((item) => item.id != itemId).toList();
    await _persist();
  }

  @override
  Future<void> saveTemplate(CardTemplate template) async {
    templates = [...templates.where((entry) => entry.id != template.id), template];
    await _persist();
  }

  @override
  Future<void> saveAttachment(String itemId, SecretAttachment attachment) async {
    items = items.map((item) {
      if (item.id != itemId) return item;
      return SecretItem(
        id: item.id,
        templateId: item.templateId,
        title: item.title,
        category: item.category,
        colorId: item.colorId,
        values: item.values,
        modifiedAt: DateTime.now(),
        attachments: [...item.attachments.where((entry) => entry.id != attachment.id), attachment],
        hitCount: item.hitCount,
      );
    }).toList();
    await _persist();
  }

  @override
  Future<void> close() async {}

  Future<void> _persist() async {
    final payload = {
      'format': 'actitpass-flutter-alpha',
      'passwordHash': _passwordHash(password),
      'templates': templates.map((template) => template.toJson()).toList(),
      'items': items.map((item) => item.toJson()).toList(),
      'conflicts': conflicts.map((conflict) => conflict.toJson()).toList(),
    };
    await file.writeAsString(base64.encode(utf8.encode(jsonEncode(payload))));
  }

  static String _passwordHash(String password) {
    var hash = 2166136261;
    for (final codeUnit in password.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 16777619) & 0xffffffff;
    }
    return hash.toRadixString(16);
  }
}

class SpbWalletSession implements VaultSession {
  SpbWalletSession(this.database);

  final SpbWalletDatabase database;
  late SpbWalletSnapshot snapshot;

  @override
  Future<void> load() async {
    snapshot = database.loadSnapshot();
  }

  @override
  Future<void> saveItem(SecretItem item) async {
    database.saveCard(
      SpbWalletCardDraft(
        id: item.id,
        title: item.title,
        description: item.values[spbDescriptionFieldId] ?? '',
        categoryPath: item.category,
        templateId: item.templateId,
        fieldValues: {
          for (final entry in item.values.entries)
            if (entry.key != spbDescriptionFieldId) entry.key: entry.value,
        },
      ),
    );
    await load();
  }

  @override
  Future<void> deleteItem(String itemId) async {
    database.deleteCard(itemId);
    await load();
  }

  @override
  Future<void> saveTemplate(CardTemplate template) async {
    database.saveTemplate(
      SpbWalletTemplateDraft(
        id: template.id,
        name: template.name,
        fields: template.fields
            .where((field) => field.id != spbDescriptionFieldId)
            .map((field) => SpbWalletTemplateFieldRecord(id: field.id, name: field.label, templateId: template.id, fieldTypeId: spbFieldTypeId(field)))
            .toList(),
      ),
    );
    await load();
  }

  @override
  Future<void> saveAttachment(String itemId, SecretAttachment attachment) async {
    final bytes = attachment.pendingBytes;
    if (attachment.deleted && attachment.id.isNotEmpty) {
      database.deleteAttachment(attachment.id);
    } else if (bytes != null) {
      database.saveAttachment(
        cardId: itemId,
        attachmentId: attachment.id.isEmpty ? null : attachment.id,
        fileName: attachment.fileName,
        bytes: bytes,
      );
    }
    await load();
  }

  @override
  Future<void> close() async {
    database.close();
  }
}

class ConflictRecord {
  const ConflictRecord({
    required this.id,
    required this.title,
    required this.description,
    required this.createdAt,
    this.reviewed = false,
  });

  final String id;
  final String title;
  final String description;
  final DateTime createdAt;
  final bool reviewed;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'createdAt': createdAt.toIso8601String(),
        'reviewed': reviewed,
      };

  factory ConflictRecord.fromJson(Map<String, dynamic> json) => ConflictRecord(
        id: json['id'] as String,
        title: json['title'] as String,
        description: json['description'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        reviewed: json['reviewed'] == true,
      );
}

const palette = [
  PaletteColor('neutral', 'Серый', Color(0xffe7eaee), Color(0xff222831)),
  PaletteColor('blue', 'Синий', Color(0xffd9e6f6), Color(0xff17375f)),
  PaletteColor('green', 'Зеленый', Color(0xffdcebdc), Color(0xff1f4d32)),
  PaletteColor('teal', 'Бирюзовый', Color(0xffd8eceb), Color(0xff1f5052)),
  PaletteColor('violet', 'Фиолетовый', Color(0xffe6def0), Color(0xff4a3568)),
  PaletteColor('red', 'Красный', Color(0xfff2dddc), Color(0xff6a2b2b)),
  PaletteColor('amber', 'Янтарный', Color(0xfff3e7ca), Color(0xff5d4318)),
];

const templateIcons = [
  TemplateIcon('key', 'Ключ', '🔑'),
  TemplateIcon('note', 'Заметка', '📝'),
  TemplateIcon('card', 'Банковская карта', '💳'),
  TemplateIcon('id', 'Документ', '🪪'),
  TemplateIcon('server', 'Сервер', '🖥️'),
  TemplateIcon('license', 'Лицензия', '🏷️'),
  TemplateIcon('wifi', 'Wi-Fi', '📶'),
  TemplateIcon('bank', 'Банк', '🏦'),
  TemplateIcon('mail', 'Почта', '✉️'),
  TemplateIcon('shield', 'Защита', '🛡️'),
];

List<CardTemplate> builtInTemplates() => const [
      CardTemplate(
        id: 'tpl_password',
        name: 'Пароль',
        iconId: 'key',
        colorId: 'blue',
        builtIn: true,
        fields: [
          FieldDefinition(id: 'username', label: 'Логин', type: 'username'),
          FieldDefinition(id: 'password', label: 'Пароль', type: 'password', required: true, secret: true),
          FieldDefinition(id: 'url', label: 'Сайт', type: 'url'),
          FieldDefinition(id: 'notes', label: 'Заметки', type: 'multiline_note'),
        ],
      ),
      CardTemplate(
        id: 'tpl_note',
        name: 'Защищенная заметка',
        iconId: 'note',
        colorId: 'neutral',
        builtIn: true,
        fields: [
          FieldDefinition(id: 'note', label: 'Текст заметки', type: 'multiline_note', required: true),
        ],
      ),
      CardTemplate(
        id: 'tpl_payment_card',
        name: 'Банковская карта',
        iconId: 'card',
        colorId: 'teal',
        builtIn: true,
        fields: [
          FieldDefinition(id: 'holder', label: 'Владелец карты', type: 'text'),
          FieldDefinition(id: 'number', label: 'Номер карты', type: 'custom_secret', required: true),
          FieldDefinition(id: 'expires', label: 'Действует до', type: 'date'),
          FieldDefinition(id: 'cvv', label: 'CVV', type: 'password', secret: true),
        ],
      ),
      CardTemplate(
        id: 'tpl_identity',
        name: 'Документ',
        iconId: 'id',
        colorId: 'violet',
        builtIn: true,
        fields: [
          FieldDefinition(id: 'full_name', label: 'ФИО', type: 'text', required: true),
          FieldDefinition(id: 'document_number', label: 'Номер документа', type: 'custom_secret', required: true),
          FieldDefinition(id: 'issued_at', label: 'Дата выдачи', type: 'date'),
          FieldDefinition(id: 'notes', label: 'Заметки', type: 'multiline_note'),
        ],
      ),
      CardTemplate(
        id: 'tpl_server',
        name: 'Доступ к серверу',
        iconId: 'server',
        colorId: 'green',
        builtIn: true,
        fields: [
          FieldDefinition(id: 'host', label: 'Хост', type: 'url', required: true),
          FieldDefinition(id: 'username', label: 'Пользователь', type: 'username', required: true),
          FieldDefinition(id: 'password', label: 'Пароль или фраза ключа', type: 'password', secret: true),
          FieldDefinition(id: 'notes', label: 'Заметки', type: 'multiline_note'),
        ],
      ),
      CardTemplate(
        id: 'tpl_license',
        name: 'Лицензия ПО',
        iconId: 'license',
        colorId: 'amber',
        builtIn: true,
        fields: [
          FieldDefinition(id: 'product', label: 'Продукт', type: 'text', required: true),
          FieldDefinition(id: 'license_key', label: 'Лицензионный ключ', type: 'custom_secret', required: true),
          FieldDefinition(id: 'email', label: 'Email аккаунта', type: 'email'),
        ],
      ),
      CardTemplate(
        id: 'tpl_wifi',
        name: 'Wi-Fi',
        iconId: 'wifi',
        colorId: 'green',
        builtIn: true,
        fields: [
          FieldDefinition(id: 'ssid', label: 'Название сети', type: 'text', required: true),
          FieldDefinition(id: 'password', label: 'Пароль Wi-Fi', type: 'password', required: true, secret: true),
          FieldDefinition(id: 'security', label: 'Тип защиты', type: 'text'),
        ],
      ),
      CardTemplate(
        id: 'tpl_bank_account',
        name: 'Банковский счет',
        iconId: 'bank',
        colorId: 'blue',
        builtIn: true,
        fields: [
          FieldDefinition(id: 'bank', label: 'Банк', type: 'text', required: true),
          FieldDefinition(id: 'account', label: 'Номер счета', type: 'custom_secret', required: true),
          FieldDefinition(id: 'login', label: 'Логин интернет-банка', type: 'username'),
          FieldDefinition(id: 'password', label: 'Пароль интернет-банка', type: 'password', secret: true),
        ],
      ),
    ];

PaletteColor colorById(String id) => palette.firstWhere(
      (color) => color.id == id,
      orElse: () => palette.first,
    );

TemplateIcon iconById(String id) => templateIcons.firstWhere(
      (icon) => icon.id == id,
      orElse: () => templateIcons.first,
    );

String makeId(String prefix) {
  final random = Random.secure();
  final suffix = List.generate(12, (_) => random.nextInt(16).toRadixString(16)).join();
  return '${prefix}_$suffix';
}

enum EntryMode { openActitPass, createActitPass, openSpbWallet }

const spbDescriptionFieldId = '__spb_description';
const spbWalletChannel = MethodChannel('actit_pass_storage/spb_wallet');

int spbFieldTypeId(FieldDefinition field) {
  switch (field.type) {
    case 'multiline_note':
      return 4;
    case 'url':
      return 6;
    case 'email':
      return 7;
    case 'date':
      return 3;
    case 'phone':
      return 8;
    case 'number':
      return 2;
    default:
      return field.secret ? 2 : 1;
  }
}

class VaultShell extends StatefulWidget {
  const VaultShell({super.key});

  @override
  State<VaultShell> createState() => _VaultShellState();
}

class _VaultShellState extends State<VaultShell> {
  final vaultNameController = TextEditingController(text: 'личная');
  final passwordController = TextEditingController();
  final confirmController = TextEditingController();
  final searchController = TextEditingController();

  EntryMode entryMode = EntryMode.openActitPass;
  bool showPassword = false;
  bool showConfirm = false;
  bool unlocked = false;
  String activeView = 'cards';
  String? message;
  String? spbWalletPath;
  String? spbWalletUri;
  SpbWalletDatabase? spbWallet;
  String syncProvider = 'mounted_folder';
  String templateFilter = '';
  String sortMode = 'modified_desc';
  String? selectedItemId;
  DateTime? lastSyncAt;

  List<CardTemplate> templates = builtInTemplates();
  List<SecretItem> items = [];
  List<ConflictRecord> conflicts = [];
  final Set<String> revealed = {};
  final Map<String, String> syncConfig = {};

  bool get createMode => entryMode == EntryMode.createActitPass;
  bool get spbMode => entryMode == EntryMode.openSpbWallet || spbWallet != null;

  File get vaultFile {
    final safeName = vaultNameController.text.trim().isEmpty ? 'personal' : vaultNameController.text.trim();
    return File('${Directory.systemTemp.path}/actitpass_${base64Url.encode(utf8.encode(safeName))}.json');
  }

  @override
  void initState() {
    super.initState();
    searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    spbWallet?.close();
    vaultNameController.dispose();
    passwordController.dispose();
    confirmController.dispose();
    searchController.dispose();
    super.dispose();
  }

  Future<void> unlock() async {
    final password = passwordController.text;
    if (entryMode == EntryMode.openSpbWallet) {
      if (spbWalletPath == null || spbWalletPath!.isEmpty) {
        setState(() => message = 'Выберите файл базы SPB Wallet с расширением .swl.');
        return;
      }
      try {
        spbWallet?.close();
        final wallet = SpbWalletDatabase.open(spbWalletPath!, password);
        final snapshot = wallet.loadSnapshot();
        spbWallet = wallet;
        setState(() {
          templates = spbTemplatesToUi(snapshot.templates);
          items = spbCardsToUi(snapshot.cards);
          conflicts = [];
          lastSyncAt = null;
          selectedItemId = items.isEmpty ? null : items.first.id;
          unlocked = true;
          activeView = 'cards';
          message = null;
        });
      } catch (error) {
        setState(() => message = 'Не удалось открыть SPB Wallet: $error');
      }
      return;
    }
    if (password.length < 8) {
      setState(() => message = 'Мастер-пароль должен быть не короче 8 символов.');
      return;
    }
    if (createMode && password != confirmController.text) {
      setState(() => message = 'Пароли не совпадают.');
      return;
    }
    if (createMode) {
      templates = builtInTemplates();
      items = demoItems();
      conflicts = [];
      lastSyncAt = null;
      await saveVault();
      setState(() {
        unlocked = true;
        selectedItemId = items.isEmpty ? null : items.first.id;
        message = null;
      });
      return;
    }
    try {
      await loadVault();
      setState(() {
        unlocked = true;
        selectedItemId = items.isEmpty ? null : items.first.id;
        message = null;
      });
    } catch (_) {
      setState(() => message = 'База не найдена или пароль не подходит. Для новой базы выберите “Создать”.');
    }
  }

  Future<void> pickSpbWalletFile() async {
    if (Platform.isAndroid) {
      try {
        final picked = await spbWalletChannel.invokeMapMethod<String, Object?>('pickSpbWallet');
        if (picked == null) return;
        final path = picked['localPath']?.toString();
        if (path == null || path.isEmpty) return;
        setState(() {
          spbWalletPath = path;
          spbWalletUri = picked['uri']?.toString();
          vaultNameController.text = picked['displayName']?.toString() ?? File(path).uri.pathSegments.last;
          message = null;
        });
      } catch (error) {
        setState(() => message = 'Не удалось выбрать файл SPB Wallet: $error');
      }
      return;
    }
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['swl', 'db', 'sqlite'],
      withData: false,
    );
    final path = result?.files.single.path;
    if (path == null) return;
    setState(() {
      spbWalletPath = path;
      spbWalletUri = null;
      vaultNameController.text = File(path).uri.pathSegments.last;
      message = null;
    });
  }

  Future<bool> writeBackSpbWallet() async {
    if (!Platform.isAndroid || spbWalletUri == null || spbWalletPath == null) return true;
    try {
      await spbWalletChannel.invokeMethod<bool>('writeSpbWallet', {
        'uri': spbWalletUri,
        'localPath': spbWalletPath,
      });
      return true;
    } catch (error) {
      setState(() => message = 'Изменения сохранены во временный файл, но не записаны обратно в SPB Wallet: $error');
      return false;
    }
  }

  List<SecretItem> demoItems() {
    final now = DateTime.now();
    return [
      SecretItem(
        id: makeId('item'),
        templateId: 'tpl_password',
        title: 'Почта Яндекс',
        category: 'Личное',
        colorId: 'blue',
        modifiedAt: now,
        values: {
          'username': 'artem@example.com',
          'password': 'Trudnyj-Parol-2026!',
          'url': 'https://mail.yandex.ru',
          'notes': 'Демо-карточка для проверки глазка.',
        },
      ),
      SecretItem(
        id: makeId('item'),
        templateId: 'tpl_payment_card',
        title: 'Основная карта',
        category: 'Финансы',
        colorId: 'teal',
        modifiedAt: now,
        values: {
          'holder': 'ARTEM IVANOV',
          'number': '2200 0000 0000 1234',
          'expires': '2028-11',
          'cvv': '927',
        },
      ),
      SecretItem(
        id: makeId('item'),
        templateId: 'tpl_bank_account',
        title: 'Счет для накоплений',
        category: 'Финансы',
        colorId: 'blue',
        modifiedAt: now,
        values: {
          'bank': 'Тинькофф',
          'account': '40817810099910004312',
          'login': 'artem-bank',
          'password': 'Bank-Pass-2026!',
        },
      ),
      SecretItem(
        id: makeId('item'),
        templateId: 'tpl_note',
        title: 'Как устроена база',
        category: 'О программе ActitPassStorage',
        colorId: 'neutral',
        modifiedAt: now,
        values: {
          'note': 'База хранится локально. Для совместимости можно открывать файл SPB Wallet .swl напрямую: изменения записываются обратно в тот же формат.',
        },
      ),
      SecretItem(
        id: makeId('item'),
        templateId: 'tpl_note',
        title: 'Синхронизация',
        category: 'О программе ActitPassStorage',
        colorId: 'neutral',
        modifiedAt: now,
        values: {
          'note': 'Синхронизация настраивается отдельно: папка, WebDAV, FTP/SFTP или почта. В строке состояния видно имя базы и время последней синхронизации.',
        },
      ),
      SecretItem(
        id: makeId('item'),
        templateId: 'tpl_note',
        title: 'Заметки и вложения',
        category: 'О программе ActitPassStorage',
        colorId: 'neutral',
        modifiedAt: now,
        values: {
          'note': 'У карточек есть отдельные кнопки заметок и вложений со счетчиками. Для SPB Wallet вложения сохраняются в родном zlib+AES формате.',
        },
      ),
    ];
  }

  List<CardTemplate> spbTemplatesToUi(List<SpbWalletTemplateRecord> source) {
    return source.map((template) {
      final fields = [
        ...template.fields.map((field) {
          final secret = isSpbSecretField(field.name);
          return FieldDefinition(
            id: field.id,
            label: field.name.isEmpty ? 'Поле' : field.name,
            type: secret ? 'password' : 'text',
            secret: secret,
          );
        }),
        const FieldDefinition(id: spbDescriptionFieldId, label: 'Заметки', type: 'multiline_note'),
      ];
      return CardTemplate(
        id: template.id,
        name: template.name,
        iconId: 'key',
        colorId: 'neutral',
        fields: fields,
      );
    }).toList();
  }

  List<SecretItem> spbCardsToUi(List<SpbWalletCardRecord> source) {
    return source.map((card) {
      return SecretItem(
        id: card.id,
        templateId: card.templateId,
        title: card.title.isEmpty ? 'SPB Wallet card' : card.title,
        category: card.categoryPath,
        colorId: 'neutral',
        values: {
          ...card.fieldValues,
          spbDescriptionFieldId: card.description,
        },
        attachments: card.attachments
            .map(
              (attachment) => SecretAttachment(
                id: attachment.id,
                fileName: attachment.fileName,
                size: attachment.size,
                decodeError: attachment.decodeError,
              ),
            )
            .toList(),
        modifiedAt: DateTime.now(),
        hitCount: card.hitCount,
      );
    }).toList();
  }

  bool isSpbSecretField(String label) {
    final normalized = label.toLowerCase();
    return normalized.contains('password') ||
        normalized.contains('pass') ||
        normalized.contains('парол') ||
        normalized.contains('pin') ||
        normalized.contains('пин') ||
        normalized.contains('cvv') ||
        normalized.contains('код');
  }

  Future<void> loadVault() async {
    final raw = await vaultFile.readAsString();
    final json = jsonDecode(utf8.decode(base64.decode(raw))) as Map<String, dynamic>;
    if (json['passwordHash'] != passwordHash(passwordController.text)) {
      throw StateError('wrong password');
    }
    templates = (json['templates'] as List<dynamic>)
        .map((template) => CardTemplate.fromJson(template as Map<String, dynamic>))
        .toList();
    items = (json['items'] as List<dynamic>)
        .map((item) => SecretItem.fromJson(item as Map<String, dynamic>))
        .toList();
    conflicts = (json['conflicts'] as List<dynamic>? ?? [])
        .map((conflict) => ConflictRecord.fromJson(conflict as Map<String, dynamic>))
        .toList();
    lastSyncAt = json['lastSyncAt'] == null ? null : DateTime.tryParse(json['lastSyncAt'] as String);
  }

  Future<void> saveVault() async {
    final payload = {
      'format': 'actitpass-flutter-alpha',
      'passwordHash': passwordHash(passwordController.text),
      'templates': templates.map((template) => template.toJson()).toList(),
      'items': items.map((item) => item.toJson()).toList(),
      'conflicts': conflicts.map((conflict) => conflict.toJson()).toList(),
      'lastSyncAt': lastSyncAt?.toIso8601String(),
    };
    await vaultFile.writeAsString(base64.encode(utf8.encode(jsonEncode(payload))));
  }

  String passwordHash(String password) {
    var hash = 2166136261;
    for (final codeUnit in password.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 16777619) & 0xffffffff;
    }
    return hash.toRadixString(16);
  }

  @override
  Widget build(BuildContext context) {
    if (!unlocked) return buildLocked();
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 820;
        return Scaffold(
          body: SafeArea(
            child: compact
                ? Column(
                    children: [
                      buildTopRail(compact: true),
                      Expanded(child: buildContent()),
                    ],
                  )
                : Row(
                    children: [
                      SizedBox(width: 260, child: buildSideRail()),
                      Expanded(child: buildContent()),
                    ],
                  ),
          ),
          bottomNavigationBar: databaseStatusBar(),
        );
      },
    );
  }

  Widget databaseStatusBar() {
    return Material(
      color: const Color(0xffedf2f6),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              const Icon(Icons.storage_outlined, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${openDatabaseTitle()} · Последняя синхронизация: ${lastSyncText()}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String openDatabaseTitle() {
    if (spbWallet != null) {
      final path = spbWalletPath;
      if (path == null || path.isEmpty) return 'SPB Wallet';
      return File(path).uri.pathSegments.isEmpty ? path : File(path).uri.pathSegments.last;
    }
    final name = vaultNameController.text.trim();
    return name.isEmpty ? 'personal' : name;
  }

  String lastSyncText() {
    final value = lastSyncAt;
    if (value == null) return 'не выполнялась';
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(local.day)}.${two(local.month)}.${local.year} ${two(local.hour)}:${two(local.minute)}';
  }

  Widget buildLocked() {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Wrap(
              spacing: 24,
              runSpacing: 24,
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 360,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircleAvatar(radius: 32, child: Text('A', style: TextStyle(fontSize: 28))),
                      const SizedBox(height: 18),
                      Text('ActitPassStorage', style: Theme.of(context).textTheme.headlineMedium),
                      const SizedBox(height: 8),
                      const Text('Менеджер паролей, заметок и настраиваемых карточек. Локальная база на устройстве, мастер-пароль и понятная синхронизация.'),
                    ],
                  ),
                ),
                Card(
                  elevation: 0,
                  child: SizedBox(
                    width: 380,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SegmentedButton<EntryMode>(
                            segments: const [
                              ButtonSegment(value: EntryMode.openActitPass, label: Text('Открыть ActitPass')),
                              ButtonSegment(value: EntryMode.createActitPass, label: Text('Создать ActitPass')),
                              ButtonSegment(value: EntryMode.openSpbWallet, label: Text('Открыть SPB Wallet')),
                            ],
                            selected: {entryMode},
                            onSelectionChanged: (value) => setState(() {
                              entryMode = value.first;
                              message = null;
                            }),
                          ),
                          const SizedBox(height: 18),
                          if (entryMode == EntryMode.openSpbWallet) ...[
                            OutlinedButton.icon(
                              onPressed: pickSpbWalletFile,
                              icon: const Icon(Icons.folder_open),
                              label: const Text('Выбрать .swl файл'),
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                spbWalletPath == null ? 'Файл SPB Wallet не выбран' : spbWalletPath!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ] else
                            TextField(
                              controller: vaultNameController,
                              decoration: const InputDecoration(labelText: 'Название базы', border: OutlineInputBorder()),
                            ),
                          const SizedBox(height: 12),
                          PasswordField(
                            controller: passwordController,
                            label: entryMode == EntryMode.openSpbWallet ? 'Пароль SPB Wallet' : 'Мастер-пароль',
                            visible: showPassword,
                            onToggle: () => setState(() => showPassword = !showPassword),
                          ),
                          if (createMode) ...[
                            const SizedBox(height: 12),
                            PasswordField(
                              controller: confirmController,
                              label: 'Повторите мастер-пароль',
                              visible: showConfirm,
                              onToggle: () => setState(() => showConfirm = !showConfirm),
                            ),
                          ],
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: unlock,
                              child: Text(entryMode == EntryMode.createActitPass
                                  ? 'Создать базу'
                                  : entryMode == EntryMode.openSpbWallet
                                      ? 'Открыть базу SPB Wallet'
                                      : 'Открыть базу'),
                            ),
                          ),
                          if (message != null) ...[
                            const SizedBox(height: 12),
                            Text(message!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget buildSideRail() {
    return Material(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              leading: const CircleAvatar(child: Text('A')),
              title: Text(spbWallet == null ? 'ActitPass' : 'SPB Wallet'),
              subtitle: Text(spbWallet == null ? 'локальная база' : (spbWalletPath ?? 'открытая .swl база')),
            ),
            const SizedBox(height: 12),
            ...navButtons(),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: () async {
                await writeBackSpbWallet();
                spbWallet?.close();
                spbWallet = null;
                spbWalletUri = null;
                setState(() => unlocked = false);
              },
              icon: const Icon(Icons.lock_outline),
              label: const Text('Заблокировать'),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildTopRail({required bool compact}) {
    return Material(
      color: Colors.white,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(8),
        child: Row(children: navButtons(compact: compact)),
      ),
    );
  }

  List<Widget> navButtons({bool compact = false}) {
    final entries = [
      ('cards', Icons.credit_card, 'Карточки'),
      ('frequent', Icons.star_outline, 'Частые'),
      ('templates', Icons.dashboard_customize_outlined, 'Шаблоны'),
      ('sync', Icons.sync, 'Синхронизация'),
      ('conflicts', Icons.warning_amber, 'Конфликты'),
      ('settings', Icons.settings_outlined, 'Настройки'),
    ];
    return entries
        .map(
          (entry) => Padding(
            padding: EdgeInsets.only(bottom: compact ? 0 : 8, right: compact ? 8 : 0),
            child: NavigationButton(
              selected: activeView == entry.$1,
              icon: entry.$2,
              label: entry.$3,
              onTap: () => setState(() => activeView = entry.$1),
            ),
          ),
        )
        .toList();
  }

  Widget buildContent() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(viewTitle(), style: Theme.of(context).textTheme.headlineSmall),
                  const Text('Секреты скрыты по умолчанию. Изменения сохраняются локально.'),
                ],
              ),
              FilledButton.icon(
                onPressed: primaryAction,
                icon: Icon(primaryIcon()),
                label: Text(primaryLabel()),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(child: viewBody()),
        ],
      ),
    );
  }

  String viewTitle() => {
      'cards': 'Карточки',
      'frequent': 'Часто используемые',
      'templates': 'Шаблоны',
        'sync': 'Синхронизация',
        'conflicts': 'Конфликты',
        'settings': 'Настройки',
      }[activeView]!;

  String primaryLabel() => activeView == 'templates'
      ? 'Новый шаблон'
      : activeView == 'sync'
          ? 'Синхронизировать'
          : 'Новая карточка';

  IconData primaryIcon() => activeView == 'templates'
      ? Icons.add_box_outlined
      : activeView == 'sync'
          ? Icons.sync
          : Icons.add;

  void primaryAction() {
    if (activeView == 'templates') {
      openTemplateDialog();
    } else if (activeView == 'sync') {
      runSync();
    } else {
      openItemDialog();
    }
  }

  Widget viewBody() {
    switch (activeView) {
      case 'frequent':
        return buildFrequentView();
      case 'templates':
        return buildTemplatesView();
      case 'sync':
        return buildSyncView();
      case 'conflicts':
        return buildConflictsView();
      case 'settings':
        return buildSettingsView();
      default:
        return buildCardsView();
    }
  }

  Widget buildCardsView() {
    final filtered = filteredItems();
    final selected = selectedItem(filtered);
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: searchController,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Поиск', border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: 'Фильтры',
              child: IconButton.filledTonal(
                onPressed: openCardFilterDialog,
                icon: Badge(
                  isLabelVisible: templateFilter.isNotEmpty || sortMode != 'modified_desc',
                  child: const Icon(Icons.filter_alt_outlined),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 760;
              if (compact) {
                return Column(
                  children: [
                    SizedBox(height: 260, child: walletTree(filtered)),
                    const SizedBox(height: 12),
                    Expanded(child: selected == null ? emptyCardDetail() : itemDetail(selected)),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: 320, child: walletTree(filtered)),
                  const SizedBox(width: 12),
                  Expanded(child: selected == null ? emptyCardDetail() : itemDetail(selected)),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> openCardFilterDialog() async {
    var nextTemplateFilter = templateFilter;
    var nextSortMode = sortMode;
    final applied = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Фильтры карточек'),
          content: SizedBox(
            width: min(MediaQuery.of(context).size.width - 48, 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: nextTemplateFilter,
                  decoration: const InputDecoration(labelText: 'Шаблон', border: OutlineInputBorder()),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('Все шаблоны')),
                    ...templates.map((template) => DropdownMenuItem(value: template.id, child: Text(template.name))),
                  ],
                  onChanged: (value) => setDialogState(() => nextTemplateFilter = value ?? ''),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: nextSortMode,
                  decoration: const InputDecoration(labelText: 'Сортировка', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 'modified_desc', child: Text('Сначала новые')),
                    DropdownMenuItem(value: 'title_asc', child: Text('По названию')),
                    DropdownMenuItem(value: 'template_asc', child: Text('По шаблону')),
                  ],
                  onChanged: (value) => setDialogState(() => nextSortMode = value ?? 'modified_desc'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                nextTemplateFilter = '';
                nextSortMode = 'modified_desc';
                Navigator.pop(context, true);
              },
              child: const Text('Сбросить'),
            ),
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Применить')),
          ],
        ),
      ),
    );
    if (applied != true) return;
    setState(() {
      templateFilter = nextTemplateFilter;
      sortMode = nextSortMode;
    });
  }

  List<SecretItem> filteredItems() {
    final filtered = items.where((item) {
      final template = templateFor(item.templateId);
      final text = '${item.title} ${item.category} ${template.name} ${item.values.values.join(' ')}'.toLowerCase();
      return (templateFilter.isEmpty || item.templateId == templateFilter) && text.contains(searchController.text.toLowerCase());
    }).toList();
    if (sortMode == 'title_asc') {
      filtered.sort((a, b) => a.title.compareTo(b.title));
    } else if (sortMode == 'template_asc') {
      filtered.sort((a, b) => templateFor(a.templateId).name.compareTo(templateFor(b.templateId).name));
    } else {
      filtered.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
    }
    return filtered;
  }

  SecretItem? selectedItem(List<SecretItem> candidates) {
    if (candidates.isEmpty) return null;
    for (final item in candidates) {
      if (item.id == selectedItemId) return item;
    }
    return candidates.first;
  }

  Widget walletTree(List<SecretItem> source) {
    final root = buildCategoryTree(source);
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: const Color(0xffd8e4f0),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: const Text('Мои карточки', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          Expanded(
            child: root.isEmpty
                ? const Center(child: Text('Карточек не найдено'))
                : ListView(
                    children: [
                      ExpansionTile(
                        initiallyExpanded: true,
                        leading: const Icon(Icons.account_balance_wallet_outlined),
                        title: const Text('Мой кошелёк'),
                        children: treeChildren(root, 0),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  CategoryTreeNode buildCategoryTree(List<SecretItem> source) {
    final root = CategoryTreeNode('Мой кошелёк');
    for (final item in source) {
      var node = root;
      for (final part in categoryParts(item.category)) {
        node = node.children.putIfAbsent(part, () => CategoryTreeNode(part));
      }
      node.cards.add(item);
    }
    return root;
  }

  List<String> categoryParts(String value) {
    return value
        .split(RegExp(r'\s*/\s*'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty && part != 'Без категории')
        .toList();
  }

  List<Widget> treeChildren(CategoryTreeNode node, int depth) {
    final children = <Widget>[];
    final folders = node.children.values.toList()..sort((a, b) => a.name.compareTo(b.name));
    for (final folder in folders) {
      children.add(
        Padding(
          padding: EdgeInsets.only(left: depth * 10.0),
          child: ExpansionTile(
            initiallyExpanded: true,
            leading: const Icon(Icons.folder_outlined, size: 20),
            title: Text(folder.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            children: treeChildren(folder, depth + 1),
          ),
        ),
      );
    }
    final cards = [...node.cards]..sort((a, b) => a.title.compareTo(b.title));
    for (final item in cards) {
      final template = templateFor(item.templateId);
      children.add(
        Padding(
          padding: EdgeInsets.only(left: 16 + depth * 14.0),
          child: ListTile(
            dense: true,
            selected: selectedItemId == item.id,
            leading: Text(iconById(template.iconId).symbol),
            title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(template.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () => selectItem(item),
            onLongPress: () => openItemDialog(item: item),
          ),
        ),
      );
    }
    return children;
  }

  Widget emptyCardDetail() {
    return const Card(
      elevation: 0,
      child: Center(child: Text('Выберите карточку в дереве слева')),
    );
  }

  Widget itemDetail(SecretItem item) {
    return itemCard(item);
  }

  Future<void> selectItem(SecretItem item) async {
    setState(() {
      selectedItemId = item.id;
      items = [
        for (final entry in items)
          entry.id == item.id
              ? SecretItem(
                  id: entry.id,
                  templateId: entry.templateId,
                  title: entry.title,
                  category: entry.category,
                  colorId: entry.colorId,
                  values: entry.values,
                  modifiedAt: entry.modifiedAt,
                  attachments: entry.attachments,
                  hitCount: entry.hitCount + 1,
                )
              : entry,
      ];
    });
    if (spbWallet != null) {
      try {
        spbWallet!.recordCardHit(item.id);
        await writeBackSpbWallet();
      } catch (error) {
        setState(() => message = 'Не удалось обновить счетчик SPB Wallet: $error');
      }
    } else {
      await saveVault();
    }
  }

  Widget buildFrequentView() {
    final frequent = [...items]..sort((a, b) {
        final byHits = b.hitCount.compareTo(a.hitCount);
        return byHits == 0 ? a.title.compareTo(b.title) : byHits;
      });
    final top = frequent.where((item) => item.hitCount > 0).take(10).toList();
    if (top.isEmpty) {
      return const Center(child: Text('Часто используемые карточки появятся после открытия карточек из дерева.'));
    }
    return ListView.separated(
      itemCount: top.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = top[index];
        final template = templateFor(item.templateId);
        return Card(
          elevation: 0,
          child: ListTile(
            leading: Text(iconById(template.iconId).symbol, style: const TextStyle(fontSize: 24)),
            title: Text(item.title),
            subtitle: Text('${template.name} · открытий: ${item.hitCount}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              setState(() {
                selectedItemId = item.id;
                activeView = 'cards';
              });
            },
          ),
        );
      },
    );
  }

  Widget itemCard(SecretItem item) {
    final template = templateFor(item.templateId);
    final color = colorById(item.colorId.isEmpty ? template.colorId : item.colorId);
    final noteCount = noteText(item).trim().isEmpty ? 0 : 1;
    final attachmentCount = item.attachments.where((attachment) => !attachment.deleted).length;
    return Card(
      color: color.bg,
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => openItemDialog(item: item),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(iconById(template.iconId).symbol, style: const TextStyle(fontSize: 28)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: color.fg)),
                        Text(template.name, style: TextStyle(color: color.fg.withValues(alpha: 0.72))),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  physics: const NeverScrollableScrollPhysics(),
                  children: template.fields.where((field) => (item.values[field.id] ?? '').isNotEmpty).map((field) {
                    final revealKey = '${item.id}:${field.id}';
                    final isRevealed = revealed.contains(revealKey);
                    final value = item.values[field.id]!;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${field.label}: ${field.secret && !isRevealed ? '••••••••' : value}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: color.fg),
                            ),
                          ),
                          if (field.secret)
                            IconButton(
                              tooltip: isRevealed ? 'Скрыть' : 'Показать',
                              icon: Icon(isRevealed ? Icons.visibility_off : Icons.visibility),
                              onPressed: () => setState(() {
                                isRevealed ? revealed.remove(revealKey) : revealed.add(revealKey);
                              }),
                            ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 8),
              Text('Категория: ${item.category.isEmpty ? 'Без категории' : item.category}', style: TextStyle(color: color.fg.withValues(alpha: 0.72))),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  CountBadgeButton(
                    icon: Icons.notes_outlined,
                    label: 'Заметки',
                    count: noteCount,
                    onPressed: () => openNotesDialog(item),
                  ),
                  CountBadgeButton(
                    icon: Icons.attach_file,
                    label: 'Вложения',
                    count: attachmentCount,
                    onPressed: () => openAttachmentsDialog(item),
                  ),
                ],
              ),
              if (item.colorId.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Цвет: ', style: TextStyle(color: color.fg.withValues(alpha: 0.72))),
                      CircleAvatar(radius: 6, backgroundColor: color.bg),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String noteFieldIdFor(SecretItem item) {
    final template = templateFor(item.templateId);
    if (template.fields.any((field) => field.id == spbDescriptionFieldId)) return spbDescriptionFieldId;
    if (template.fields.any((field) => field.id == 'notes')) return 'notes';
    if (template.fields.any((field) => field.id == 'note')) return 'note';
    return spbDescriptionFieldId;
  }

  String noteText(SecretItem item) => item.values[noteFieldIdFor(item)] ?? '';

  Future<void> openNotesDialog(SecretItem item) async {
    final fieldId = noteFieldIdFor(item);
    final controller = TextEditingController(text: item.values[fieldId] ?? '');
    final saved = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Заметки: ${item.title}'),
        content: SizedBox(
          width: min(MediaQuery.of(context).size.width - 48, 620),
          child: TextField(
            controller: controller,
            minLines: 8,
            maxLines: 14,
            decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Заметка'),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Сохранить')),
        ],
      ),
    );
    controller.dispose();
    if (saved == null) return;
    await persistItem(
      SecretItem(
        id: item.id,
        templateId: item.templateId,
        title: item.title,
        category: item.category,
        colorId: item.colorId,
        values: {...item.values, fieldId: saved},
        modifiedAt: DateTime.now(),
        attachments: item.attachments,
        hitCount: item.hitCount,
      ),
    );
  }

  Future<void> openAttachmentsDialog(SecretItem item) async {
    await openItemDialog(item: item);
  }

  Widget buildTemplatesView() {
    return ListView.separated(
      itemCount: templates.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final template = templates[index];
        final color = colorById('neutral');
        return Card(
          elevation: 0,
          child: ListTile(
            leading: CircleAvatar(backgroundColor: color.bg, foregroundColor: color.fg, child: Text(iconById(template.iconId).symbol)),
            title: Text(template.name),
            subtitle: Text(template.fields.map((field) => '${field.label}${field.secret ? ' (скрыто)' : ''}').join(', ')),
            trailing: Wrap(
              spacing: 4,
              children: [
                if (template.builtIn) const Chip(label: Text('Встроенный')),
                IconButton(
                  tooltip: 'Скопировать шаблон',
                  icon: const Icon(Icons.copy),
                  onPressed: () => copyTemplate(template),
                ),
                const Icon(Icons.edit),
              ],
            ),
            onTap: () => openTemplateDialog(template: template),
          ),
        );
      },
    );
  }

  Future<void> copyTemplate(CardTemplate template) async {
    final copy = CardTemplate(
      id: makeId('tpl'),
      name: '${template.name}(1)',
      iconId: template.iconId,
      colorId: template.colorId,
      builtIn: false,
      fields: [
        for (final field in template.fields)
          FieldDefinition(
            id: field.id,
            label: field.label,
            type: field.type,
            required: field.required,
            secret: field.secret,
          ),
      ],
    );
    if (spbWallet != null) {
      final prepared = prepareSpbTemplate(copy, true);
      try {
        spbWallet!.saveTemplate(
          SpbWalletTemplateDraft(
            id: prepared.id,
            name: prepared.name,
            fields: prepared.fields
                .where((field) => field.id != spbDescriptionFieldId)
                .map((field) => SpbWalletTemplateFieldRecord(id: field.id, name: field.label, templateId: prepared.id, fieldTypeId: spbFieldTypeId(field)))
                .toList(),
          ),
        );
        final snapshot = spbWallet!.loadSnapshot();
        setState(() {
          templates = spbTemplatesToUi(snapshot.templates);
          items = spbCardsToUi(snapshot.cards);
        });
      } catch (error) {
        setState(() => message = 'Не удалось скопировать шаблон SPB Wallet: $error');
      }
      return;
    }
    setState(() => templates = [...templates, copy]);
    await saveVault();
  }

  Widget buildSyncView() {
    return ListView(
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            SizedBox(
              width: 360,
              child: Card(
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: syncProvider,
                        decoration: const InputDecoration(labelText: 'Тип синхронизации', border: OutlineInputBorder()),
                        items: const [
                          DropdownMenuItem(value: 'mounted_folder', child: Text('Папка / SMB / NFS')),
                          DropdownMenuItem(value: 'email', child: Text('Почта IMAP/SMTP')),
                          DropdownMenuItem(value: 'webdav', child: Text('WebDAV')),
                          DropdownMenuItem(value: 'sftp', child: Text('SFTP')),
                          DropdownMenuItem(value: 'ftp', child: Text('FTP/FTPS')),
                        ],
                        onChanged: (value) => setState(() => syncProvider = value ?? 'mounted_folder'),
                      ),
                      const SizedBox(height: 12),
                      ...syncFields(syncProvider),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () => showSyncHelp(syncProvider),
                        icon: const Icon(Icons.help_outline),
                        label: const Text('Как настроить этот способ'),
                      ),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: runSync,
                        icon: const Icon(Icons.sync),
                        label: const Text('Синхронизировать'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(
              width: 420,
              child: Card(
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Как это работает', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      const Text('Каждое устройство хранит локальную копию базы. Синхронизация обменивается зашифрованными пакетами изменений. Если два устройства изменили одну карточку, выигрывает более поздняя версия, а конфликт попадает в журнал.'),
                      const SizedBox(height: 12),
                      Text('Текущий провайдер: ${syncTitle(syncProvider)}'),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  List<Widget> syncFields(String provider) {
    final specs = {
      'mounted_folder': [
        ('directory', 'Путь к папке', '/home/user/ActitPassSync', false),
      ],
      'email': [
        ('email', 'Почтовый ящик', 'user@example.com', false),
        ('imapHost', 'IMAP сервер', 'imap.example.com', false),
        ('imapPort', 'IMAP порт', '993', false),
        ('smtpHost', 'SMTP сервер', 'smtp.example.com', false),
        ('smtpPort', 'SMTP порт', '465', false),
        ('login', 'Логин', 'user@example.com', false),
        ('password', 'Пароль приложения', '', true),
        ('folder', 'Папка/метка', 'ActitPassStorage', false),
      ],
      'webdav': [
        ('url', 'WebDAV URL папки', 'https://example.com/remote.php/dav/files/user/ActitPass/', false),
        ('username', 'Пользователь', '', false),
        ('password', 'Пароль или токен', '', true),
      ],
      'sftp': [
        ('host', 'SFTP хост', 'storage.example.com', false),
        ('port', 'Порт', '22', false),
        ('username', 'Пользователь', '', false),
        ('password', 'Пароль или фраза ключа', '', true),
        ('path', 'Удаленная папка', '/ActitPass', false),
      ],
      'ftp': [
        ('host', 'FTP/FTPS хост', 'ftp.example.com', false),
        ('port', 'Порт', '21', false),
        ('username', 'Пользователь', '', false),
        ('password', 'Пароль', '', true),
        ('path', 'Удаленная папка', '/ActitPass', false),
        ('security', 'Режим: FTP / FTPS явный / FTPS неявный', 'FTP', false),
      ],
    }[provider]!;
    return specs.map((spec) => SyncTextField(
          label: spec.$2,
          hint: spec.$3,
          secret: spec.$4,
          initialValue: syncConfig['$provider:${spec.$1}'] ?? '',
          onChanged: (value) => syncConfig['$provider:${spec.$1}'] = value,
        )).toList();
  }

  Widget buildConflictsView() {
    if (conflicts.isEmpty) {
      return const Center(child: Text('Конфликтов пока нет. Если они появятся, здесь будет видно старую и новую версию.'));
    }
    return ListView.separated(
      itemCount: conflicts.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final conflict = conflicts[index];
        return Card(
          elevation: 0,
          child: ListTile(
            leading: Icon(conflict.reviewed ? Icons.check_circle_outline : Icons.warning_amber),
            title: Text(conflict.title),
            subtitle: Text(conflict.description),
            trailing: Text(conflict.reviewed ? 'Просмотрено' : 'Новое'),
          ),
        );
      },
    );
  }

  Widget buildSettingsView() {
    return ListView(
      children: [
        Text('Открытая база', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        Card(
          elevation: 0,
          child: ListTile(
            leading: const Icon(Icons.storage_outlined),
            title: Text(openDatabaseTitle()),
            subtitle: Text('Последняя синхронизация: ${lastSyncText()}'),
          ),
        ),
        const SizedBox(height: 24),
        Text('Палитра карточек', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: palette.map((color) => Chip(
                avatar: CircleAvatar(backgroundColor: color.bg),
                label: Text(color.label),
              )).toList(),
        ),
        const SizedBox(height: 24),
        Text('Пиктограммы шаблонов', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: templateIcons.map((icon) => Chip(label: Text('${icon.symbol} ${icon.label}'))).toList(),
        ),
      ],
    );
  }

  CardTemplate templateFor(String id) => templates.firstWhere(
        (template) => template.id == id,
        orElse: () => templates.first,
      );

  Future<void> openItemDialog({SecretItem? item}) async {
    final saved = await showDialog<SecretItem>(
      context: context,
      builder: (context) => ItemEditorDialog(
        templates: templates,
        initial: item,
        supportsAttachments: spbWallet != null,
      ),
    );
    if (saved == null) return;
    await persistItem(saved);
  }

  Future<void> persistItem(SecretItem saved) async {
    if (spbWallet != null) {
      await saveSpbItem(saved);
      return;
    }
    setState(() {
      items = [
        ...items.where((entry) => entry.id != saved.id),
        saved,
      ];
      selectedItemId = saved.id;
    });
    await saveVault();
  }

  Future<void> saveSpbItem(SecretItem saved) async {
    final wallet = spbWallet;
    if (wallet == null) return;
    final cardId = isSpbHexId(saved.id) ? saved.id : SpbWalletDatabase.makeId();
    try {
      wallet.saveCard(
        SpbWalletCardDraft(
          id: cardId,
          title: saved.title,
          description: saved.values[spbDescriptionFieldId] ?? '',
          categoryPath: saved.category,
          templateId: saved.templateId,
          fieldValues: {
            for (final entry in saved.values.entries)
              if (entry.key != spbDescriptionFieldId) entry.key: entry.value,
          },
        ),
      );
      for (final attachment in saved.attachments) {
        if (attachment.deleted && attachment.id.isNotEmpty) {
          wallet.deleteAttachment(attachment.id);
        } else if (attachment.pendingBytes != null) {
          wallet.saveAttachment(
            cardId: cardId,
            attachmentId: attachment.id.isEmpty ? null : attachment.id,
            fileName: attachment.fileName,
            bytes: attachment.pendingBytes!,
          );
        }
      }
      await writeBackSpbWallet();
      final snapshot = wallet.loadSnapshot();
      setState(() {
        templates = spbTemplatesToUi(snapshot.templates);
        items = spbCardsToUi(snapshot.cards);
        selectedItemId = cardId;
        message = null;
      });
    } catch (error) {
      setState(() => message = 'Не удалось сохранить SPB Wallet: $error');
    }
  }

  Future<void> openTemplateDialog({CardTemplate? template}) async {
    final saved = await showDialog<CardTemplate>(
      context: context,
      builder: (context) => TemplateEditorDialog(initial: template),
    );
    if (saved == null) return;
    if (spbWallet != null) {
      final prepared = prepareSpbTemplate(saved, template == null);
      try {
        spbWallet!.saveTemplate(
          SpbWalletTemplateDraft(
            id: prepared.id,
            name: prepared.name,
            fields: prepared.fields
                .where((field) => field.id != spbDescriptionFieldId)
                .map((field) => SpbWalletTemplateFieldRecord(id: field.id, name: field.label, templateId: prepared.id, fieldTypeId: spbFieldTypeId(field)))
                .toList(),
          ),
        );
        await writeBackSpbWallet();
        final snapshot = spbWallet!.loadSnapshot();
        setState(() {
          templates = spbTemplatesToUi(snapshot.templates);
          items = spbCardsToUi(snapshot.cards);
          message = null;
        });
      } catch (error) {
        setState(() => message = 'Не удалось сохранить шаблон SPB Wallet: $error');
      }
      return;
    }
    setState(() {
      templates = [
        ...templates.where((entry) => entry.id != saved.id),
        saved,
      ];
    });
    await saveVault();
  }

  CardTemplate prepareSpbTemplate(CardTemplate template, bool isNew) {
    if (!isNew) return template;
    final id = SpbWalletDatabase.makeId();
    return CardTemplate(
      id: id,
      name: template.name,
      iconId: template.iconId,
      colorId: template.colorId,
      fields: template.fields
          .map((field) => FieldDefinition(
                id: SpbWalletDatabase.makeId(),
                label: field.label,
                type: field.type,
                required: field.required,
                secret: field.secret,
              ))
          .toList(),
    );
  }

  bool isSpbHexId(String value) => RegExp(r'^[0-9A-Fa-f]+$').hasMatch(value) && value.length.isEven;

  Future<void> runSync() async {
    final now = DateTime.now();
    setState(() {
      lastSyncAt = now;
      conflicts = [
        ConflictRecord(
          id: makeId('conflict'),
          title: 'Проверка синхронизации: ${syncTitle(syncProvider)}',
          description: 'Демо-запись показывает журнал конфликтов. В промышленном Rust-ядре здесь будет результат last-write-wins merge.',
          createdAt: now,
        ),
        ...conflicts,
      ];
      activeView = 'conflicts';
    });
    await saveVault();
  }

  String syncTitle(String provider) => {
        'mounted_folder': 'Папка / SMB / NFS',
        'email': 'Почта IMAP/SMTP',
        'webdav': 'WebDAV',
        'sftp': 'SFTP',
        'ftp': 'FTP/FTPS',
      }[provider]!;

  void showSyncHelp(String provider) {
    final steps = {
      'mounted_folder': [
        'Создайте отдельную папку для пакетов ActitPassStorage.',
        'Для SMB/NFS сначала подключите сетевой ресурс средствами системы.',
        'В поле пути укажите локальный путь к уже доступной папке.',
      ],
      'email': [
        'Создайте отдельный ящик или папку/метку для писем синхронизации.',
        'Укажите IMAP для чтения и SMTP для отправки.',
        'Используйте пароль приложения. Пакеты в письмах зашифрованы мастер-паролем.',
      ],
      'webdav': [
        'Создайте папку в Nextcloud, ownCloud, NAS или другом WebDAV-хранилище.',
        'Вставьте полный WebDAV URL папки.',
        'Если нужна авторизация, используйте отдельный пароль приложения.',
      ],
      'sftp': [
        'Подготовьте SSH/SFTP доступ и отдельную удаленную папку.',
        'Укажите хост, порт, пользователя и путь.',
        'Для ключа с фразой введите фразу ключа в поле пароля.',
      ],
      'ftp': [
        'Создайте отдельную FTP/FTPS папку.',
        'Укажите хост, порт, пользователя, пароль и путь.',
        'Обычный FTP не защищает учетные данные в сети; лучше FTPS/WebDAV HTTPS/SFTP.',
      ],
    }[provider]!;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Как настроить: ${syncTitle(provider)}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: steps.map((step) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('• $step'),
              )).toList(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Понятно')),
        ],
      ),
    );
  }
}

class PasswordField extends StatelessWidget {
  const PasswordField({
    required this.controller,
    required this.label,
    required this.visible,
    required this.onToggle,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final bool visible;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: !visible,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          tooltip: visible ? 'Скрыть' : 'Показать',
          icon: Icon(visible ? Icons.visibility_off : Icons.visibility),
          onPressed: onToggle,
        ),
      ),
    );
  }
}

class SyncTextField extends StatefulWidget {
  const SyncTextField({
    required this.label,
    required this.hint,
    required this.initialValue,
    required this.secret,
    required this.onChanged,
    super.key,
  });

  final String label;
  final String hint;
  final String initialValue;
  final bool secret;
  final ValueChanged<String> onChanged;

  @override
  State<SyncTextField> createState() => _SyncTextFieldState();
}

class _SyncTextFieldState extends State<SyncTextField> {
  bool visible = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        initialValue: widget.initialValue,
        obscureText: widget.secret && !visible,
        onChanged: widget.onChanged,
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.hint,
          border: const OutlineInputBorder(),
          suffixIcon: widget.secret
              ? IconButton(
                  tooltip: visible ? 'Скрыть' : 'Показать',
                  icon: Icon(visible ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => visible = !visible),
                )
              : null,
        ),
      ),
    );
  }
}

class NavigationButton extends StatelessWidget {
  const NavigationButton({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
    super.key,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          alignment: Alignment.centerLeft,
          backgroundColor: selected ? Theme.of(context).colorScheme.primaryContainer : null,
        ),
      ),
    );
  }
}

class CountBadgeButton extends StatelessWidget {
  const CountBadgeButton({
    required this.icon,
    required this.label,
    required this.count,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String label;
  final int count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        OutlinedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 18),
          label: Text(label),
        ),
        if (count > 0)
          Positioned(
            right: -5,
            top: -7,
            child: Container(
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              padding: const EdgeInsets.symmetric(horizontal: 5),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.error,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                count > 99 ? '99+' : '$count',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onError,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class ItemEditorDialog extends StatefulWidget {
  const ItemEditorDialog({
    required this.templates,
    this.initial,
    this.supportsAttachments = false,
    super.key,
  });

  final List<CardTemplate> templates;
  final SecretItem? initial;
  final bool supportsAttachments;

  @override
  State<ItemEditorDialog> createState() => _ItemEditorDialogState();
}

class _ItemEditorDialogState extends State<ItemEditorDialog> {
  late String templateId;
  late String colorId;
  late final TextEditingController title;
  late final TextEditingController category;
  late final Map<String, TextEditingController> values;
  late List<SecretAttachment> attachments;
  final Set<String> visibleSecrets = {};

  CardTemplate get template => widget.templates.firstWhere((entry) => entry.id == templateId);

  @override
  void initState() {
    super.initState();
    templateId = widget.initial?.templateId ?? widget.templates.first.id;
    colorId = widget.initial?.colorId ?? template.colorId;
    title = TextEditingController(text: widget.initial?.title ?? '');
    category = TextEditingController(text: widget.initial?.category ?? '');
    values = {
      for (final field in template.fields) field.id: TextEditingController(text: widget.initial?.values[field.id] ?? ''),
    };
    attachments = [...?widget.initial?.attachments];
  }

  @override
  void dispose() {
    title.dispose();
    category.dispose();
    for (final controller in values.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? 'Новая карточка' : 'Редактировать карточку'),
      content: SizedBox(
        width: min(MediaQuery.of(context).size.width - 48, 680),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: templateId,
                decoration: const InputDecoration(labelText: 'Шаблон', border: OutlineInputBorder()),
                items: widget.templates.map((template) => DropdownMenuItem(value: template.id, child: Text('${iconById(template.iconId).symbol} ${template.name}'))).toList(),
                onChanged: (value) => setState(() {
                  templateId = value ?? templateId;
                  for (final field in template.fields) {
                    values.putIfAbsent(field.id, () => TextEditingController());
                  }
                }),
              ),
              const SizedBox(height: 10),
              TextField(controller: title, decoration: const InputDecoration(labelText: 'Название', border: OutlineInputBorder())),
              const SizedBox(height: 10),
              TextField(controller: category, decoration: const InputDecoration(labelText: 'Категория', border: OutlineInputBorder())),
              const SizedBox(height: 10),
              ColorPicker(value: colorId, onChanged: (value) => setState(() => colorId = value)),
              const SizedBox(height: 10),
              ...template.fields.map((field) {
                final controller = values.putIfAbsent(field.id, () => TextEditingController());
                final visible = visibleSecrets.contains(field.id);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TextField(
                    controller: controller,
                    obscureText: field.secret && !visible,
                    minLines: field.type == 'multiline_note' ? 3 : 1,
                    maxLines: field.type == 'multiline_note' ? 5 : 1,
                    decoration: InputDecoration(
                      labelText: '${field.label}${field.required ? ' *' : ''}',
                      border: const OutlineInputBorder(),
                      suffixIcon: field.secret
                          ? IconButton(
                              tooltip: visible ? 'Скрыть' : 'Показать',
                              icon: Icon(visible ? Icons.visibility_off : Icons.visibility),
                              onPressed: () => setState(() {
                                visible ? visibleSecrets.remove(field.id) : visibleSecrets.add(field.id);
                              }),
                            )
                          : null,
                    ),
                  ),
                );
              }),
              if (widget.supportsAttachments) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Вложения SPB Wallet', style: Theme.of(context).textTheme.titleSmall),
                ),
                const SizedBox(height: 8),
                ...attachments.where((attachment) => !attachment.deleted).map((attachment) {
                  final subtitle = attachment.decodeError != null
                      ? 'Ошибка чтения: ${attachment.decodeError}'
                      : attachment.pendingBytes != null
                          ? 'Будет записано: ${attachment.pendingBytes!.length} байт'
                          : attachment.size >= 0
                              ? '${attachment.size} байт'
                              : 'Размер неизвестен';
                  return Card(
                    elevation: 0,
                    child: ListTile(
                      leading: const Icon(Icons.attach_file),
                      title: Text(attachment.fileName),
                      subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
                      trailing: Wrap(
                        spacing: 4,
                        children: [
                          IconButton(
                            tooltip: 'Заменить файл',
                            icon: const Icon(Icons.drive_file_move_outline),
                            onPressed: () => replaceAttachment(attachment),
                          ),
                          IconButton(
                            tooltip: 'Удалить вложение',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => setState(() {
                              attachments = attachments
                                  .map((entry) => entry.id == attachment.id ? entry.copyWith(deleted: true) : entry)
                                  .toList();
                            }),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: addAttachment,
                    icon: const Icon(Icons.add),
                    label: const Text('Добавить вложение'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton(
          onPressed: () {
            Navigator.pop(
              context,
              SecretItem(
                id: widget.initial?.id ?? makeId('item'),
                templateId: templateId,
                title: title.text.trim().isEmpty ? template.name : title.text.trim(),
                category: category.text.trim(),
                colorId: colorId,
                values: {for (final entry in values.entries) entry.key: entry.value.text.trim()},
                attachments: attachments,
                modifiedAt: DateTime.now(),
                hitCount: widget.initial?.hitCount ?? 0,
              ),
            );
          },
          child: const Text('Сохранить'),
        ),
      ],
    );
  }

  Future<void> addAttachment() async {
    final picked = await FilePicker.platform.pickFiles(withData: true);
    final file = picked?.files.single;
    if (file == null) return;
    final bytes = file.bytes ?? (file.path == null ? null : await File(file.path!).readAsBytes());
    if (bytes == null) return;
    setState(() {
      attachments = [
        ...attachments,
        SecretAttachment(
          id: '',
          fileName: file.name,
          size: bytes.length,
          pendingBytes: bytes,
        ),
      ];
    });
  }

  Future<void> replaceAttachment(SecretAttachment attachment) async {
    final picked = await FilePicker.platform.pickFiles(withData: true);
    final file = picked?.files.single;
    if (file == null) return;
    final bytes = file.bytes ?? (file.path == null ? null : await File(file.path!).readAsBytes());
    if (bytes == null) return;
    setState(() {
      attachments = attachments
          .map((entry) => entry.id == attachment.id
              ? entry.copyWith(
                  fileName: file.name,
                  size: bytes.length,
                  decodeError: null,
                  pendingBytes: bytes,
                )
              : entry)
          .toList();
    });
  }
}

class TemplateEditorDialog extends StatefulWidget {
  const TemplateEditorDialog({this.initial, super.key});

  final CardTemplate? initial;

  @override
  State<TemplateEditorDialog> createState() => _TemplateEditorDialogState();
}

class _TemplateEditorDialogState extends State<TemplateEditorDialog> {
  late final TextEditingController name;
  late String iconId;
  late String colorId;

  @override
  void initState() {
    super.initState();
    name = TextEditingController(text: widget.initial?.name ?? '');
    iconId = widget.initial?.iconId ?? 'key';
    colorId = widget.initial?.colorId ?? 'neutral';
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Шаблон'),
      content: SizedBox(
        width: min(MediaQuery.of(context).size.width - 48, 620),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Название шаблона', border: OutlineInputBorder())),
              const SizedBox(height: 14),
              const Text('Пиктограмма'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: templateIcons.map((icon) => ChoiceChip(
                      selected: icon.id == iconId,
                      label: Text('${icon.symbol} ${icon.label}'),
                      onSelected: (_) => setState(() => iconId = icon.id),
                    )).toList(),
              ),
              const SizedBox(height: 14),
              const Text('Новый пользовательский шаблон стартует с полями “Логин”, “Пароль” и “Заметки”. Секретные поля всегда получают кнопку-глаз.'),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton(
          onPressed: () {
            Navigator.pop(
              context,
              CardTemplate(
                id: widget.initial?.id ?? makeId('tpl'),
                name: name.text.trim().isEmpty ? 'Новый шаблон' : name.text.trim(),
                iconId: iconId,
                colorId: colorId,
                builtIn: widget.initial?.builtIn ?? false,
                fields: const [
                  FieldDefinition(id: 'username', label: 'Логин', type: 'username'),
                  FieldDefinition(id: 'password', label: 'Пароль', type: 'password', secret: true),
                  FieldDefinition(id: 'notes', label: 'Заметки', type: 'multiline_note'),
                ],
              ),
            );
          },
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}

class ColorPicker extends StatelessWidget {
  const ColorPicker({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Цвет карточки'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: palette.map((color) {
            final selected = color.id == value;
            return Tooltip(
              message: color.label,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => onChanged(color.id),
                child: Container(
                  width: 34,
                  height: 34,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected ? Theme.of(context).colorScheme.primary : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: CircleAvatar(backgroundColor: color.bg),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
