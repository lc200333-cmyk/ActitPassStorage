import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

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

  factory FieldDefinition.fromJson(Map<String, dynamic> json) =>
      FieldDefinition(
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
            .map((field) =>
                FieldDefinition.fromJson(field as Map<String, dynamic>))
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
    this.iconId,
    this.backgroundImageBase64,
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
  final String? iconId;
  final String? backgroundImageBase64;

  Map<String, dynamic> toJson() => {
        'id': id,
        'templateId': templateId,
        'title': title,
        'category': category,
        'colorId': colorId,
        'values': values,
        'modifiedAt': modifiedAt.toIso8601String(),
        'attachments':
            attachments.map((attachment) => attachment.toJson()).toList(),
        'hitCount': hitCount,
        'iconId': iconId,
        'backgroundImageBase64': backgroundImageBase64,
      };

  factory SecretItem.fromJson(Map<String, dynamic> json) => SecretItem(
        id: json['id'] as String,
        templateId: json['templateId'] as String,
        title: json['title'] as String,
        category: json['category'] as String? ?? '',
        colorId: json['colorId'] as String? ?? 'neutral',
        values:
            Map<String, String>.from(json['values'] as Map<dynamic, dynamic>),
        modifiedAt: DateTime.parse(json['modifiedAt'] as String),
        attachments: (json['attachments'] as List<dynamic>? ?? [])
            .map((attachment) =>
                SecretAttachment.fromJson(attachment as Map<String, dynamic>))
            .toList(),
        hitCount: json['hitCount'] as int? ?? 0,
        iconId: json['iconId'] as String?,
        backgroundImageBase64: json['backgroundImageBase64'] as String?,
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

  factory SecretAttachment.fromJson(Map<String, dynamic> json) =>
      SecretAttachment(
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

class ExistingVault {
  const ExistingVault({required this.title, this.path});

  final String title;
  final String? path;
}

abstract class VaultSession {
  Future<void> load();
  Future<void> saveItem(SecretItem item);
  Future<void> deleteItem(String itemId);
  Future<void> saveTemplate(CardTemplate template);
  Future<void> saveAttachment(String itemId, SecretAttachment attachment);
  Future<void> close();
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
        cardColor: paletteColorToSpb(item.colorId),
        iconId:
            item.iconId == null ? null : syntheticSpbIconIdForUi(item.iconId!),
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
        iconId: syntheticSpbIconIdForUi(template.iconId),
        fields: template.fields
            .where((field) => field.id != spbDescriptionFieldId)
            .map((field) => SpbWalletTemplateFieldRecord(
                id: field.id,
                name: field.label,
                templateId: template.id,
                fieldTypeId: spbFieldTypeId(field)))
            .toList(),
      ),
    );
    await load();
  }

  @override
  Future<void> saveAttachment(
      String itemId, SecretAttachment attachment) async {
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
  TemplateIcon('lock', 'Замок', '🔒'),
  TemplateIcon('unlock', 'Открытый замок', '🔓'),
  TemplateIcon('safe', 'Сейф', '🧰'),
  TemplateIcon('briefcase', 'Портфель', '💼'),
  TemplateIcon('folder', 'Папка', '📁'),
  TemplateIcon('file', 'Файл', '📄'),
  TemplateIcon('bookmark', 'Закладка', '🔖'),
  TemplateIcon('tag', 'Метка', '🏷️'),
  TemplateIcon('receipt', 'Чек', '🧾'),
  TemplateIcon('money', 'Деньги', '💵'),
  TemplateIcon('coin', 'Монеты', '🪙'),
  TemplateIcon('wallet', 'Кошелек', '👛'),
  TemplateIcon('chart', 'График', '📈'),
  TemplateIcon('calculator', 'Калькулятор', '🧮'),
  TemplateIcon('home', 'Дом', '🏠'),
  TemplateIcon('car', 'Авто', '🚗'),
  TemplateIcon('plane', 'Самолет', '✈️'),
  TemplateIcon('train', 'Поезд', '🚆'),
  TemplateIcon('passport', 'Паспорт', '🛂'),
  TemplateIcon('ticket', 'Билет', '🎫'),
  TemplateIcon('phone', 'Телефон', '📱'),
  TemplateIcon('desktop', 'Компьютер', '🖥️'),
  TemplateIcon('laptop', 'Ноутбук', '💻'),
  TemplateIcon('printer', 'Принтер', '🖨️'),
  TemplateIcon('keyboard', 'Клавиатура', '⌨️'),
  TemplateIcon('mouse', 'Мышь', '🖱️'),
  TemplateIcon('disk', 'Диск', '💾'),
  TemplateIcon('cd', 'Диск', '💿'),
  TemplateIcon('camera', 'Камера', '📷'),
  TemplateIcon('video', 'Видео', '🎥'),
  TemplateIcon('tv', 'Телевизор', '📺'),
  TemplateIcon('game', 'Игры', '🎮'),
  TemplateIcon('headphones', 'Наушники', '🎧'),
  TemplateIcon('watch', 'Часы', '⌚'),
  TemplateIcon('satellite', 'Связь', '📡'),
  TemplateIcon('globe', 'Сайт', '🌐'),
  TemplateIcon('link', 'Ссылка', '🔗'),
  TemplateIcon('cloud', 'Облако', '☁️'),
  TemplateIcon('database', 'База данных', '🗄️'),
  TemplateIcon('gear', 'Настройки', '⚙️'),
  TemplateIcon('tool', 'Инструмент', '🛠️'),
  TemplateIcon('wrench', 'Ключ', '🔧'),
  TemplateIcon('bug', 'Багтрекер', '🐞'),
  TemplateIcon('code', 'Код', '💻'),
  TemplateIcon('package', 'Пакет', '📦'),
  TemplateIcon('rocket', 'Проект', '🚀'),
  TemplateIcon('lab', 'Лаборатория', '🧪'),
  TemplateIcon('medical', 'Медицина', '⚕️'),
  TemplateIcon('heart', 'Здоровье', '❤️'),
  TemplateIcon('pill', 'Лекарства', '💊'),
  TemplateIcon('school', 'Учеба', '🎓'),
  TemplateIcon('book', 'Книга', '📚'),
  TemplateIcon('pen', 'Ручка', '🖊️'),
  TemplateIcon('clipboard', 'Буфер', '📋'),
  TemplateIcon('calendar', 'Календарь', '📅'),
  TemplateIcon('clock', 'Время', '⏰'),
  TemplateIcon('pin', 'PIN', '📌'),
  TemplateIcon('location', 'Адрес', '📍'),
  TemplateIcon('map', 'Карта', '🗺️'),
  TemplateIcon('house_key', 'Ключи дома', '🗝️'),
  TemplateIcon('building', 'Компания', '🏢'),
  TemplateIcon('shop', 'Магазин', '🏬'),
  TemplateIcon('factory', 'Производство', '🏭'),
  TemplateIcon('hammer', 'Работа', '🔨'),
  TemplateIcon('scales', 'Документы', '⚖️'),
  TemplateIcon('certificate', 'Сертификат', '📜'),
  TemplateIcon('medal', 'Награда', '🏅'),
  TemplateIcon('star', 'Избранное', '⭐'),
  TemplateIcon('warning', 'Важно', '⚠️'),
  TemplateIcon('bell', 'Напоминание', '🔔'),
  TemplateIcon('gift', 'Подарок', '🎁'),
  TemplateIcon('cart', 'Покупки', '🛒'),
  TemplateIcon('food', 'Еда', '🍽️'),
  TemplateIcon('coffee', 'Кофе', '☕'),
  TemplateIcon('hotel', 'Отель', '🏨'),
  TemplateIcon('taxi', 'Такси', '🚕'),
  TemplateIcon('fuel', 'Топливо', '⛽'),
  TemplateIcon('bicycle', 'Велосипед', '🚲'),
  TemplateIcon('ship', 'Корабль', '🚢'),
  TemplateIcon('anchor', 'Якорь', '⚓'),
  TemplateIcon('crypto', 'Крипто', '₿'),
  TemplateIcon('diamond', 'Ценности', '💎'),
  TemplateIcon('gem', 'Драгоценности', '💍'),
  TemplateIcon('mailbox', 'Почтовый ящик', '📫'),
  TemplateIcon('inbox', 'Входящие', '📥'),
  TemplateIcon('outbox', 'Исходящие', '📤'),
  TemplateIcon('chat', 'Чат', '💬'),
  TemplateIcon('contact', 'Контакт', '👤'),
  TemplateIcon('group', 'Группа', '👥'),
  TemplateIcon('family', 'Семья', '👪'),
  TemplateIcon('fingerprint', 'Биометрия', '🫆'),
  TemplateIcon('magnifier', 'Поиск', '🔎'),
  TemplateIcon('battery', 'Питание', '🔋'),
  TemplateIcon('plug', 'Подключение', '🔌'),
  TemplateIcon('fire', 'Срочно', '🔥'),
  TemplateIcon('snowflake', 'Архив', '❄️'),
  TemplateIcon('plant', 'Сад', '🌱'),
  TemplateIcon('tree', 'Участок', '🌳'),
  TemplateIcon('sun', 'Свет', '☀️'),
  TemplateIcon('moon', 'Ночь', '🌙'),
  TemplateIcon('umbrella', 'Страховка', '☂️'),
  TemplateIcon('magnet', 'Магнит', '🧲'),
  TemplateIcon('dna', 'Данные', '🧬'),
  TemplateIcon('microchip', 'Чип', '🔬'),
  TemplateIcon('qr', 'QR', '▪️'),
  TemplateIcon('check', 'Проверено', '✅'),
  TemplateIcon('cross', 'Ошибка', '❌'),
  TemplateIcon('plus', 'Дополнительно', '➕'),
  TemplateIcon('minus', 'Вычет', '➖'),
  TemplateIcon('question', 'Вопрос', '❓'),
  TemplateIcon('info', 'Информация', 'ℹ️'),
];

const quickTemplateIconIds = [
  'key',
  'note',
  'card',
  'id',
  'server',
  'license',
  'wifi',
  'bank',
  'mail',
  'shield',
];

List<TemplateIcon> quickTemplateIcons(String selectedIconId) {
  final selected = iconById(selectedIconId);
  final icons = [
    ...quickTemplateIconIds.map(iconById),
    if (!quickTemplateIconIds.contains(selected.id)) selected,
  ];
  final seen = <String>{};
  return [
    for (final icon in icons)
      if (seen.add(icon.id)) icon,
  ];
}

List<CardTemplate> builtInTemplates() => const [
      CardTemplate(
        id: 'tpl_password',
        name: 'Пароль',
        iconId: 'key',
        colorId: 'blue',
        builtIn: true,
        fields: [
          FieldDefinition(id: 'username', label: 'Логин', type: 'username'),
          FieldDefinition(
              id: 'password',
              label: 'Пароль',
              type: 'password',
              required: true,
              secret: true),
          FieldDefinition(id: 'url', label: 'Сайт', type: 'url'),
          FieldDefinition(
              id: 'notes', label: 'Заметки', type: 'multiline_note'),
        ],
      ),
      CardTemplate(
        id: 'tpl_note',
        name: 'Защищенная заметка',
        iconId: 'note',
        colorId: 'neutral',
        builtIn: true,
        fields: [
          FieldDefinition(
              id: 'note',
              label: 'Текст заметки',
              type: 'multiline_note',
              required: true),
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
          FieldDefinition(
              id: 'number',
              label: 'Номер карты',
              type: 'custom_secret',
              required: true),
          FieldDefinition(id: 'expires', label: 'Действует до', type: 'date'),
          FieldDefinition(
              id: 'cvv', label: 'CVV', type: 'password', secret: true),
        ],
      ),
      CardTemplate(
        id: 'tpl_identity',
        name: 'Документ',
        iconId: 'id',
        colorId: 'violet',
        builtIn: true,
        fields: [
          FieldDefinition(
              id: 'full_name', label: 'ФИО', type: 'text', required: true),
          FieldDefinition(
              id: 'document_number',
              label: 'Номер документа',
              type: 'custom_secret',
              required: true),
          FieldDefinition(id: 'issued_at', label: 'Дата выдачи', type: 'date'),
          FieldDefinition(
              id: 'notes', label: 'Заметки', type: 'multiline_note'),
        ],
      ),
      CardTemplate(
        id: 'tpl_server',
        name: 'Доступ к серверу',
        iconId: 'server',
        colorId: 'green',
        builtIn: true,
        fields: [
          FieldDefinition(
              id: 'host', label: 'Хост', type: 'url', required: true),
          FieldDefinition(
              id: 'username',
              label: 'Пользователь',
              type: 'username',
              required: true),
          FieldDefinition(
              id: 'password',
              label: 'Пароль или фраза ключа',
              type: 'password',
              secret: true),
          FieldDefinition(
              id: 'notes', label: 'Заметки', type: 'multiline_note'),
        ],
      ),
      CardTemplate(
        id: 'tpl_license',
        name: 'Лицензия ПО',
        iconId: 'license',
        colorId: 'amber',
        builtIn: true,
        fields: [
          FieldDefinition(
              id: 'product', label: 'Продукт', type: 'text', required: true),
          FieldDefinition(
              id: 'license_key',
              label: 'Лицензионный ключ',
              type: 'custom_secret',
              required: true),
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
          FieldDefinition(
              id: 'ssid', label: 'Название сети', type: 'text', required: true),
          FieldDefinition(
              id: 'password',
              label: 'Пароль Wi-Fi',
              type: 'password',
              required: true,
              secret: true),
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
          FieldDefinition(
              id: 'bank', label: 'Банк', type: 'text', required: true),
          FieldDefinition(
              id: 'account',
              label: 'Номер счета',
              type: 'custom_secret',
              required: true),
          FieldDefinition(
              id: 'login', label: 'Логин интернет-банка', type: 'username'),
          FieldDefinition(
              id: 'password',
              label: 'Пароль интернет-банка',
              type: 'password',
              secret: true),
        ],
      ),
    ];

PaletteColor colorById(String id) => palette.firstWhere(
      (color) => color.id == id,
      orElse: () => palette.first,
    );

int paletteColorToSpb(String colorId) =>
    colorById(colorId).bg.toARGB32() & 0x00ffffff;

String spbColorToPaletteId(int color) {
  final normalized = color & 0x00ffffff;
  if (normalized == 0xffffff) return 'neutral';
  var best = palette.first;
  var bestDistance = 1 << 62;
  for (final candidate in palette) {
    final value = candidate.bg.toARGB32() & 0x00ffffff;
    final dr = ((normalized >> 16) & 0xff) - ((value >> 16) & 0xff);
    final dg = ((normalized >> 8) & 0xff) - ((value >> 8) & 0xff);
    final db = (normalized & 0xff) - (value & 0xff);
    final distance = dr * dr + dg * dg + db * db;
    if (distance < bestDistance) {
      best = candidate;
      bestDistance = distance;
    }
  }
  return best.id;
}

TemplateIcon iconById(String id) => templateIcons.firstWhere(
      (icon) => icon.id == id,
      orElse: () => templateIcons.first,
    );

String defaultIconForTemplateName(String name, Iterable<String> fieldLabels) {
  final text = ([name, ...fieldLabels]).join(' ').toLowerCase();
  if (text.contains('банк') ||
      text.contains('bank') ||
      text.contains('счет') ||
      text.contains('account')) {
    return 'bank';
  }
  if (text.contains('карта') || text.contains('card') || text.contains('cvv')) {
    return 'card';
  }
  if (text.contains('wi-fi') ||
      text.contains('wifi') ||
      text.contains('ssid')) {
    return 'wifi';
  }
  if (text.contains('почт') ||
      text.contains('mail') ||
      text.contains('email')) {
    return 'mail';
  }
  if (text.contains('паспорт') ||
      text.contains('документ') ||
      text.contains('удостовер') ||
      text.contains('document') ||
      text.contains('identity')) {
    return 'id';
  }
  if (text.contains('сервер') ||
      text.contains('server') ||
      text.contains('ssh') ||
      text.contains('host')) {
    return 'server';
  }
  if (text.contains('лиценз') ||
      text.contains('license') ||
      text.contains('ключ продукта')) {
    return 'license';
  }
  if (text.contains('замет') ||
      text.contains('note') ||
      text.contains('memo')) {
    return 'note';
  }
  if (text.contains('телефон') || text.contains('phone')) return 'phone';
  if (text.contains('сайт') ||
      text.contains('url') ||
      text.contains('web') ||
      text.contains('internet')) {
    return 'globe';
  }
  if (text.contains('облак') || text.contains('cloud')) return 'cloud';
  if (text.contains('база') || text.contains('database')) return 'database';
  if (text.contains('крипт') ||
      text.contains('bitcoin') ||
      text.contains('crypto')) {
    return 'crypto';
  }
  if (text.contains('pin') ||
      text.contains('парол') ||
      text.contains('password') ||
      text.contains('логин')) {
    return 'key';
  }
  return 'key';
}

String itemIconId(SecretItem item, CardTemplate template) {
  final iconId = item.iconId;
  return iconId == null || iconId.isEmpty ? template.iconId : iconId;
}

String syntheticSpbIconIdForUi(String uiIconId) {
  var first = 2166136261;
  var second = 2166136261 ^ 0x9e3779b9;
  for (final codeUnit in 'actitpass-icon:$uiIconId'.codeUnits) {
    first ^= codeUnit;
    first = (first * 16777619) & 0xffffffff;
    second ^= codeUnit + 31;
    second = (second * 16777619) & 0xffffffff;
  }
  return first.toRadixString(16).padLeft(8, '0').toUpperCase() +
      second.toRadixString(16).padLeft(8, '0').toUpperCase();
}

String? uiIconIdFromSyntheticSpbIcon(String spbIconId) {
  final normalized = spbIconId.toUpperCase();
  for (final icon in templateIcons) {
    if (syntheticSpbIconIdForUi(icon.id) == normalized) return icon.id;
  }
  return null;
}

String makeId(String prefix) {
  final random = Random.secure();
  final suffix =
      List.generate(12, (_) => random.nextInt(16).toRadixString(16)).join();
  return '${prefix}_$suffix';
}

enum EntryMode { openSwl, createSwl }

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

String normalizeUrlInput(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty ||
      RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(trimmed)) {
    return trimmed;
  }
  return 'https://$trimmed';
}

String formatDateInput(DateTime date) {
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  final year = date.year.toString().padLeft(4, '0');
  return '$day.$month.$year';
}

DateTime? parseDateInput(String value) {
  final trimmed = value.trim();
  final dotted = RegExp(r'^(\d{2})\.(\d{2})\.(\d{4})$').firstMatch(trimmed);
  if (dotted != null) {
    final day = int.parse(dotted.group(1)!);
    final month = int.parse(dotted.group(2)!);
    final year = int.parse(dotted.group(3)!);
    return validDate(year, month, day);
  }
  final iso = RegExp(r'^(\d{4})-(\d{2})(?:-(\d{2}))?$').firstMatch(trimmed);
  if (iso != null) {
    final year = int.parse(iso.group(1)!);
    final month = int.parse(iso.group(2)!);
    final day = int.parse(iso.group(3) ?? '1');
    return validDate(year, month, day);
  }
  return null;
}

DateTime? validDate(int year, int month, int day) {
  if (year < 1 || month < 1 || month > 12 || day < 1) return null;
  final date = DateTime(year, month, day);
  if (date.year != year || date.month != month || date.day != day) {
    return null;
  }
  return date;
}

class DateTextInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final trimmed = digits.length > 8 ? digits.substring(0, 8) : digits;
    final parts = <String>[];
    if (trimmed.isNotEmpty) {
      parts.add(trimmed.length <= 2 ? trimmed : trimmed.substring(0, 2));
    }
    if (trimmed.length > 2) {
      parts.add(
          trimmed.length <= 4 ? trimmed.substring(2) : trimmed.substring(2, 4));
    }
    if (trimmed.length > 4) {
      parts.add(trimmed.substring(4));
    }
    final text = parts.join('.');
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
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

  EntryMode entryMode = EntryMode.openSwl;
  bool showPassword = false;
  bool showConfirm = false;
  bool unlocked = false;
  bool? menuOpenOverride;
  String activeView = 'cards';
  String? message;
  String? spbWalletPath;
  String? spbWalletUri;
  String? syncSourcePath;
  String? syncSourceUrl;
  String? syncOriginProvider;
  SpbWalletDatabase? spbWallet;
  String syncProvider = 'mounted_folder';
  String templateFilter = '';
  String sortMode = 'modified_desc';
  String? selectedItemId;
  DateTime? lastSyncAt;

  List<CardTemplate> templates = builtInTemplates();
  List<SecretItem> items = [];
  List<ConflictRecord> conflicts = [];
  List<ExistingVault> recentVaults = [];
  final Map<String, String> spbIconIdByUiIcon = {};
  final Set<String> revealed = {};
  final Map<String, String> syncConfig = {};

  bool get createMode => entryMode == EntryMode.createSwl;

  File get swlVaultFile {
    final safeName = vaultNameController.text.trim().isEmpty
        ? 'personal'
        : vaultNameController.text.trim();
    final sanitized =
        safeName.replaceAll(RegExp(r'[^\wа-яА-ЯёЁ.-]+', unicode: true), '_');
    return File('${Directory.systemTemp.path}/$sanitized.swl');
  }

  File get recentVaultsFile =>
      File('${Directory.systemTemp.path}/actitpass_recent_swl.json');

  @override
  void initState() {
    super.initState();
    searchController.addListener(() => setState(() {}));
    loadRecentVaults();
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
    if (entryMode == EntryMode.openSwl) {
      if (spbWalletPath == null || spbWalletPath!.isEmpty) {
        setState(() => message = 'Выберите файл базы .swl.');
        return;
      }
      try {
        spbWallet?.close();
        final wallet = SpbWalletDatabase.open(spbWalletPath!, password);
        final snapshot = wallet.loadSnapshot();
        spbWallet = wallet;
        spbIconIdByUiIcon.clear();
        setState(() {
          templates = spbTemplatesToUi(snapshot.templates);
          items = spbCardsToUi(snapshot.cards);
          conflicts = [];
          lastSyncAt = null;
          syncSourcePath = null;
          syncSourceUrl = null;
          syncOriginProvider = null;
          selectedItemId = items.isEmpty ? null : items.first.id;
          unlocked = true;
          activeView = 'cards';
          message = null;
        });
        await rememberRecentVault(spbWalletPath!);
      } catch (error) {
        setState(() => message = 'Не удалось открыть .swl базу: $error');
      }
      return;
    }
    if (createMode && password != confirmController.text) {
      setState(() => message = 'Пароли не совпадают.');
      return;
    }
    if (createMode) {
      try {
        await createSwlVault(password);
      } catch (error) {
        setState(() => message = 'Не удалось создать .swl базу: $error');
      }
      return;
    }
  }

  Future<void> pickSpbWalletFile() async {
    if (Platform.isAndroid) {
      try {
        final picked = await spbWalletChannel
            .invokeMapMethod<String, Object?>('pickSpbWallet');
        if (picked == null) return;
        final path = picked['localPath']?.toString();
        if (path == null || path.isEmpty) return;
        setState(() {
          spbWalletPath = path;
          spbWalletUri = picked['uri']?.toString();
          vaultNameController.text = picked['displayName']?.toString() ??
              File(path).uri.pathSegments.last;
          message = null;
        });
        await rememberRecentVault(path);
      } catch (error) {
        setState(() => message = 'Не удалось выбрать .swl файл: $error');
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
      syncSourcePath = null;
      syncSourceUrl = null;
      syncOriginProvider = null;
      vaultNameController.text = File(path).uri.pathSegments.last;
      message = null;
    });
    await rememberRecentVault(path);
  }

  Future<void> loadRecentVaults() async {
    final found = <ExistingVault>[];
    try {
      if (recentVaultsFile.existsSync()) {
        final decoded =
            jsonDecode(await recentVaultsFile.readAsString()) as List<dynamic>;
        for (final rawPath in decoded.whereType<String>()) {
          final file = File(rawPath);
          if (!file.existsSync() || !file.path.toLowerCase().endsWith('.swl')) {
            continue;
          }
          final title = file.uri.pathSegments.isEmpty
              ? file.path
              : file.uri.pathSegments.last;
          if (found.any((vault) => vault.path == file.path)) continue;
          found.add(ExistingVault(title: title, path: file.path));
        }
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() => recentVaults = found);
  }

  Future<void> rememberRecentVault(String path) async {
    if (path.isEmpty) return;
    final paths = [
      path,
      ...recentVaults
          .map((vault) => vault.path)
          .whereType<String>()
          .where((entry) => entry != path),
    ].take(8).toList();
    await recentVaultsFile.writeAsString(jsonEncode(paths));
    if (!mounted) return;
    setState(() {
      recentVaults = paths
          .where((entry) => File(entry).existsSync())
          .map((entry) => ExistingVault(
                title: File(entry).uri.pathSegments.isEmpty
                    ? entry
                    : File(entry).uri.pathSegments.last,
                path: entry,
              ))
          .toList();
    });
  }

  Future<void> createSwlVault(String password) async {
    final file = swlVaultFile;
    final wallet = SpbWalletDatabase.create(file.path, password);
    spbIconIdByUiIcon.clear();
    final sourceTemplates = builtInTemplates();
    final templateMap = <String, CardTemplate>{};
    for (final template in sourceTemplates) {
      final prepared = prepareSpbTemplate(template, true);
      templateMap[template.id] = prepared;
      wallet.saveTemplate(
        SpbWalletTemplateDraft(
          id: prepared.id,
          name: prepared.name,
          iconId: syntheticSpbIconIdForUi(prepared.iconId),
          fields: prepared.fields
              .where((field) => field.id != spbDescriptionFieldId)
              .map((field) => SpbWalletTemplateFieldRecord(
                  id: field.id,
                  name: field.label,
                  templateId: prepared.id,
                  fieldTypeId: spbFieldTypeId(field)))
              .toList(),
        ),
      );
    }

    for (final item in demoItems()) {
      final template = templateMap[item.templateId];
      if (template == null) continue;
      final original =
          sourceTemplates.firstWhere((entry) => entry.id == item.templateId);
      final fieldMap = <String, String>{};
      for (var i = 0;
          i < original.fields.length && i < template.fields.length;
          i++) {
        fieldMap[original.fields[i].id] = template.fields[i].id;
      }
      wallet.saveCard(
        SpbWalletCardDraft(
          id: SpbWalletDatabase.makeId(),
          title: item.title,
          description: '',
          categoryPath: item.category,
          templateId: template.id,
          iconId: syntheticSpbIconIdForUi(item.iconId ?? template.iconId),
          fieldValues: {
            for (final entry in item.values.entries)
              if (fieldMap[entry.key] != null)
                fieldMap[entry.key]!: entry.value,
          },
          cardColor: paletteColorToSpb(item.colorId),
          backgroundImageBase64: item.backgroundImageBase64,
        ),
      );
    }

    final snapshot = wallet.loadSnapshot();
    spbWallet?.close();
    spbWallet = wallet;
    setState(() {
      spbWalletPath = file.path;
      spbWalletUri = null;
      syncSourcePath = null;
      syncSourceUrl = null;
      syncOriginProvider = null;
      templates = spbTemplatesToUi(snapshot.templates);
      items = spbCardsToUi(snapshot.cards);
      conflicts = [];
      lastSyncAt = null;
      selectedItemId = items.isEmpty ? null : items.first.id;
      unlocked = true;
      activeView = 'cards';
      message = null;
    });
    await rememberRecentVault(file.path);
  }

  Future<void> connectSyncVault(String password) async {
    if (syncProvider == 'mounted_folder') {
      final source = resolveMountedFolderSyncFile();
      final localName = vaultNameController.text.trim().isEmpty
          ? source.uri.pathSegments.last
              .replaceAll(RegExp(r'\.swl$', caseSensitive: false), '')
          : vaultNameController.text.trim();
      vaultNameController.text = localName;
      final local = swlVaultFile;
      await source.copy(local.path);
      await openSyncedLocalWallet(
        localPath: local.path,
        password: password,
        sourcePath: source.path,
        sourceUrl: null,
      );
      return;
    }
    if (syncProvider == 'webdav') {
      final uri = webDavSyncUri();
      final bytes = await downloadWebDavVault(uri);
      final localName = vaultNameController.text.trim().isEmpty
          ? webDavFileName(uri)
              .replaceAll(RegExp(r'\.swl$', caseSensitive: false), '')
          : vaultNameController.text.trim();
      vaultNameController.text = localName;
      final local = swlVaultFile;
      await local.writeAsBytes(bytes, flush: true);
      await openSyncedLocalWallet(
        localPath: local.path,
        password: password,
        sourcePath: null,
        sourceUrl: uri.toString(),
      );
      return;
    }
    throw StateError(
        'Для автоматического подключения сейчас поддержаны папка/SMB/NFS и WebDAV. Для SFTP/FTP/почты сначала подключите хранилище как папку или откройте .swl файл вручную.');
  }

  Future<void> openSyncedLocalWallet({
    required String localPath,
    required String password,
    required String? sourcePath,
    required String? sourceUrl,
  }) async {
    spbWallet?.close();
    final wallet = SpbWalletDatabase.open(localPath, password);
    final snapshot = wallet.loadSnapshot();
    spbWallet = wallet;
    spbIconIdByUiIcon.clear();
    setState(() {
      spbWalletPath = localPath;
      spbWalletUri = null;
      syncSourcePath = sourcePath;
      syncSourceUrl = sourceUrl;
      syncOriginProvider = syncProvider;
      templates = spbTemplatesToUi(snapshot.templates);
      items = spbCardsToUi(snapshot.cards);
      conflicts = [];
      lastSyncAt = DateTime.now();
      selectedItemId = items.isEmpty ? null : items.first.id;
      unlocked = true;
      activeView = 'cards';
      message = null;
    });
    await rememberRecentVault(localPath);
  }

  File resolveMountedFolderSyncFile() {
    final directoryPath = syncConfig['mounted_folder:directory']?.trim() ?? '';
    if (directoryPath.isEmpty) {
      throw StateError('Укажите путь к папке с .swl файлом.');
    }
    final directory = Directory(directoryPath);
    if (!directory.existsSync()) {
      throw StateError('Папка не найдена: $directoryPath');
    }
    final configuredName = syncConfig['mounted_folder:database']?.trim() ?? '';
    if (configuredName.isNotEmpty) {
      final file =
          File('${directory.path}${Platform.pathSeparator}$configuredName');
      if (!file.existsSync()) {
        throw StateError('В папке нет файла $configuredName.');
      }
      return file;
    }
    final swlFiles = directory
        .listSync(followLinks: false)
        .whereType<File>()
        .where((file) => file.path.toLowerCase().endsWith('.swl'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    if (swlFiles.isEmpty) throw StateError('В папке нет .swl базы.');
    if (swlFiles.length > 1) {
      throw StateError(
          'В папке несколько .swl баз. Укажите имя файла в поле “Имя .swl файла”.');
    }
    return swlFiles.single;
  }

  Uri webDavSyncUri() {
    final rawUrl = syncConfig['webdav:url']?.trim() ?? '';
    if (rawUrl.isEmpty) throw StateError('Укажите WebDAV URL.');
    final base = Uri.parse(rawUrl);
    if (base.path.toLowerCase().endsWith('.swl')) return base;
    final configuredName = syncConfig['webdav:database']?.trim() ?? '';
    final fileName = configuredName.isEmpty
        ? '${vaultNameController.text.trim().isEmpty ? 'personal' : vaultNameController.text.trim()}.swl'
        : configuredName;
    final separator = rawUrl.endsWith('/') ? '' : '/';
    return Uri.parse('$rawUrl$separator${Uri.encodeComponent(fileName)}');
  }

  String webDavFileName(Uri uri) =>
      uri.pathSegments.isEmpty ? 'personal.swl' : uri.pathSegments.last;

  Future<List<int>> downloadWebDavVault(Uri uri) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      applyWebDavAuth(request);
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('WebDAV вернул HTTP ${response.statusCode}.');
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response) {
        bytes.add(chunk);
      }
      return bytes.takeBytes();
    } finally {
      client.close(force: true);
    }
  }

  Future<void> uploadWebDavVault(Uri uri, List<int> bytes) async {
    final client = HttpClient();
    try {
      final request = await client.putUrl(uri);
      applyWebDavAuth(request);
      request.headers.contentType = ContentType.binary;
      request.contentLength = bytes.length;
      request.add(bytes);
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError(
            'WebDAV вернул HTTP ${response.statusCode} при записи.');
      }
      await response.drain();
    } finally {
      client.close(force: true);
    }
  }

  void applyWebDavAuth(HttpClientRequest request) {
    final username = syncConfig['webdav:username']?.trim() ?? '';
    final password = syncConfig['webdav:password'] ?? '';
    if (username.isEmpty && password.isEmpty) return;
    request.headers.set(HttpHeaders.authorizationHeader,
        'Basic ${base64Encode(utf8.encode('$username:$password'))}');
  }

  void chooseExistingVault(ExistingVault vault) {
    setState(() {
      entryMode = EntryMode.openSwl;
      message = null;
      spbWalletPath = vault.path;
      spbWalletUri = null;
      syncSourcePath = null;
      syncSourceUrl = null;
      syncOriginProvider = null;
      vaultNameController.text = vault.title;
    });
  }

  Future<bool> writeBackSpbWallet() async {
    var ok = true;
    try {
      if (Platform.isAndroid && spbWalletUri != null && spbWalletPath != null) {
        await spbWalletChannel.invokeMethod<bool>('writeSpbWallet', {
          'uri': spbWalletUri,
          'localPath': spbWalletPath,
        });
      }
      if (syncSourcePath != null &&
          spbWalletPath != null &&
          syncSourcePath != spbWalletPath) {
        await File(spbWalletPath!).copy(syncSourcePath!);
      }
      if (syncSourceUrl != null && spbWalletPath != null) {
        await uploadWebDavVault(Uri.parse(syncSourceUrl!),
            await File(spbWalletPath!).readAsBytes());
      }
      if (spbWalletUri != null ||
          syncSourcePath != null ||
          syncSourceUrl != null) {
        lastSyncAt = DateTime.now();
      }
    } catch (error) {
      ok = false;
      setState(() => message =
          'Изменения сохранены во временный файл, но не записаны обратно в исходную .swl базу: $error');
    }
    return ok;
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
          'note':
              'База хранится локально в формате .swl. Изменения записываются обратно в тот же файл.',
        },
      ),
      SecretItem(
        id: makeId('item'),
        templateId: 'tpl_note',
        title: 'Открытие базы',
        category: 'О программе ActitPassStorage',
        colorId: 'neutral',
        modifiedAt: now,
        values: {
          'note':
              'На стартовом экране можно выбрать .swl файл вручную или открыть один из последних выбранных файлов.',
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
          'note':
              'У карточек есть отдельные кнопки заметок и вложений со счетчиками. Вложения сохраняются в родном zlib+AES формате .swl.',
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
        const FieldDefinition(
            id: spbDescriptionFieldId,
            label: 'Заметки',
            type: 'multiline_note'),
      ];
      final iconId = defaultIconForTemplateName(
        template.name,
        template.fields.map((field) => field.name),
      );
      rememberSpbIcon(iconId, template.iconId);
      return CardTemplate(
        id: template.id,
        name: template.name,
        iconId: iconId,
        colorId: 'neutral',
        fields: fields,
      );
    }).toList();
  }

  List<SecretItem> spbCardsToUi(List<SpbWalletCardRecord> source) {
    return source.map((card) {
      final template = templateFor(card.templateId);
      final iconId = uiIconForSpbIcon(card.iconId) ?? template.iconId;
      rememberSpbIcon(iconId, card.iconId);
      return SecretItem(
        id: card.id,
        templateId: card.templateId,
        title: card.title.isEmpty ? '.swl карточка' : card.title,
        category: card.categoryPath,
        colorId: spbColorToPaletteId(card.cardColor),
        iconId: iconId,
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
        backgroundImageBase64: card.backgroundImageBase64,
      );
    }).toList();
  }

  void rememberSpbIcon(String uiIconId, String spbIconId) {
    if (spbIconId.isEmpty || !isSpbHexId(spbIconId)) return;
    spbIconIdByUiIcon.putIfAbsent(uiIconId, () => spbIconId);
  }

  String? uiIconForSpbIcon(String spbIconId) {
    if (spbIconId.isEmpty) return null;
    final synthetic = uiIconIdFromSyntheticSpbIcon(spbIconId);
    if (synthetic != null) return synthetic;
    for (final entry in spbIconIdByUiIcon.entries) {
      if (entry.value == spbIconId) return entry.key;
    }
    return null;
  }

  String? spbIconIdForUi(String uiIconId, String fallbackUiIconId) {
    final direct = spbIconIdByUiIcon[uiIconId];
    if (direct != null && isSpbHexId(direct)) return direct;
    final fallback = spbIconIdByUiIcon[fallbackUiIconId];
    if (fallback != null && isSpbHexId(fallback)) return fallback;
    return syntheticSpbIconIdForUi(uiIconId);
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

  @override
  Widget build(BuildContext context) {
    if (!unlocked) return buildLocked();
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 820;
        final menuOpen = isMenuOpen(compact);
        return Scaffold(
          body: SafeArea(
            child: compact
                ? Column(
                    children: [
                      buildMenuHeader(compact: true),
                      if (menuOpen) buildTopRail(compact: true),
                      Expanded(child: buildContent()),
                    ],
                  )
                : Row(
                    children: [
                      SizedBox(
                          width: 52, child: buildMenuHandle(compact: false)),
                      if (menuOpen)
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

  bool isMenuOpen(bool compact) => menuOpenOverride ?? !compact;

  void toggleMenu(bool compact) {
    final current = isMenuOpen(compact);
    setState(() => menuOpenOverride = !current);
  }

  Widget buildMenuHeader({required bool compact}) {
    return Material(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Меню',
              icon: const Icon(Icons.menu),
              onPressed: () => toggleMenu(compact),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                openDatabaseTitle(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildMenuHandle({required bool compact}) {
    return Material(
      color: Colors.white,
      child: Column(
        children: [
          const SizedBox(height: 8),
          IconButton(
            tooltip: 'Меню',
            icon: const Icon(Icons.menu),
            onPressed: () => toggleMenu(compact),
          ),
        ],
      ),
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
                  openDatabaseTitle(),
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
      if (path == null || path.isEmpty) return '.swl база';
      return File(path).uri.pathSegments.isEmpty
          ? path
          : File(path).uri.pathSegments.last;
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
                      const CircleAvatar(
                          radius: 32,
                          child: Text('A', style: TextStyle(fontSize: 28))),
                      const SizedBox(height: 18),
                      Text('ActitPassStorage',
                          style: Theme.of(context).textTheme.headlineMedium),
                      const SizedBox(height: 8),
                      const Text(
                          'Менеджер паролей, заметок и настраиваемых карточек. Локальная .swl база на устройстве.'),
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
                              ButtonSegment(
                                  value: EntryMode.openSwl,
                                  label: Text('Открыть .swl')),
                              ButtonSegment(
                                  value: EntryMode.createSwl,
                                  label: Text('Создать .swl')),
                            ],
                            selected: {entryMode},
                            onSelectionChanged: (value) => setState(() {
                              entryMode = value.first;
                              message = null;
                            }),
                          ),
                          const SizedBox(height: 18),
                          if (!createMode && recentVaults.isNotEmpty) ...[
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text('Последние файлы',
                                  style:
                                      Theme.of(context).textTheme.titleSmall),
                            ),
                            const SizedBox(height: 8),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 150),
                              child: ListView.separated(
                                shrinkWrap: true,
                                itemCount: recentVaults.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 4),
                                itemBuilder: (context, index) {
                                  final vault = recentVaults[index];
                                  return ListTile(
                                    dense: true,
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8)),
                                    tileColor: Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerHighest,
                                    leading: const Icon(Icons.history),
                                    title: Text(vault.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis),
                                    subtitle: Text(vault.path ?? '',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis),
                                    onTap: () => chooseExistingVault(vault),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 14),
                          ],
                          if (!createMode) ...[
                            OutlinedButton.icon(
                              onPressed: pickSpbWalletFile,
                              icon: const Icon(Icons.folder_open),
                              label: const Text('Выбрать .swl файл'),
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                spbWalletPath == null
                                    ? 'Файл .swl не выбран'
                                    : spbWalletPath!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ] else
                            TextField(
                              controller: vaultNameController,
                              decoration: const InputDecoration(
                                  labelText: 'Название базы',
                                  border: OutlineInputBorder()),
                            ),
                          const SizedBox(height: 12),
                          PasswordField(
                            controller: passwordController,
                            label: 'Пароль .swl базы',
                            visible: showPassword,
                            onToggle: () =>
                                setState(() => showPassword = !showPassword),
                          ),
                          if (createMode) ...[
                            const SizedBox(height: 12),
                            PasswordField(
                              controller: confirmController,
                              label: 'Повторите пароль',
                              visible: showConfirm,
                              onToggle: () =>
                                  setState(() => showConfirm = !showConfirm),
                            ),
                          ],
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: unlock,
                              child: Text(entryMode == EntryMode.createSwl
                                  ? 'Создать .swl базу'
                                  : 'Открыть .swl базу'),
                            ),
                          ),
                          if (message != null) ...[
                            const SizedBox(height: 12),
                            Text(message!,
                                style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.error)),
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
              title: const Text('.swl база'),
              subtitle: Text(spbWalletPath ?? 'открытая .swl база'),
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
                syncSourcePath = null;
                syncSourceUrl = null;
                syncOriginProvider = null;
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
      ('settings', Icons.settings_outlined, 'Настройки'),
    ];
    return entries
        .map(
          (entry) => Padding(
            padding: EdgeInsets.only(
                bottom: compact ? 0 : 8, right: compact ? 8 : 0),
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
                  Text(viewTitle(),
                      style: Theme.of(context).textTheme.headlineSmall),
                  const Text(
                      'Секреты скрыты по умолчанию. Изменения сохраняются локально.'),
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
        'settings': 'Настройки',
      }[activeView]!;

  String primaryLabel() =>
      activeView == 'templates' ? 'Новый шаблон' : 'Новая карточка';

  IconData primaryIcon() =>
      activeView == 'templates' ? Icons.add_box_outlined : Icons.add;

  void primaryAction() {
    if (activeView == 'templates') {
      openTemplateDialog();
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
                decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    labelText: 'Поиск',
                    border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: 'Фильтры',
              child: IconButton.filledTonal(
                onPressed: openCardFilterDialog,
                icon: Badge(
                  isLabelVisible:
                      templateFilter.isNotEmpty || sortMode != 'modified_desc',
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
                return walletTree(filtered, openCardsInDialog: true);
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: 320, child: walletTree(filtered)),
                  const SizedBox(width: 12),
                  Expanded(
                      child: selected == null
                          ? emptyCardDetail()
                          : itemDetail(selected)),
                  const SizedBox(width: 12),
                  SizedBox(width: 230, child: spbRightPanel(filtered)),
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
                  decoration: const InputDecoration(
                      labelText: 'Шаблон', border: OutlineInputBorder()),
                  items: [
                    const DropdownMenuItem(
                        value: '', child: Text('Все шаблоны')),
                    ...templates.map((template) => DropdownMenuItem(
                        value: template.id, child: Text(template.name))),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => nextTemplateFilter = value ?? ''),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: nextSortMode,
                  decoration: const InputDecoration(
                      labelText: 'Сортировка', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(
                        value: 'modified_desc', child: Text('Сначала новые')),
                    DropdownMenuItem(
                        value: 'title_asc', child: Text('По названию')),
                    DropdownMenuItem(
                        value: 'template_asc', child: Text('По шаблону')),
                  ],
                  onChanged: (value) => setDialogState(
                      () => nextSortMode = value ?? 'modified_desc'),
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
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Отмена')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Применить')),
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
      final text =
          '${item.title} ${item.category} ${template.name} ${item.values.values.join(' ')}'
              .toLowerCase();
      return (templateFilter.isEmpty || item.templateId == templateFilter) &&
          text.contains(searchController.text.toLowerCase());
    }).toList();
    if (sortMode == 'title_asc') {
      filtered.sort((a, b) => a.title.compareTo(b.title));
    } else if (sortMode == 'template_asc') {
      filtered.sort((a, b) => templateFor(a.templateId)
          .name
          .compareTo(templateFor(b.templateId).name));
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

  Widget walletTree(List<SecretItem> source, {bool openCardsInDialog = false}) {
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
            child: const Text('Мои карточки',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          Expanded(
            child: root.isEmpty
                ? const Center(child: Text('Карточек не найдено'))
                : ListView(
                    children: [
                      ExpansionTile(
                        initiallyExpanded: true,
                        leading:
                            const Icon(Icons.account_balance_wallet_outlined),
                        title: const Text('Мой кошелёк'),
                        children: treeChildren(root, 0,
                            openCardsInDialog: openCardsInDialog),
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

  List<String> existingCategories() {
    final categories = {
      for (final item in items)
        if (item.category.trim().isNotEmpty) item.category.trim(),
    }.toList();
    categories.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return categories;
  }

  List<Widget> treeChildren(CategoryTreeNode node, int depth,
      {required bool openCardsInDialog}) {
    final children = <Widget>[];
    final folders = node.children.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    for (final folder in folders) {
      children.add(
        Padding(
          padding: EdgeInsets.only(left: depth * 10.0),
          child: ExpansionTile(
            initiallyExpanded: true,
            leading: const Icon(Icons.folder_outlined, size: 20),
            title:
                Text(folder.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            children: treeChildren(folder, depth + 1,
                openCardsInDialog: openCardsInDialog),
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
            leading: Text(iconById(itemIconId(item, template)).symbol),
            title:
                Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(template.name,
                maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () => openCardsInDialog
                ? openCardPreviewDialog(item)
                : selectItem(item),
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

  Widget spbRightPanel(List<SecretItem> visibleItems) {
    final frequent = [...items]..sort((a, b) {
        final byHits = b.hitCount.compareTo(a.hitCount);
        return byHits == 0 ? a.title.compareTo(b.title) : byHits;
      });
    final top = frequent.take(10).toList();
    final selected = selectedItem(visibleItems);
    return ListView(
      children: [
        SpbPanel(
          title: 'Задачи',
          children: [
            ListTile(
              dense: true,
              leading: const Icon(Icons.add_card_outlined),
              title: const Text('Создать новую карточку'),
              onTap: () => openItemDialog(),
            ),
            ListTile(
              dense: true,
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Редактировать'),
              enabled: selected != null,
              onTap: selected == null
                  ? null
                  : () => openItemDialog(item: selected),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SpbPanel(
          title: 'Часто используемые',
          children: [
            if (top.isEmpty)
              const ListTile(dense: true, title: Text('Пока нет данных'))
            else
              ...top.map((item) {
                final template = templateFor(item.templateId);
                return ListTile(
                  dense: true,
                  leading: Text(iconById(itemIconId(item, template)).symbol),
                  title: Text(item.title,
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  onTap: () => selectItem(item),
                );
              }),
          ],
        ),
        const SizedBox(height: 12),
        SpbPanel(
          title: 'Найти карточки',
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: TextField(
                controller: searchController,
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
      ],
    );
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
                  iconId: entry.iconId,
                  backgroundImageBase64: entry.backgroundImageBase64,
                )
              : entry,
      ];
    });
    if (spbWallet != null) {
      try {
        spbWallet!.recordCardHit(item.id);
        await writeBackSpbWallet();
      } catch (error) {
        setState(
            () => message = 'Не удалось обновить счетчик .swl базы: $error');
      }
    } else {
      setState(() => message =
          'Откройте или создайте .swl базу перед изменением карточек.');
    }
  }

  Future<void> openCardPreviewDialog(SecretItem item) async {
    await selectItem(item);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: min(MediaQuery.of(context).size.width - 24, 520),
            maxHeight: MediaQuery.of(context).size.height - 48,
          ),
          child: itemCard(item),
        ),
      ),
    );
  }

  Widget buildFrequentView() {
    final frequent = [...items]..sort((a, b) {
        final byHits = b.hitCount.compareTo(a.hitCount);
        return byHits == 0 ? a.title.compareTo(b.title) : byHits;
      });
    final top = frequent.where((item) => item.hitCount > 0).take(10).toList();
    if (top.isEmpty) {
      return const Center(
          child: Text(
              'Часто используемые карточки появятся после открытия карточек из дерева.'));
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
            leading: Text(iconById(itemIconId(item, template)).symbol,
                style: const TextStyle(fontSize: 24)),
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
    final color =
        colorById(item.colorId.isEmpty ? template.colorId : item.colorId);
    final noteCount = noteText(item).trim().isEmpty ? 0 : 1;
    final attachmentCount =
        item.attachments.where((attachment) => !attachment.deleted).length;
    final backgroundImage = backgroundImageFor(item);
    return Card(
      color: backgroundImage == null ? color.bg : Colors.white,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => openItemDialog(item: item),
        child: Container(
          decoration: backgroundImage == null
              ? null
              : BoxDecoration(
                  image: DecorationImage(
                    image: backgroundImage,
                    fit: BoxFit.cover,
                    colorFilter: ColorFilter.mode(
                        Colors.white.withValues(alpha: 0.28),
                        BlendMode.srcOver),
                  ),
                ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(iconById(itemIconId(item, template)).symbol,
                      style: const TextStyle(fontSize: 28)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontWeight: FontWeight.w700, color: color.fg)),
                        Text(template.name,
                            style: TextStyle(
                                color: color.fg.withValues(alpha: 0.72))),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  physics: const NeverScrollableScrollPhysics(),
                  children: template.fields
                      .where(
                          (field) => (item.values[field.id] ?? '').isNotEmpty)
                      .map((field) {
                    final revealKey = '${item.id}:${field.id}';
                    final isRevealed = revealed.contains(revealKey);
                    final value = item.values[field.id]!;
                    return FieldValueRow(
                      label: field.label,
                      value: field.secret && !isRevealed ? '••••••••' : value,
                      foreground: color.fg,
                      secret: field.secret,
                      revealed: isRevealed,
                      onToggle: field.secret
                          ? () => setState(() {
                                isRevealed
                                    ? revealed.remove(revealKey)
                                    : revealed.add(revealKey);
                              })
                          : null,
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                  'Категория: ${item.category.isEmpty ? 'Без категории' : item.category}',
                  style: TextStyle(color: color.fg.withValues(alpha: 0.72))),
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
                      Text('Цвет: ',
                          style: TextStyle(
                              color: color.fg.withValues(alpha: 0.72))),
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

  ImageProvider? backgroundImageFor(SecretItem item) {
    final encoded = item.backgroundImageBase64;
    if (encoded == null || encoded.isEmpty) return null;
    try {
      return MemoryImage(base64Decode(encoded));
    } catch (_) {
      return null;
    }
  }

  String noteFieldIdFor(SecretItem item) {
    final template = templateFor(item.templateId);
    if (template.fields.any((field) => field.id == spbDescriptionFieldId)) {
      return spbDescriptionFieldId;
    }
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
            decoration: const InputDecoration(
                border: OutlineInputBorder(), labelText: 'Заметка'),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Сохранить')),
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
        iconId: item.iconId,
        backgroundImageBase64: item.backgroundImageBase64,
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
            leading: CircleAvatar(
                backgroundColor: color.bg,
                foregroundColor: color.fg,
                child: Text(iconById(template.iconId).symbol)),
            title: Text(template.name),
            subtitle: Text(template.fields
                .map((field) =>
                    '${field.label}${field.secret ? ' (скрыто)' : ''}')
                .join(', ')),
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
            iconId: spbIconIdForUi(prepared.iconId, prepared.iconId),
            fields: prepared.fields
                .where((field) => field.id != spbDescriptionFieldId)
                .map((field) => SpbWalletTemplateFieldRecord(
                    id: field.id,
                    name: field.label,
                    templateId: prepared.id,
                    fieldTypeId: spbFieldTypeId(field)))
                .toList(),
          ),
        );
        final snapshot = spbWallet!.loadSnapshot();
        setState(() {
          templates = spbTemplatesToUi(snapshot.templates);
          items = spbCardsToUi(snapshot.cards);
        });
      } catch (error) {
        setState(
            () => message = 'Не удалось скопировать шаблон .swl базы: $error');
      }
      return;
    }
    setState(() =>
        message = 'Откройте или создайте .swl базу перед изменением шаблонов.');
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
            subtitle: Text(spbWalletPath ?? 'локальный .swl файл'),
          ),
        ),
        const SizedBox(height: 24),
        Text('Палитра карточек',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: palette
              .map((color) => Chip(
                    avatar: CircleAvatar(backgroundColor: color.bg),
                    label: Text(color.label),
                  ))
              .toList(),
        ),
        const SizedBox(height: 24),
        Text('Пиктограммы шаблонов',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: templateIcons
              .map((icon) => Chip(label: Text('${icon.symbol} ${icon.label}')))
              .toList(),
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
        categories: existingCategories(),
        initial: item,
        supportsAttachments: spbWallet != null,
        loadAttachmentBytes: spbWallet == null
            ? null
            : (attachmentId) async =>
                spbWallet!.readAttachmentBytes(attachmentId),
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
    setState(() => message =
        'Откройте или создайте .swl базу перед сохранением карточек.');
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
          cardColor: paletteColorToSpb(saved.colorId),
          iconId: spbIconIdForUi(
            itemIconId(saved, templateFor(saved.templateId)),
            templateFor(saved.templateId).iconId,
          ),
          backgroundImageBase64: saved.backgroundImageBase64,
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
      setState(() => message = 'Не удалось сохранить .swl базу: $error');
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
            iconId: spbIconIdForUi(prepared.iconId, prepared.iconId),
            fields: prepared.fields
                .where((field) => field.id != spbDescriptionFieldId)
                .map((field) => SpbWalletTemplateFieldRecord(
                    id: field.id,
                    name: field.label,
                    templateId: prepared.id,
                    fieldTypeId: spbFieldTypeId(field)))
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
        setState(
            () => message = 'Не удалось сохранить шаблон .swl базы: $error');
      }
      return;
    }
    setState(() => message =
        'Откройте или создайте .swl базу перед сохранением шаблонов.');
  }

  CardTemplate prepareSpbTemplate(CardTemplate template, bool isNew) {
    final id = isNew ? SpbWalletDatabase.makeId() : template.id;
    return CardTemplate(
      id: id,
      name: template.name,
      iconId: template.iconId,
      colorId: template.colorId,
      fields: template.fields
          .map((field) => FieldDefinition(
                id: isSpbHexId(field.id)
                    ? field.id
                    : SpbWalletDatabase.makeId(),
                label: field.label,
                type: field.type,
                required: field.required,
                secret: field.secret,
              ))
          .toList(),
    );
  }

  bool isSpbHexId(String value) =>
      RegExp(r'^[0-9A-Fa-f]+$').hasMatch(value) && value.length.isEven;

  Future<void> runSync() async {
    if (spbWallet == null) {
      setState(() => message = 'Запись доступна после открытия .swl базы.');
      return;
    }
    final ok = await writeBackSpbWallet();
    if (!mounted) return;
    setState(() {
      if (ok) {
        lastSyncAt = DateTime.now();
        message = syncSourcePath == null && syncSourceUrl == null
            ? 'База сохранена локально.'
            : 'База записана в исходное хранилище.';
      }
    });
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
          backgroundColor:
              selected ? Theme.of(context).colorScheme.primaryContainer : null,
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

class FieldValueRow extends StatelessWidget {
  const FieldValueRow({
    required this.label,
    required this.value,
    required this.foreground,
    this.secret = false,
    this.revealed = false,
    this.onToggle,
    super.key,
  });

  final String label;
  final String value;
  final Color foreground;
  final bool secret;
  final bool revealed;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.44),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: foreground.withValues(alpha: 0.10)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground.withValues(alpha: 0.62),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style:
                      TextStyle(color: foreground, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          if (secret && onToggle != null)
            IconButton(
              tooltip: revealed ? 'Скрыть' : 'Показать',
              icon: Icon(revealed ? Icons.visibility_off : Icons.visibility),
              onPressed: onToggle,
            ),
        ],
      ),
    );
  }
}

class SpbPanel extends StatelessWidget {
  const SpbPanel({
    required this.title,
    required this.children,
    super.key,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: const Color(0xffb9cee4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(title,
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          ...children,
        ],
      ),
    );
  }
}

class IconPickerField extends StatelessWidget {
  const IconPickerField({
    required this.label,
    required this.iconId,
    required this.onChanged,
    super.key,
  });

  final String label;
  final String iconId;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final icon = iconById(iconId);
    return Row(
      children: [
        CircleAvatar(child: Text(icon.symbol)),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () async {
              final picked = await showIconPickerDialog(context, iconId);
              if (picked != null) onChanged(picked);
            },
            icon: Text(icon.symbol, style: const TextStyle(fontSize: 18)),
            label: Text(label),
          ),
        ),
      ],
    );
  }
}

Future<String?> showIconPickerDialog(
  BuildContext context,
  String selectedIconId,
) {
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Все пиктограммы'),
      content: SizedBox(
        width: min(MediaQuery.of(context).size.width - 48, 560),
        height: min(MediaQuery.of(context).size.height - 180, 420),
        child: GridView.builder(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 52,
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
          ),
          itemCount: templateIcons.length,
          itemBuilder: (context, index) {
            final icon = templateIcons[index];
            final selected = icon.id == selectedIconId;
            return Tooltip(
              message: icon.label,
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => Navigator.pop(context, icon.id),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: selected
                        ? Theme.of(context).colorScheme.primaryContainer
                        : Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: selected
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).dividerColor,
                    ),
                  ),
                  child: Center(
                    child:
                        Text(icon.symbol, style: const TextStyle(fontSize: 24)),
                  ),
                ),
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
      ],
    ),
  );
}

class ItemEditorDialog extends StatefulWidget {
  const ItemEditorDialog({
    required this.templates,
    required this.categories,
    this.initial,
    this.supportsAttachments = false,
    this.loadAttachmentBytes,
    super.key,
  });

  final List<CardTemplate> templates;
  final List<String> categories;
  final SecretItem? initial;
  final bool supportsAttachments;
  final Future<List<int>> Function(String attachmentId)? loadAttachmentBytes;

  @override
  State<ItemEditorDialog> createState() => _ItemEditorDialogState();
}

class _ItemEditorDialogState extends State<ItemEditorDialog> {
  static const emptyCategoryValue = '__empty_category__';
  static const newCategoryValue = '__new_category__';

  late String templateId;
  late String colorId;
  late String categorySelection;
  late String iconId;
  late final TextEditingController title;
  late final TextEditingController category;
  late final Map<String, TextEditingController> values;
  late List<SecretAttachment> attachments;
  String? backgroundImageBase64;
  final Set<String> visibleSecrets = {};

  CardTemplate get template =>
      widget.templates.firstWhere((entry) => entry.id == templateId);

  @override
  void initState() {
    super.initState();
    templateId = widget.initial?.templateId ?? widget.templates.first.id;
    colorId = widget.initial?.colorId ?? template.colorId;
    iconId = widget.initial?.iconId ?? template.iconId;
    title = TextEditingController(text: widget.initial?.title ?? '');
    final initialCategory = widget.initial?.category.trim() ?? '';
    category = TextEditingController(text: initialCategory);
    categorySelection = initialCategory.isEmpty
        ? emptyCategoryValue
        : widget.categories.contains(initialCategory)
            ? initialCategory
            : newCategoryValue;
    values = {
      for (final field in template.fields)
        field.id:
            TextEditingController(text: widget.initial?.values[field.id] ?? ''),
    };
    attachments = [...?widget.initial?.attachments];
    backgroundImageBase64 = widget.initial?.backgroundImageBase64;
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
      title: Text(
          widget.initial == null ? 'Новая карточка' : 'Редактировать карточку'),
      content: SizedBox(
        width: min(MediaQuery.of(context).size.width - 48, 680),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: templateId,
                decoration: const InputDecoration(
                    labelText: 'Шаблон', border: OutlineInputBorder()),
                items: widget.templates
                    .map((template) => DropdownMenuItem(
                        value: template.id,
                        child: Text(
                            '${iconById(template.iconId).symbol} ${template.name}')))
                    .toList(),
                onChanged: (value) => setState(() {
                  templateId = value ?? templateId;
                  if (widget.initial == null ||
                      widget.initial?.iconId == null) {
                    iconId = template.iconId;
                  }
                  for (final field in template.fields) {
                    values.putIfAbsent(field.id, () => TextEditingController());
                  }
                }),
              ),
              const SizedBox(height: 10),
              TextField(
                  controller: title,
                  decoration: const InputDecoration(
                      labelText: 'Название', border: OutlineInputBorder())),
              const SizedBox(height: 10),
              categoryEditor(),
              const SizedBox(height: 10),
              IconPickerField(
                label: 'Пиктограмма карточки',
                iconId: iconId,
                onChanged: (value) => setState(() => iconId = value),
              ),
              const SizedBox(height: 10),
              ColorPicker(
                  value: colorId,
                  onChanged: (value) => setState(() => colorId = value)),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: pickBackgroundImage,
                      icon: const Icon(Icons.image_outlined),
                      label: Text(backgroundImageBase64 == null
                          ? 'Добавить фон'
                          : 'Заменить фон'),
                    ),
                  ),
                  if (backgroundImageBase64 != null) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Убрать фон',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () =>
                          setState(() => backgroundImageBase64 = null),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              ...template.fields.map((field) {
                final controller =
                    values.putIfAbsent(field.id, () => TextEditingController());
                final visible = visibleSecrets.contains(field.id);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TextField(
                    controller: controller,
                    obscureText: field.secret && !visible,
                    keyboardType: keyboardTypeForField(field),
                    inputFormatters: inputFormattersForField(field),
                    onEditingComplete: () {
                      if (field.type == 'url') {
                        controller.text = normalizeUrlInput(controller.text);
                        controller.selection = TextSelection.collapsed(
                            offset: controller.text.length);
                      }
                    },
                    minLines: field.type == 'multiline_note' ? 3 : 1,
                    maxLines: field.type == 'multiline_note' ? 5 : 1,
                    decoration: InputDecoration(
                      labelText: '${field.label}${field.required ? ' *' : ''}',
                      hintText: hintTextForField(field),
                      border: const OutlineInputBorder(),
                      suffixIcon: fieldSuffixIcon(field, controller, visible),
                    ),
                  ),
                );
              }),
              if (widget.supportsAttachments) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Вложения .swl',
                      style: Theme.of(context).textTheme.titleSmall),
                ),
                const SizedBox(height: 8),
                ...attachments
                    .where((attachment) => !attachment.deleted)
                    .map((attachment) {
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
                      subtitle: Text(subtitle,
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                      trailing: Wrap(
                        spacing: 4,
                        children: [
                          if (attachment.id.isNotEmpty &&
                              attachment.decodeError == null)
                            IconButton(
                              tooltip: 'Сохранить вложение',
                              icon: const Icon(Icons.download_outlined),
                              onPressed: () => exportAttachment(attachment),
                            ),
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
                                  .map((entry) => entry.id == attachment.id
                                      ? entry.copyWith(deleted: true)
                                      : entry)
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
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена')),
        FilledButton(
          onPressed: () {
            Navigator.pop(
              context,
              SecretItem(
                id: widget.initial?.id ?? makeId('item'),
                templateId: templateId,
                title: title.text.trim().isEmpty
                    ? template.name
                    : title.text.trim(),
                category: category.text.trim(),
                colorId: colorId,
                values: {
                  for (final field in widget.templates
                      .firstWhere((entry) => entry.id == templateId)
                      .fields)
                    field.id: field.type == 'url'
                        ? normalizeUrlInput((values[field.id]?.text ?? ''))
                        : (values[field.id]?.text.trim() ?? ''),
                },
                attachments: attachments,
                modifiedAt: DateTime.now(),
                hitCount: widget.initial?.hitCount ?? 0,
                iconId: iconId,
                backgroundImageBase64: backgroundImageBase64,
              ),
            );
          },
          child: const Text('Сохранить'),
        ),
      ],
    );
  }

  Widget categoryEditor() {
    final dropdownValues = <String>{
      emptyCategoryValue,
      ...widget.categories,
      newCategoryValue,
    }.toList();
    final selectedValue = dropdownValues.contains(categorySelection)
        ? categorySelection
        : newCategoryValue;
    return Column(
      children: [
        DropdownButtonFormField<String>(
          initialValue: selectedValue,
          decoration: const InputDecoration(
            labelText: 'Категория',
            border: OutlineInputBorder(),
          ),
          items: [
            const DropdownMenuItem(
              value: emptyCategoryValue,
              child: Text('Без категории'),
            ),
            ...widget.categories.map(
              (entry) => DropdownMenuItem(value: entry, child: Text(entry)),
            ),
            const DropdownMenuItem(
              value: newCategoryValue,
              child: Text('Создать новую категорию'),
            ),
          ],
          onChanged: (value) => setState(() {
            categorySelection = value ?? emptyCategoryValue;
            if (categorySelection == emptyCategoryValue) {
              category.clear();
            } else if (categorySelection != newCategoryValue) {
              category.text = categorySelection;
            }
          }),
        ),
        if (selectedValue == newCategoryValue) ...[
          const SizedBox(height: 10),
          TextField(
            controller: category,
            decoration: const InputDecoration(
              labelText: 'Новая категория',
              hintText: 'Например: Финансы / Банк',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ],
    );
  }

  TextInputType keyboardTypeForField(FieldDefinition field) {
    if (field.type == 'url') return TextInputType.url;
    if (field.type == 'date') return TextInputType.datetime;
    return TextInputType.text;
  }

  List<TextInputFormatter>? inputFormattersForField(FieldDefinition field) {
    if (field.type == 'date') return [DateTextInputFormatter()];
    return null;
  }

  String? hintTextForField(FieldDefinition field) {
    if (field.type == 'url') return 'https://example.com';
    if (field.type == 'date') return 'дд.мм.гггг';
    return null;
  }

  Widget? fieldSuffixIcon(
    FieldDefinition field,
    TextEditingController controller,
    bool visible,
  ) {
    final buttons = <Widget>[];
    if (field.type == 'date') {
      buttons.add(
        IconButton(
          tooltip: 'Выбрать дату',
          icon: const Icon(Icons.calendar_month_outlined),
          onPressed: () => pickDateForField(controller),
        ),
      );
    }
    if (field.secret) {
      buttons.add(
        IconButton(
          tooltip: visible ? 'Скрыть' : 'Показать',
          icon: Icon(visible ? Icons.visibility_off : Icons.visibility),
          onPressed: () => setState(() {
            visible
                ? visibleSecrets.remove(field.id)
                : visibleSecrets.add(field.id);
          }),
        ),
      );
    }
    if (buttons.isEmpty) return null;
    if (buttons.length == 1) return buttons.single;
    return SizedBox(
      width: 96,
      child: Row(mainAxisSize: MainAxisSize.min, children: buttons),
    );
  }

  Future<void> pickDateForField(TextEditingController controller) async {
    final initialDate = parseDateInput(controller.text) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate.year < 1900 || initialDate.year > 2200
          ? DateTime.now()
          : initialDate,
      firstDate: DateTime(1900),
      lastDate: DateTime(2200),
    );
    if (picked == null) return;
    setState(() => controller.text = formatDateInput(picked));
  }

  Future<void> addAttachment() async {
    final picked = await FilePicker.platform.pickFiles(withData: true);
    final file = picked?.files.single;
    if (file == null) return;
    final bytes = file.bytes ??
        (file.path == null ? null : await File(file.path!).readAsBytes());
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

  Future<void> pickBackgroundImage() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final file = picked?.files.single;
    if (file == null) return;
    final bytes = file.bytes ??
        (file.path == null ? null : await File(file.path!).readAsBytes());
    if (bytes == null) return;
    setState(() => backgroundImageBase64 = base64Encode(bytes));
  }

  Future<void> replaceAttachment(SecretAttachment attachment) async {
    final picked = await FilePicker.platform.pickFiles(withData: true);
    final file = picked?.files.single;
    if (file == null) return;
    final bytes = file.bytes ??
        (file.path == null ? null : await File(file.path!).readAsBytes());
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

  Future<void> exportAttachment(SecretAttachment attachment) async {
    final loader = widget.loadAttachmentBytes;
    if (loader == null || attachment.id.isEmpty) return;
    try {
      final bytes = await loader(attachment.id);
      final data = Uint8List.fromList(bytes);
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Сохранить вложение',
        fileName: attachment.fileName,
        bytes: data,
      );
      if (path != null && !Platform.isAndroid && !Platform.isIOS) {
        final file = File(path);
        if (!file.existsSync() || file.lengthSync() != data.length) {
          await file.writeAsBytes(data, flush: true);
        }
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось сохранить вложение: $error')),
      );
    }
  }
}

class TemplateEditorDialog extends StatefulWidget {
  const TemplateEditorDialog({this.initial, super.key});

  final CardTemplate? initial;

  @override
  State<TemplateEditorDialog> createState() => _TemplateEditorDialogState();
}

class TemplateFieldDraft {
  TemplateFieldDraft(FieldDefinition field)
      : id = field.id,
        type = field.type,
        required = field.required,
        secret = field.secret,
        label = TextEditingController(text: field.label);

  final String id;
  final TextEditingController label;
  String type;
  bool required;
  bool secret;

  void dispose() => label.dispose();

  FieldDefinition toField() => FieldDefinition(
        id: id,
        label: label.text.trim().isEmpty ? 'Поле' : label.text.trim(),
        type: type,
        required: required,
        secret: secret || type == 'password' || type == 'custom_secret',
      );
}

class _TemplateEditorDialogState extends State<TemplateEditorDialog> {
  late final TextEditingController name;
  late String iconId;
  late String colorId;
  late final List<TemplateFieldDraft> fields;

  @override
  void initState() {
    super.initState();
    name = TextEditingController(text: widget.initial?.name ?? '');
    iconId = widget.initial?.iconId ?? 'key';
    colorId = widget.initial?.colorId ?? 'neutral';
    fields = [
      for (final field in widget.initial?.fields ??
          const [
            FieldDefinition(id: 'username', label: 'Логин', type: 'username'),
            FieldDefinition(
                id: 'password',
                label: 'Пароль',
                type: 'password',
                secret: true),
            FieldDefinition(
                id: 'notes', label: 'Заметки', type: 'multiline_note'),
          ])
        TemplateFieldDraft(field),
    ];
  }

  @override
  void dispose() {
    name.dispose();
    for (final field in fields) {
      field.dispose();
    }
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
              TextField(
                  controller: name,
                  decoration: const InputDecoration(
                      labelText: 'Название шаблона',
                      border: OutlineInputBorder())),
              const SizedBox(height: 14),
              const Text('Пиктограмма'),
              const SizedBox(height: 8),
              templateIconPicker(),
              const SizedBox(height: 14),
              Row(
                children: [
                  Text('Поля', style: Theme.of(context).textTheme.titleSmall),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: addField,
                    icon: const Icon(Icons.add),
                    label: const Text('Добавить поле'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ...fields.map(fieldEditor),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена')),
        FilledButton(
          onPressed: () {
            Navigator.pop(
              context,
              CardTemplate(
                id: widget.initial?.id ?? makeId('tpl'),
                name: name.text.trim().isEmpty
                    ? 'Новый шаблон'
                    : name.text.trim(),
                iconId: iconId,
                colorId: colorId,
                builtIn: widget.initial?.builtIn ?? false,
                fields: fields.map((field) => field.toField()).toList(),
              ),
            );
          },
          child: const Text('Сохранить'),
        ),
      ],
    );
  }

  Widget templateIconPicker() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ...quickTemplateIcons(iconId).map((icon) => ChoiceChip(
              selected: icon.id == iconId,
              label: Text(icon.symbol, style: const TextStyle(fontSize: 18)),
              tooltip: icon.label,
              onSelected: (_) => setState(() => iconId = icon.id),
            )),
        OutlinedButton.icon(
          onPressed: () async {
            final picked = await showIconPickerDialog(context, iconId);
            if (picked != null) setState(() => iconId = picked);
          },
          icon: const Icon(Icons.apps_outlined),
          label: const Text('Все пиктограммы'),
        ),
      ],
    );
  }

  Widget fieldEditor(TemplateFieldDraft field) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            TextField(
              controller: field.label,
              decoration: const InputDecoration(
                  labelText: 'Название поля', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: field.type,
                    decoration: const InputDecoration(
                        labelText: 'Тип', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(
                          value: 'text', child: Text('Маленькая строка')),
                      DropdownMenuItem(value: 'username', child: Text('Логин')),
                      DropdownMenuItem(
                          value: 'multiline_note',
                          child: Text('Большая строка')),
                      DropdownMenuItem(
                          value: 'password', child: Text('Пароль')),
                      DropdownMenuItem(
                          value: 'custom_secret', child: Text('Секрет')),
                      DropdownMenuItem(value: 'number', child: Text('Число')),
                      DropdownMenuItem(value: 'url', child: Text('Сайт')),
                      DropdownMenuItem(value: 'email', child: Text('Email')),
                      DropdownMenuItem(value: 'phone', child: Text('Телефон')),
                      DropdownMenuItem(value: 'date', child: Text('Дата')),
                      DropdownMenuItem(value: 'totp', child: Text('TOTP')),
                    ],
                    onChanged: (value) => setState(() {
                      field.type = value ?? 'text';
                      if (field.type == 'password' ||
                          field.type == 'custom_secret') {
                        field.secret = true;
                      }
                    }),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Удалить поле',
                  icon: const Icon(Icons.delete_outline),
                  onPressed:
                      fields.length <= 1 ? null : () => removeField(field),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 10,
              children: [
                FilterChip(
                  selected: field.required,
                  label: const Text('Обязательное'),
                  onSelected: (value) => setState(() => field.required = value),
                ),
                FilterChip(
                  selected: field.secret,
                  label: const Text('Скрывать'),
                  onSelected: (value) => setState(() => field.secret = value),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void addField() {
    setState(() {
      fields.add(
        TemplateFieldDraft(
          FieldDefinition(
              id: makeId('field'), label: 'Новое поле', type: 'text'),
        ),
      );
    });
  }

  void removeField(TemplateFieldDraft field) {
    setState(() {
      fields.remove(field);
      field.dispose();
    });
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
                      color: selected
                          ? Theme.of(context).colorScheme.primary
                          : Colors.transparent,
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
