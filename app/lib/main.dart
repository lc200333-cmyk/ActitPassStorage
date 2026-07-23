import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'spb_wallet/spb_wallet_database.dart';

void main() {
  runApp(const ActitPassApp());
}

final rootScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

Future<void> copyCardFieldValue(String value) async {
  await Clipboard.setData(ClipboardData(text: value));
  rootScaffoldMessengerKey.currentState
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      const SnackBar(
        content: Text('Скопировано'),
        duration: Duration(milliseconds: 900),
        behavior: SnackBarBehavior.floating,
      ),
    );
}

class ActitPassApp extends StatelessWidget {
  const ActitPassApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scaffoldMessengerKey: rootScaffoldMessengerKey,
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
    this.spbColor,
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
  // Точный RGB-цвет карточки, как он хранится в .swl (spbwlt_CardView.CardColor).
  // Если задан, имеет приоритет над colorId при отрисовке и сохранении, чтобы
  // не "квантовать" оригинальный цвет SPB Wallet до одного из 7 пресетов палитры.
  final int? spbColor;

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
        'spbColor': spbColor,
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
        spbColor: json['spbColor'] as int?,
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
  CategoryTreeNode(this.name, {this.path = '', this.iconId});

  final String name;
  final String path;
  final String? iconId;
  final Map<String, CategoryTreeNode> children = {};
  final List<SecretItem> cards = [];

  bool get isEmpty => children.isEmpty && cards.isEmpty;
}

class ExistingVault {
  const ExistingVault({
    required this.title,
    this.path,
    this.uri,
    this.displayPath,
  });

  final String title;
  final String? path;
  final String? uri;
  final String? displayPath;

  String get key => uri ?? path ?? title;

  Map<String, dynamic> toJson() => {
        'title': title,
        if (path != null) 'path': path,
        if (uri != null) 'uri': uri,
        if (displayPath != null) 'displayPath': displayPath,
      };

  factory ExistingVault.fromJson(Map<String, dynamic> json) {
    final title = json['title']?.toString();
    final path = json['path']?.toString();
    final uri = json['uri']?.toString();
    final displayPath = json['displayPath']?.toString();
    return ExistingVault(
      title: title == null || title.isEmpty
          ? _vaultTitleFromPath(displayPath ?? path ?? uri ?? '.swl база')
          : title,
      path: path,
      uri: uri,
      displayPath: displayPath,
    );
  }
}

String _vaultTitleFromPath(String path) {
  if (path.startsWith('content://')) return '.swl база';
  final normalized = path.replaceAll('\\', '/');
  final slash = normalized.lastIndexOf('/');
  return slash < 0 ? path : normalized.substring(slash + 1);
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
        cardColor: item.spbColor ?? paletteColorToSpb(item.colorId),
        iconId:
            item.iconId == null ? null : syntheticSpbIconIdForUi(item.iconId!),
        backgroundImageBase64: item.backgroundImageBase64,
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

const templateIconGlyphs = {
  'key': Icons.vpn_key_outlined,
  'note': Icons.notes_outlined,
  'card': Icons.credit_card,
  'id': Icons.badge_outlined,
  'server': Icons.dns_outlined,
  'license': Icons.sell_outlined,
  'wifi': Icons.wifi,
  'bank': Icons.account_balance,
  'mail': Icons.mail_outline,
  'shield': Icons.security,
  'lock': Icons.lock_outline,
  'unlock': Icons.lock_open,
  'safe': Icons.inventory_2_outlined,
  'briefcase': Icons.business_center_outlined,
  'folder': Icons.folder_outlined,
  'file': Icons.insert_drive_file_outlined,
  'bookmark': Icons.bookmark_border,
  'tag': Icons.label_outline,
  'receipt': Icons.receipt_long,
  'money': Icons.attach_money,
  'coin': Icons.monetization_on_outlined,
  'wallet': Icons.account_balance_wallet_outlined,
  'chart': Icons.trending_up,
  'calculator': Icons.calculate_outlined,
  'home': Icons.home_outlined,
  'car': Icons.directions_car,
  'plane': Icons.flight_takeoff,
  'train': Icons.train,
  'passport': Icons.assignment_ind_outlined,
  'ticket': Icons.confirmation_number_outlined,
  'phone': Icons.phone_iphone,
  'desktop': Icons.desktop_windows,
  'laptop': Icons.laptop_mac,
  'printer': Icons.print,
  'keyboard': Icons.keyboard,
  'mouse': Icons.mouse,
  'disk': Icons.save,
  'cd': Icons.album,
  'camera': Icons.photo_camera,
  'video': Icons.videocam,
  'tv': Icons.tv,
  'game': Icons.sports_esports,
  'headphones': Icons.headphones,
  'watch': Icons.watch,
  'satellite': Icons.settings_input_antenna,
  'globe': Icons.public,
  'link': Icons.link,
  'cloud': Icons.cloud_outlined,
  'database': Icons.storage,
  'gear': Icons.settings,
  'tool': Icons.construction,
  'wrench': Icons.build,
  'bug': Icons.bug_report_outlined,
  'code': Icons.code,
  'package': Icons.inventory_2,
  'rocket': Icons.rocket_launch,
  'lab': Icons.science,
  'medical': Icons.medical_services,
  'heart': Icons.favorite_border,
  'pill': Icons.medication,
  'school': Icons.school,
  'book': Icons.menu_book,
  'pen': Icons.edit,
  'clipboard': Icons.assignment,
  'calendar': Icons.calendar_month,
  'clock': Icons.schedule,
  'pin': Icons.push_pin,
  'location': Icons.place,
  'map': Icons.map_outlined,
  'house_key': Icons.key,
  'building': Icons.business,
  'shop': Icons.local_mall,
  'factory': Icons.factory,
  'hammer': Icons.hardware,
  'scales': Icons.balance,
  'certificate': Icons.workspace_premium,
  'medal': Icons.emoji_events,
  'star': Icons.star_border,
  'warning': Icons.warning_amber,
  'bell': Icons.notifications_none,
  'gift': Icons.card_giftcard,
  'cart': Icons.shopping_cart,
  'food': Icons.restaurant,
  'coffee': Icons.local_cafe,
  'hotel': Icons.hotel,
  'taxi': Icons.local_taxi,
  'fuel': Icons.local_gas_station,
  'bicycle': Icons.directions_bike,
  'ship': Icons.directions_boat,
  'anchor': Icons.anchor,
  'crypto': Icons.currency_bitcoin,
  'diamond': Icons.diamond_outlined,
  'gem': Icons.diamond,
  'mailbox': Icons.markunread_mailbox_outlined,
  'inbox': Icons.move_to_inbox,
  'outbox': Icons.outbox,
  'chat': Icons.chat_bubble_outline,
  'contact': Icons.person_outline,
  'group': Icons.group_outlined,
  'family': Icons.family_restroom,
  'fingerprint': Icons.fingerprint,
  'magnifier': Icons.search,
  'battery': Icons.battery_full,
  'plug': Icons.power,
  'fire': Icons.local_fire_department,
  'snowflake': Icons.ac_unit,
  'plant': Icons.grass,
  'tree': Icons.park,
  'sun': Icons.wb_sunny,
  'moon': Icons.dark_mode,
  'umbrella': Icons.beach_access,
  'magnet': Icons.tungsten,
  'dna': Icons.biotech,
  'microchip': Icons.memory,
  'qr': Icons.qr_code,
  'check': Icons.check_circle_outline,
  'cross': Icons.cancel_outlined,
  'plus': Icons.add_circle_outline,
  'minus': Icons.remove_circle_outline,
  'question': Icons.help_outline,
  'info': Icons.info_outline,
};

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

const navEntries = [
  NavEntry('cards', Icons.credit_card, 'Карточки'),
  NavEntry('frequent', Icons.star_outline, 'Частые'),
  NavEntry('templates', Icons.dashboard_customize_outlined, 'Шаблоны'),
  NavEntry('settings', Icons.settings_outlined, 'Настройки'),
];

class NavEntry {
  const NavEntry(this.id, this.icon, this.label);

  final String id;
  final IconData icon;
  final String label;
}

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
      CardTemplate(
        id: 'tpl_email_account',
        name: 'Email аккаунт',
        iconId: 'mail',
        colorId: 'green',
        builtIn: true,
        fields: [
          FieldDefinition(
              id: 'email', label: 'Email', type: 'email', required: true),
          FieldDefinition(
              id: 'password',
              label: 'Пароль',
              type: 'password',
              required: true,
              secret: true),
          FieldDefinition(
              id: 'recovery', label: 'Резервная почта', type: 'email'),
          FieldDefinition(
              id: 'notes', label: 'Заметки', type: 'multiline_note'),
        ],
      ),
      CardTemplate(
        id: 'tpl_api_key',
        name: 'API ключ',
        iconId: 'code',
        colorId: 'violet',
        builtIn: true,
        fields: [
          FieldDefinition(
              id: 'service', label: 'Сервис', type: 'text', required: true),
          FieldDefinition(id: 'url', label: 'Панель', type: 'url'),
          FieldDefinition(
              id: 'token',
              label: 'Токен',
              type: 'custom_secret',
              required: true),
          FieldDefinition(
              id: 'notes',
              label: 'Права и ограничения',
              type: 'multiline_note'),
        ],
      ),
      CardTemplate(
        id: 'tpl_crypto_wallet',
        name: 'Криптокошелек',
        iconId: 'crypto',
        colorId: 'amber',
        builtIn: true,
        fields: [
          FieldDefinition(
              id: 'wallet', label: 'Название кошелька', type: 'text'),
          FieldDefinition(id: 'address', label: 'Адрес', type: 'text'),
          FieldDefinition(
              id: 'seed',
              label: 'Seed-фраза',
              type: 'custom_secret',
              required: true),
          FieldDefinition(id: 'pin', label: 'PIN', type: 'password'),
          FieldDefinition(
              id: 'notes', label: 'Заметки', type: 'multiline_note'),
        ],
      ),
      CardTemplate(
        id: 'tpl_contact',
        name: 'Контакт',
        iconId: 'contact',
        colorId: 'neutral',
        builtIn: true,
        fields: [
          FieldDefinition(id: 'name', label: 'Имя', type: 'text'),
          FieldDefinition(id: 'phone', label: 'Телефон', type: 'phone'),
          FieldDefinition(id: 'email', label: 'Email', type: 'email'),
          FieldDefinition(
              id: 'address', label: 'Адрес', type: 'multiline_note'),
        ],
      ),
      CardTemplate(
        id: 'tpl_subscription',
        name: 'Подписка',
        iconId: 'ticket',
        colorId: 'blue',
        builtIn: true,
        fields: [
          FieldDefinition(
              id: 'service', label: 'Сервис', type: 'text', required: true),
          FieldDefinition(id: 'login', label: 'Логин', type: 'username'),
          FieldDefinition(id: 'renewal', label: 'Дата продления', type: 'date'),
          FieldDefinition(id: 'price', label: 'Стоимость', type: 'number'),
          FieldDefinition(
              id: 'notes', label: 'Условия', type: 'multiline_note'),
        ],
      ),
      CardTemplate(
        id: 'tpl_insurance',
        name: 'Страховка',
        iconId: 'umbrella',
        colorId: 'teal',
        builtIn: true,
        fields: [
          FieldDefinition(
              id: 'company', label: 'Компания', type: 'text', required: true),
          FieldDefinition(
              id: 'policy',
              label: 'Номер полиса',
              type: 'custom_secret',
              required: true),
          FieldDefinition(id: 'valid_to', label: 'Действует до', type: 'date'),
          FieldDefinition(
              id: 'phone', label: 'Телефон поддержки', type: 'phone'),
          FieldDefinition(
              id: 'notes', label: 'Условия', type: 'multiline_note'),
        ],
      ),
      CardTemplate(
        id: 'tpl_travel',
        name: 'Поездка',
        iconId: 'plane',
        colorId: 'violet',
        builtIn: true,
        fields: [
          FieldDefinition(id: 'carrier', label: 'Перевозчик', type: 'text'),
          FieldDefinition(id: 'booking', label: 'Бронь/PNR', type: 'text'),
          FieldDefinition(id: 'date', label: 'Дата', type: 'date'),
          FieldDefinition(
              id: 'document', label: 'Документ', type: 'custom_secret'),
          FieldDefinition(
              id: 'notes', label: 'Заметки', type: 'multiline_note'),
        ],
      ),
      CardTemplate(
        id: 'tpl_home_access',
        name: 'Домашний доступ',
        iconId: 'house_key',
        colorId: 'green',
        builtIn: true,
        fields: [
          FieldDefinition(id: 'object', label: 'Объект', type: 'text'),
          FieldDefinition(id: 'code', label: 'Код доступа', type: 'password'),
          FieldDefinition(id: 'contact', label: 'Контакт', type: 'phone'),
          FieldDefinition(
              id: 'notes', label: 'Инструкции', type: 'multiline_note'),
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

/// Цвет для отрисовки карточки: если известен точный RGB из SPB Wallet
/// (`item.spbColor`), используется он напрямую, без округления до одного из
/// 7 пресетов палитры. Иначе — прежнее поведение через colorId/пресет.
PaletteColor itemDisplayColor(SecretItem item, CardTemplate template) {
  final rawColor = item.spbColor;
  if (rawColor == null) {
    return colorById(item.colorId.isEmpty ? template.colorId : item.colorId);
  }
  final bg = Color(0xff000000 | (rawColor & 0x00ffffff));
  final fg =
      bg.computeLuminance() > 0.55 ? const Color(0xff222831) : Colors.white;
  return PaletteColor('custom', 'Свой цвет', bg, fg);
}

TemplateIcon iconById(String id) => templateIcons.firstWhere(
      (icon) => icon.id == id,
      orElse: () => templateIcons.first,
    );

IconData templateIconGlyph(String id) =>
    templateIconGlyphs[id] ?? Icons.vpn_key_outlined;

Widget templateIconWidget(String id, {double size = 20, Color? color}) {
  final originalAsset = spbOriginalIconAsset(id);
  if (originalAsset != null) {
    // Original SPB Wallet icons are 64x64. Do not scale them down to the
    // Material icon size requested by compact callers.
    return SizedBox(
      width: 64,
      height: 64,
      child: Image.asset(
        originalAsset,
        width: 64,
        height: 64,
        fit: BoxFit.none,
        filterQuality: FilterQuality.none,
        errorBuilder: (_, __, ___) =>
            Icon(Icons.vpn_key_outlined, size: size, color: color),
      ),
    );
  }
  return Icon(templateIconGlyph(id), size: size, color: color);
}

Widget templateMenuIconLabel(String iconId, String text) {
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      templateIconWidget(iconId, size: 18),
      const SizedBox(width: 8),
      Flexible(child: Text(text, overflow: TextOverflow.ellipsis)),
    ],
  );
}

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
  // A legacy icon selected from an existing .swl must retain its real ID.
  // Hashing it would make the old database point at a different icon.
  if (RegExp(r'^[0-9A-Fa-f]{16}$').hasMatch(uiIconId)) {
    return uiIconId.toUpperCase();
  }
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

// IDs are in the original resource order from SpbWallet_RU_templates.swl.
// The corresponding files remain named icons_001.png ... icons_065.png.
const spbOriginalIconIds = [
  'A74FE6691728757D',
  'E4186A7B247E2B1D',
  '4428DBE8E0FDBEF5',
  'BD097D2EE2FA614A',
  '6FCAF114B73422CF',
  '490FA51A66910C69',
  '556D5E8F02589023',
  '7291F51A432B6530',
  '40F61F0CE55A0757',
  'D3AB05E94F9E4C18',
  '52AB4DC040DF39EA',
  'AD817751F169F5F9',
  '289B3CF7980A951E',
  '20678C366BED420F',
  'E8950204C5B13337',
  '9DEB9BC675EC569A',
  'AC2FDDB9D988A96E',
  'F7F133A9EDA8AD3E',
  '364C9DE41B5927E4',
  'C0F3D5137928104F',
  'D8466DC42C598628',
  'F1DF61C4072919F4',
  '55B25AA977BBABA0',
  '5DB82F9F9859FF2C',
  '7650B2DDF2971084',
  'D0A03FA49259E894',
  '6ACC0F32AAB28ED8',
  'CAACFBE92AAC7C7D',
  'AB540457E8E62887',
  'E610927897C0F039',
  'EDE2A1A2E3B172D5',
  '38A06822A088D80F',
  'BC8395AF3885E099',
  '28A67DABE33DA42B',
  '14BD44DE9F2F4F99',
  'B8058FF4BA946340',
  'E5442EED85AD0572',
  '62767D3E1BC8E2C8',
  '867CA874B9508C95',
  'A6E0F0CFDFAF6928',
  '087CF65FC366A122',
  'B7D8EDDF4E4F493E',
  '27445EACFC5DD8D9',
  '31785C316B046C3F',
  '24760DEDF9C71546',
  '508A24D5C6B90C54',
  'BC51FC021F344286',
  '243B78A1D8C7E32C',
  '97973FA7389FFE1C',
  '68E51FEE9B8D4E7C',
  '06D4F7F69F1E42E5',
  'DAECE1D88696E125',
  '5DEF85654F9DC2CD',
  'A06AD15403B46BAB',
  '30E614ECB34BA668',
  'CEBAB052995FF2BA',
  '71076D75AD9AD080',
  '26DAEC5D7E4E6715',
  '54320B4412A08007',
  'E864A803F91DA5C4',
  '4863F2D4E9D399F6',
  '96DAFC9A4C1F55F6',
  '5D595FE47887E6C9',
  '6E4AAD6B4F39E378',
  '0C1E037B56E9E59B',
];

String? spbOriginalIconAsset(String iconId) {
  final index = spbOriginalIconIds.indexOf(iconId.toUpperCase());
  if (index < 0) return null;
  final fileNumber = (index + 1).toString().padLeft(3, '0');
  return 'assets/spb_wallet_libraries/icons/apk_icons/res/'
      'drawable-hdpi/icons_$fileNumber.png';
}

String makeId(String prefix) {
  final random = Random.secure();
  final suffix =
      List.generate(12, (_) => random.nextInt(16).toRadixString(16)).join();
  return '${prefix}_$suffix';
}

enum EntryMode { openSwl, createSwl }

enum VirtualKeyboardMode { numeric, uppercase, lowercase, symbols }

const spbDescriptionFieldId = '__spb_description';
const spbWalletChannel = MethodChannel('actit_pass_storage/spb_wallet');
const windowChannel = MethodChannel('actit_pass_storage/window');

bool isNotesLabel(String label) {
  final normalized = label.trim().toLowerCase();
  return normalized == 'note' ||
      normalized == 'notes' ||
      normalized == 'заметка' ||
      normalized == 'заметки' ||
      normalized.contains('замет');
}

bool isRealNotesField(FieldDefinition field) {
  if (field.id == spbDescriptionFieldId) return false;
  final normalizedId = field.id.trim().toLowerCase();
  return normalizedId == 'note' ||
      normalizedId == 'notes' ||
      isNotesLabel(field.label);
}

bool fieldTypeIsSecret(String type) =>
    type == 'password' || type == 'custom_secret';

bool fieldDefinitionIsSecret(FieldDefinition field) =>
    field.secret || fieldTypeIsSecret(field.type);

String noteFieldIdForTemplate(CardTemplate template) {
  for (final field in template.fields) {
    if (isRealNotesField(field)) return field.id;
  }
  for (final field in template.fields) {
    if (field.id == spbDescriptionFieldId) return spbDescriptionFieldId;
  }
  return spbDescriptionFieldId;
}

int spbFieldTypeId(FieldDefinition field) {
  if (fieldTypeIsSecret(field.type)) {
    return 2;
  }
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
      return 1;
    default:
      return 1;
  }
}

bool createInitialSwlVaultFile(Map<String, dynamic> payload) {
  final path = payload['path'] as String;
  final password = payload['password'] as String;
  final templates = (payload['templates'] as List<dynamic>)
      .map((entry) =>
          CardTemplate.fromJson(Map<String, dynamic>.from(entry as Map)))
      .toList();
  final itemEntries = (payload['items'] as List<dynamic>)
      .map((entry) => Map<String, dynamic>.from(entry as Map))
      .toList();
  final items = itemEntries.map((entry) => SecretItem.fromJson(entry)).toList();
  final categoryIcons = Map<String, String>.from(
      payload['categoryIcons'] as Map<dynamic, dynamic>);
  SpbWalletDatabase? wallet;
  try {
    wallet = SpbWalletDatabase.create(path, password);
    for (final template in templates) {
      wallet.saveTemplate(
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
    }
    final templateMap = {
      for (final template in templates) template.id: template
    };
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final template = templateMap[item.templateId];
      if (template == null) continue;
      wallet.saveCard(
        SpbWalletCardDraft(
          id: item.id,
          title: item.title,
          description: '',
          categoryPath: item.category,
          templateId: template.id,
          iconId: syntheticSpbIconIdForUi(item.iconId ?? template.iconId),
          fieldValues: item.values,
          cardColor: itemEntries[i]['cardColor'] as int,
          backgroundImageBase64: item.backgroundImageBase64,
        ),
      );
    }
    for (final entry in categoryIcons.entries) {
      wallet.saveCategoryIcon(entry.key, syntheticSpbIconIdForUi(entry.value));
    }
    wallet.close();
    return true;
  } catch (_) {
    try {
      wallet?.close();
    } catch (_) {}
    try {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    } catch (_) {}
    rethrow;
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
  final passwordFocusNode = FocusNode(debugLabel: 'vaultPassword');

  EntryMode entryMode = EntryMode.openSwl;
  bool showPassword = false;
  bool showConfirm = false;
  bool unlocked = false;
  bool? menuOpenOverride;
  bool creatingVault = false;
  String? configuredWindowMode;
  VirtualKeyboardMode virtualKeyboardMode = VirtualKeyboardMode.numeric;
  String activeView = 'cards';
  String? message;
  String? spbWalletPath;
  String? spbWalletUri;
  String? spbWalletDisplayPath;
  String? syncSourcePath;
  String? syncSourceUrl;
  String? syncOriginProvider;
  SpbWalletDatabase? spbWallet;
  String syncProvider = 'mounted_folder';
  String templateFilter = '';
  String templateSearchQuery = '';
  String sortMode = 'modified_desc';
  String? selectedItemId;
  DateTime? lastSyncAt;

  List<CardTemplate> templates = builtInTemplates();
  List<SecretItem> items = [];
  List<ConflictRecord> conflicts = [];
  List<ExistingVault> recentVaults = [];
  final Map<String, String> spbIconIdByUiIcon = {};
  Map<String, String> categoryIconsByPath = {};
  Set<String> categoryPaths = {};
  final Set<String> revealed = {};
  final Map<String, String> syncConfig = {};

  bool get createMode => entryMode == EntryMode.createSwl;

  String get normalizedVaultBaseName {
    final rawName = vaultNameController.text
        .trim()
        .replaceAll(RegExp(r'\.swl$', caseSensitive: false), '');
    final safeName = rawName.isEmpty ? 'personal' : rawName;
    return safeName.replaceAll(RegExp(r'[^\wа-яА-ЯёЁ.-]+', unicode: true), '_');
  }

  Future<File> swlVaultFile() async {
    final directory = await appVaultDirectory();
    return File('${directory.path}/$normalizedVaultBaseName.swl');
  }

  Future<File> recentVaultsFile() async =>
      File('${(await appStateDirectory()).path}/actitpass_recent_swl.json');

  Future<Directory> appStateDirectory() async {
    if (Platform.isAndroid) {
      final directory = Directory('${Directory.systemTemp.parent.path}/files');
      if (!directory.existsSync()) {
        directory.createSync(recursive: true);
      }
      return directory;
    }
    final directory = await getApplicationSupportDirectory();
    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
    }
    return directory;
  }

  Future<Directory> appVaultDirectory() async {
    final base = Platform.isAndroid
        ? await appStateDirectory()
        : await getApplicationDocumentsDirectory();
    final directory = Directory('${base.path}/ActitPassStorage');
    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
    }
    return directory;
  }

  bool isAndroidCacheWalletPath(String path) =>
      Platform.isAndroid && path.contains('/cache/spbwallet_');

  @override
  void initState() {
    super.initState();
    searchController.addListener(() => setState(() {}));
    loadRecentVaults();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        passwordFocusNode.requestFocus();
      }
    });
  }

  void synchronizeWindowMode() {
    if (!Platform.isWindows) return;
    final desiredMode = unlocked
        ? 'main'
        : message == null
            ? 'login'
            : 'loginExpanded';
    if (configuredWindowMode == desiredMode) return;
    configuredWindowMode = desiredMode;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (unlocked) {
        configureMainWindow();
      } else {
        configureLoginWindow(expanded: message != null);
      }
    });
  }

  Future<void> configureLoginWindow({bool expanded = false}) async {
    if (!Platform.isWindows) return;
    try {
      await windowChannel.invokeMethod<void>(
        expanded ? 'showLoginExpanded' : 'showLogin',
      );
    } on MissingPluginException {
      // Other Flutter targets do not provide the Win32 window channel.
    }
  }

  Future<void> configureMainWindow() async {
    if (!Platform.isWindows) return;
    try {
      await windowChannel.invokeMethod<void>('showMain');
    } on MissingPluginException {
      // Other Flutter targets do not provide the Win32 window channel.
    }
  }

  Future<void> startLoginWindowDrag() async {
    if (!Platform.isWindows) return;
    try {
      await windowChannel.invokeMethod<void>('startDrag');
    } on MissingPluginException {
      // Other Flutter targets do not provide the Win32 window channel.
    }
  }

  @override
  void dispose() {
    spbWallet?.close();
    vaultNameController.dispose();
    passwordController.dispose();
    confirmController.dispose();
    searchController.dispose();
    passwordFocusNode.dispose();
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
          applySpbSnapshot(snapshot);
          conflicts = [];
          lastSyncAt = null;
          selectedItemId = items.isEmpty ? null : items.first.id;
          unlocked = true;
          activeView = 'cards';
          message = null;
        });
        if (!Platform.isAndroid || spbWalletUri == null) {
          await rememberRecentVault(spbWalletPath!);
        }
      } catch (error) {
        setState(() => message =
            'Не удалось открыть базу. Проверьте правильность пароля.');
      }
      return;
    }
    if (createMode && password != confirmController.text) {
      setState(() => message = 'Пароли не совпадают.');
      return;
    }
    if (createMode) {
      if (creatingVault) return;
      setState(() {
        creatingVault = true;
        message = null;
      });
      await WidgetsBinding.instance.endOfFrame;
      await Future<void>.delayed(const Duration(milliseconds: 16));
      try {
        await createSwlVault(password);
      } catch (error) {
        setState(() => message = 'Не удалось создать .swl базу: $error');
      } finally {
        if (mounted) {
          setState(() => creatingVault = false);
        }
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
          spbWalletDisplayPath =
              picked['displayPath']?.toString() ?? spbWalletUri;
          syncSourcePath = null;
          syncSourceUrl = null;
          syncOriginProvider = null;
          vaultNameController.text = picked['displayName']?.toString() ??
              File(path).uri.pathSegments.last;
          message = null;
        });
        final uri = spbWalletUri;
        if (uri != null && uri.isNotEmpty) {
          await rememberRecentVaultEntry(ExistingVault(
            title: vaultNameController.text,
            uri: uri,
            displayPath: spbWalletDisplayPath,
          ));
        }
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
      spbWalletDisplayPath = path;
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
      final file = await recentVaultsFile();
      if (file.existsSync()) {
        final decoded = jsonDecode(await file.readAsString()) as List<dynamic>;
        for (final raw in decoded) {
          ExistingVault? vault;
          if (raw is String) {
            final file = File(raw);
            if (isAndroidCacheWalletPath(file.path)) continue;
            if (!file.existsSync() ||
                !file.path.toLowerCase().endsWith('.swl')) {
              continue;
            }
            vault = ExistingVault(
              title: _vaultTitleFromPath(file.path),
              path: file.path,
              displayPath: file.path,
            );
          } else if (raw is Map<String, dynamic>) {
            vault = ExistingVault.fromJson(raw);
            if (vault.uri == null) {
              final path = vault.path;
              if (path == null || isAndroidCacheWalletPath(path)) continue;
              if (!File(path).existsSync() ||
                  !path.toLowerCase().endsWith('.swl')) {
                continue;
              }
            }
          } else if (raw is Map) {
            vault = ExistingVault.fromJson(Map<String, dynamic>.from(raw));
          }
          if (vault == null) continue;
          if (found.any((entry) => entry.key == vault!.key)) {
            continue;
          }
          found.add(vault);
        }
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() => recentVaults = found);
    if (found.isNotEmpty &&
        !unlocked &&
        entryMode == EntryMode.openSwl &&
        (spbWalletPath == null || spbWalletPath!.isEmpty)) {
      await chooseExistingVault(found.first);
    }
  }

  Future<void> rememberRecentVault(String path) async {
    if (path.isEmpty) return;
    if (isAndroidCacheWalletPath(path)) return;
    await rememberRecentVaultEntry(ExistingVault(
      title: _vaultTitleFromPath(path),
      path: path,
      displayPath: path,
    ));
  }

  Future<void> rememberRecentVaultEntry(ExistingVault vault) async {
    final entries = [
      vault,
      ...recentVaults.where((entry) => entry.key != vault.key).where((entry) =>
          entry.uri != null ||
          (entry.path != null && !isAndroidCacheWalletPath(entry.path!))),
    ].take(8).toList();
    final file = await recentVaultsFile();
    await file.writeAsString(const JsonEncoder.withIndent('  ')
        .convert(entries.map((entry) => entry.toJson()).toList()));
    if (!mounted) return;
    setState(() => recentVaults = entries);
  }

  Future<void> createSwlVault(String password, {File? targetFile}) async {
    final file = targetFile ?? await swlVaultFile();
    if (file.existsSync()) {
      throw StateError(
          'База "${file.uri.pathSegments.last}" уже есть. Выберите другое название или откройте существующую базу.');
    }
    final sourceTemplates = builtInTemplates();
    final templateMap = <String, CardTemplate>{};
    final preparedTemplates = <CardTemplate>[];
    final preparedItems = <SecretItem>[];
    for (final template in sourceTemplates) {
      final prepared = prepareSpbTemplate(template, true);
      templateMap[template.id] = prepared;
      preparedTemplates.add(prepared);
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
      preparedItems.add(
        SecretItem(
          id: SpbWalletDatabase.makeId(),
          templateId: template.id,
          title: item.title,
          category: item.category,
          colorId: item.colorId,
          values: {
            for (final entry in item.values.entries)
              if (fieldMap[entry.key] != null)
                fieldMap[entry.key]!: entry.value,
          },
          modifiedAt: item.modifiedAt,
          iconId: item.iconId,
          backgroundImageBase64: item.backgroundImageBase64,
        ),
      );
    }

    final payload = <String, dynamic>{
      'path': file.path,
      'password': password,
      'templates':
          preparedTemplates.map((template) => template.toJson()).toList(),
      'items': preparedItems.map((item) {
        final json = item.toJson();
        json['cardColor'] = paletteColorToSpb(item.colorId);
        return json;
      }).toList(),
      'categoryIcons': demoCategoryIcons(),
    };
    await compute<Map<String, dynamic>, bool>(
      createInitialSwlVaultFile,
      payload,
    );

    spbIconIdByUiIcon.clear();
    final wallet = SpbWalletDatabase.open(file.path, password);
    final snapshot = wallet.loadSnapshot();
    spbWallet?.close();
    spbWallet = wallet;
    setState(() {
      spbWalletPath = file.path;
      spbWalletUri = null;
      spbWalletDisplayPath = file.path;
      syncSourcePath = null;
      syncSourceUrl = null;
      syncOriginProvider = null;
      applySpbSnapshot(snapshot);
      conflicts = [];
      lastSyncAt = null;
      selectedItemId = items.isEmpty ? null : items.first.id;
      unlocked = true;
      activeView = 'cards';
      message = null;
    });
    await rememberRecentVault(file.path);
  }

  Future<void> createNewVaultFromLogin() async {
    final pathController = TextEditingController();
    final nameController = TextEditingController(text: 'Новая база');
    final newPasswordController = TextEditingController();
    final repeatPasswordController = TextEditingController();
    var showNewPassword = false;
    var showRepeatedPassword = false;
    var isCreating = false;
    String? dialogError;

    Future<void> pickNewVaultDirectory(StateSetter setDialogState) async {
      final selectedDirectory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Назначить путь для новой базы',
        lockParentWindow: true,
      );
      if (selectedDirectory == null || selectedDirectory.trim().isEmpty) {
        return;
      }
      setDialogState(() {
        pathController.text = selectedDirectory;
        dialogError = null;
      });
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xffececec),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
          ),
          titlePadding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
          title: GestureDetector(
            key: const Key('newVaultDialogDragHandle'),
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) {
              unawaited(startLoginWindowDrag());
            },
            child: const SizedBox(
              height: 38,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Создание новой базы'),
              ),
            ),
          ),
          content: Theme(
            data: Theme.of(context).copyWith(
              inputDecorationTheme: const InputDecorationTheme(
                filled: true,
                fillColor: Colors.white,
              ),
            ),
            child: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      key: const Key('newVaultPath'),
                      controller: pathController,
                      readOnly: true,
                      autofocus: true,
                      onTap: () => pickNewVaultDirectory(setDialogState),
                      decoration: InputDecoration(
                        labelText: 'Назначить путь',
                        hintText: 'Выберите папку для новой базы',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          key: const Key('browseNewVaultPath'),
                          tooltip: 'Выбрать папку в проводнике',
                          icon: const Icon(Icons.folder_open_outlined),
                          onPressed: () =>
                              pickNewVaultDirectory(setDialogState),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('newVaultName'),
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Название базы',
                        suffixText: '.swl',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    PasswordField(
                      key: const Key('newVaultPassword'),
                      controller: newPasswordController,
                      label: 'Новый пароль',
                      visible: showNewPassword,
                      onToggle: () => setDialogState(
                        () => showNewPassword = !showNewPassword,
                      ),
                    ),
                    const SizedBox(height: 12),
                    PasswordField(
                      key: const Key('newVaultPasswordRepeat'),
                      controller: repeatPasswordController,
                      label: 'Повторите новый пароль',
                      visible: showRepeatedPassword,
                      onToggle: () => setDialogState(
                        () => showRepeatedPassword = !showRepeatedPassword,
                      ),
                    ),
                    if (dialogError != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        dialogError!,
                        key: const Key('newVaultError'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
          actions: [
            SizedBox(
              width: 110,
              child: IgnorePointer(
                ignoring: isCreating,
                child: Opacity(
                  opacity: isCreating ? 0.6 : 1,
                  child: passwordKey(
                    key: const Key('confirmCreateVault'),
                    label: 'OK',
                    height: 40,
                    fontSize: 18,
                    onPressed: () async {
                      final selectedDirectory = pathController.text.trim();
                      final name = nameController.text.trim().replaceAll(
                          RegExp(r'\.swl$', caseSensitive: false), '');
                      final newPassword = newPasswordController.text;
                      if (selectedDirectory.isEmpty) {
                        setDialogState(
                          () => dialogError =
                              'Назначьте путь для файла новой базы.',
                        );
                        return;
                      }
                      if (name.isEmpty) {
                        setDialogState(
                            () => dialogError = 'Введите название базы.');
                        return;
                      }
                      if (newPassword.isEmpty) {
                        setDialogState(
                            () => dialogError = 'Введите новый пароль.');
                        return;
                      }
                      if (newPassword != repeatPasswordController.text) {
                        setDialogState(
                            () => dialogError = 'Новые пароли не совпадают.');
                        return;
                      }

                      final previousName = vaultNameController.text;
                      setDialogState(() {
                        isCreating = true;
                        dialogError = null;
                      });
                      vaultNameController.text = name;
                      try {
                        final targetFile = File(
                          '${Directory(selectedDirectory).path}'
                          '${Platform.pathSeparator}'
                          '$normalizedVaultBaseName.swl',
                        );
                        await createSwlVault(
                          newPassword,
                          targetFile: targetFile,
                        );
                        entryMode = EntryMode.openSwl;
                        if (dialogContext.mounted) {
                          Navigator.of(dialogContext).pop();
                        }
                      } catch (error) {
                        vaultNameController.text = previousName;
                        if (dialogContext.mounted) {
                          setDialogState(() {
                            isCreating = false;
                            dialogError =
                                'Не удалось создать .swl базу: $error';
                          });
                        }
                      }
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 124,
              child: IgnorePointer(
                ignoring: isCreating,
                child: Opacity(
                  opacity: isCreating ? 0.6 : 1,
                  child: passwordKey(
                    key: const Key('cancelCreateVault'),
                    label: 'Отмена',
                    height: 40,
                    fontSize: 17,
                    top: const Color(0xffd32b31),
                    bottom: const Color(0xff7f0609),
                    onPressed: () => Navigator.of(dialogContext).pop(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    pathController.dispose();
    nameController.dispose();
    newPasswordController.dispose();
    repeatPasswordController.dispose();
    if (mounted && !unlocked) passwordFocusNode.requestFocus();
  }

  Map<String, String> demoCategoryIcons() => const {
        'Примеры': 'bookmark',
        'Примеры / Доступы': 'key',
        'Примеры / Финансы': 'bank',
        'Примеры / Работа': 'briefcase',
        'Примеры / Сервисы': 'globe',
        'Примеры / Документы': 'id',
        'Примеры / О программе': 'info',
      };

  Future<void> connectSyncVault(String password) async {
    if (syncProvider == 'mounted_folder') {
      final source = resolveMountedFolderSyncFile();
      final localName = vaultNameController.text.trim().isEmpty
          ? source.uri.pathSegments.last
              .replaceAll(RegExp(r'\.swl$', caseSensitive: false), '')
          : vaultNameController.text.trim();
      vaultNameController.text = localName;
      final local = await swlVaultFile();
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
      final local = await swlVaultFile();
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
      spbWalletDisplayPath = sourcePath ?? sourceUrl ?? localPath;
      syncSourcePath = sourcePath;
      syncSourceUrl = sourceUrl;
      syncOriginProvider = syncProvider;
      applySpbSnapshot(snapshot);
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

  Future<void> chooseExistingVault(ExistingVault vault) async {
    try {
      if (Platform.isAndroid && vault.uri != null) {
        final copied = await spbWalletChannel
            .invokeMapMethod<String, Object?>('copySpbWallet', {
          'uri': vault.uri,
          'displayName': vault.title,
        });
        final localPath = copied?['localPath']?.toString();
        if (localPath == null || localPath.isEmpty) {
          throw StateError('Не удалось открыть выбранную .swl базу.');
        }
        setState(() {
          entryMode = EntryMode.openSwl;
          message = null;
          spbWalletPath = localPath;
          spbWalletUri = vault.uri;
          spbWalletDisplayPath =
              copied?['displayPath']?.toString() ?? vault.displayPath;
          syncSourcePath = null;
          syncSourceUrl = null;
          syncOriginProvider = null;
          vaultNameController.text =
              copied?['displayName']?.toString() ?? vault.title;
        });
      } else {
        setState(() {
          entryMode = EntryMode.openSwl;
          message = null;
          spbWalletPath = vault.path;
          spbWalletUri = null;
          spbWalletDisplayPath = vault.displayPath ?? vault.path;
          syncSourcePath = null;
          syncSourceUrl = null;
          syncOriginProvider = null;
          vaultNameController.text = vault.title;
        });
      }
      await rememberRecentVaultEntry(ExistingVault(
        title: vaultNameController.text,
        path: Platform.isAndroid && spbWalletUri != null ? null : spbWalletPath,
        uri: spbWalletUri,
        displayPath: spbWalletDisplayPath,
      ));
    } catch (error) {
      setState(
          () => message = 'Не удалось открыть последнюю .swl базу: $error');
    }
  }

  Future<bool> writeBackSpbWallet() async {
    var ok = true;
    try {
      spbWallet?.flushToDisk();
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
        title: 'Демо: личный кабинет',
        category: 'Примеры / Доступы',
        colorId: 'blue',
        modifiedAt: now,
        values: {
          'username': 'user@example.com',
          'password': 'Example-Password-2026!',
          'url': 'https://example.com/login',
          'notes':
              'Нажмите на любое поле в просмотре карточки, чтобы скопировать значение. Поля типа пароль и секрет скрываются по умолчанию.',
        },
      ),
      SecretItem(
        id: makeId('item'),
        templateId: 'tpl_payment_card',
        title: 'Демо: банковская карта',
        category: 'Примеры / Финансы',
        colorId: 'teal',
        modifiedAt: now,
        values: {
          'holder': 'DEMO USER',
          'number': '2200 0000 0000 1234',
          'expires': '2028-11',
          'cvv': '927',
        },
      ),
      SecretItem(
        id: makeId('item'),
        templateId: 'tpl_bank_account',
        title: 'Демо: банковский счет',
        category: 'Примеры / Финансы',
        colorId: 'blue',
        modifiedAt: now,
        values: {
          'bank': 'Демо Банк',
          'account': '40817810000000000000',
          'login': 'demo-bank-login',
          'password': 'Demo-Bank-Password!',
        },
      ),
      SecretItem(
        id: makeId('item'),
        templateId: 'tpl_email_account',
        title: 'Демо: почтовый аккаунт',
        category: 'Примеры / Доступы',
        colorId: 'green',
        modifiedAt: now,
        values: {
          'email': 'mailbox@example.com',
          'password': 'Mail-Example-Secret!',
          'recovery': 'backup@example.com',
          'notes':
              'Для почты удобно хранить основной пароль, резервный адрес и подсказки по восстановлению.',
        },
      ),
      SecretItem(
        id: makeId('item'),
        templateId: 'tpl_api_key',
        title: 'Демо: API ключ',
        category: 'Примеры / Работа',
        colorId: 'violet',
        modifiedAt: now,
        values: {
          'service': 'Example Cloud',
          'url': 'https://console.example.com',
          'token': 'ex_live_000000000000000000000000',
          'notes':
              'В заметках можно указать права ключа, дату выпуска и где он используется.',
        },
      ),
      SecretItem(
        id: makeId('item'),
        templateId: 'tpl_crypto_wallet',
        title: 'Демо: криптокошелек',
        category: 'Примеры / Финансы',
        colorId: 'amber',
        modifiedAt: now,
        values: {
          'wallet': 'Demo Wallet',
          'address': 'bc1qexample000000000000000000000000000000',
          'seed': 'example seed phrase words are stored here as a secret',
          'pin': '000000',
          'notes':
              'Это пример структуры. Реальные seed-фразы стоит хранить особенно осторожно и иметь офлайн-резервную копию.',
        },
      ),
      SecretItem(
        id: makeId('item'),
        templateId: 'tpl_subscription',
        title: 'Демо: подписка',
        category: 'Примеры / Сервисы',
        colorId: 'blue',
        modifiedAt: now,
        values: {
          'service': 'Example Plus',
          'login': 'user@example.com',
          'renewal': '2026-12-01',
          'price': '990',
          'notes':
              'Можно хранить дату продления, стоимость и условия отмены подписки.',
        },
      ),
      SecretItem(
        id: makeId('item'),
        templateId: 'tpl_travel',
        title: 'Демо: поездка',
        category: 'Примеры / Документы',
        colorId: 'violet',
        modifiedAt: now,
        values: {
          'carrier': 'Example Airlines',
          'booking': 'ABC123',
          'date': '2026-08-15',
          'document': 'Demo Passport 000000000',
          'notes':
              'Для поездок можно хранить бронь, дату, номер документа и добавить вложения с билетами.',
        },
      ),
      SecretItem(
        id: makeId('item'),
        templateId: 'tpl_note',
        title: 'Как устроена база',
        category: 'Примеры / О программе',
        colorId: 'neutral',
        modifiedAt: now,
        values: {
          'note':
              'База создается и открывается как обычный файл SPB Wallet .swl. При открытии существующей базы приложение старается не конвертировать формат, а записывать изменения обратно в исходную .swl базу.',
        },
      ),
      SecretItem(
        id: makeId('item'),
        templateId: 'tpl_note',
        title: 'Открытие базы',
        category: 'Примеры / О программе',
        colorId: 'neutral',
        modifiedAt: now,
        values: {
          'note':
              'На стартовом экране можно выбрать .swl файл вручную или открыть один из последних выбранных файлов. На Android выбранный файл показывается как исходный файл из Downloads, хотя технически SQLite работает через временную рабочую копию.',
        },
      ),
      SecretItem(
        id: makeId('item'),
        templateId: 'tpl_note',
        title: 'Заметки и вложения',
        category: 'Примеры / О программе',
        colorId: 'neutral',
        modifiedAt: now,
        values: {
          'note':
              'У карточек есть кнопка вложений. В просмотре вложения открываются без редактирования, а изменение вложений доступно через режим редактирования карточки.',
        },
      ),
      SecretItem(
        id: makeId('item'),
        templateId: 'tpl_note',
        title: 'Копирование значений',
        category: 'Примеры / О программе',
        colorId: 'neutral',
        modifiedAt: now,
        values: {
          'note':
              'В просмотре карточки нажмите на поле, чтобы скопировать его значение. Для паролей копируется настоящее значение, даже если на экране показаны точки.',
        },
      ),
      SecretItem(
        id: makeId('item'),
        templateId: 'tpl_note',
        title: 'Шаблоны',
        category: 'Примеры / О программе',
        colorId: 'neutral',
        modifiedAt: now,
        values: {
          'note':
              'Встроенные шаблоны служат стартовой библиотекой. Их можно копировать и на основе копии создавать свой вариант с нужными полями и пиктограммой.',
        },
      ),
    ];
  }

  List<CardTemplate> spbTemplatesToUi(List<SpbWalletTemplateRecord> source) {
    return source.map((template) {
      final fields = template.fields.map((field) {
        final type = spbFieldTypeToUi(field.fieldTypeId, field.name);
        final secret = spbFieldIsSecret(field.fieldTypeId, field.name);
        return FieldDefinition(
          id: field.id,
          label: field.name.isEmpty ? 'Поле' : field.name,
          type: type,
          secret: secret,
        );
      }).toList();
      if (!fields.any(isRealNotesField)) {
        fields.add(const FieldDefinition(
            id: spbDescriptionFieldId,
            label: 'Заметки',
            type: 'multiline_note'));
      }
      final iconId = spbOriginalIconAsset(template.iconId) == null
          ? defaultIconForTemplateName(
              template.name,
              template.fields.map((field) => field.name),
            )
          : template.iconId.toUpperCase();
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

  void applySpbSnapshot(SpbWalletSnapshot snapshot) {
    templates = spbTemplatesToUi(snapshot.templates);
    items = spbCardsToUi(snapshot.cards);
    categoryIconsByPath = spbCategoryIconsToUi(snapshot.categories);
    categoryPaths = spbCategoryPathsToUi(snapshot.categories);
  }

  String spbFieldTypeToUi(int fieldTypeId, [String fieldName = '']) {
    if (spbFieldIsSecret(fieldTypeId, fieldName)) {
      return secretFieldTypeForName(fieldName);
    }
    switch (fieldTypeId) {
      case 3:
        return 'date';
      case 4:
        return 'multiline_note';
      case 6:
        return 'url';
      case 7:
        return 'email';
      case 8:
        return 'phone';
      default:
        return 'text';
    }
  }

  bool spbFieldIsSecret(int fieldTypeId, String fieldName) {
    return isSpbSecretField(fieldName);
  }

  String secretFieldTypeForName(String fieldName) {
    final normalized = fieldName.trim().toLowerCase();
    if (normalized.contains('парол') ||
        normalized.contains('password') ||
        normalized.contains('pass')) {
      return 'password';
    }
    return 'custom_secret';
  }

  List<SecretItem> spbCardsToUi(List<SpbWalletCardRecord> source) {
    return source.map((card) {
      final template = templateFor(card.templateId);
      final iconId = uiIconForSpbIcon(card.iconId) ?? template.iconId;
      final values = Map<String, String>.from(card.fieldValues);
      final descriptionFieldId = noteFieldIdForTemplate(template);
      if (card.description.trim().isNotEmpty &&
          (values[descriptionFieldId]?.trim().isEmpty ?? true)) {
        values[descriptionFieldId] = card.description;
      }
      rememberSpbIcon(iconId, card.iconId);
      return SecretItem(
        id: card.id,
        templateId: card.templateId,
        title: card.title.isEmpty ? '.swl карточка' : card.title,
        category: card.categoryPath,
        colorId: spbColorToPaletteId(card.cardColor),
        iconId: iconId,
        values: values,
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
        spbColor: card.cardColor,
      );
    }).toList();
  }

  void rememberSpbIcon(String uiIconId, String spbIconId) {
    if (spbIconId.isEmpty || !isSpbHexId(spbIconId)) return;
    spbIconIdByUiIcon.putIfAbsent(uiIconId, () => spbIconId);
  }

  String? uiIconForSpbIcon(String spbIconId) {
    if (spbIconId.isEmpty) return null;
    if (spbOriginalIconAsset(spbIconId) != null) {
      return spbIconId.toUpperCase();
    }
    final synthetic = uiIconIdFromSyntheticSpbIcon(spbIconId);
    if (synthetic != null) return synthetic;
    for (final entry in spbIconIdByUiIcon.entries) {
      if (entry.value == spbIconId) return entry.key;
    }
    return null;
  }

  String? spbIconIdForUi(String uiIconId, String fallbackUiIconId) {
    if (isSpbHexId(uiIconId)) return uiIconId.toUpperCase();
    final direct = spbIconIdByUiIcon[uiIconId];
    if (direct != null && isSpbHexId(direct)) return direct;
    if (uiIconId == fallbackUiIconId) {
      final fallback = spbIconIdByUiIcon[fallbackUiIconId];
      if (fallback != null && isSpbHexId(fallback)) return fallback;
    }
    return syntheticSpbIconIdForUi(uiIconId);
  }

  Map<String, String> spbCategoryIconsToUi(
      List<SpbWalletCategoryRecord> categories) {
    final byId = {for (final category in categories) category.id: category};
    final result = <String, String>{};
    String pathFor(SpbWalletCategoryRecord category) {
      final names = <String>[];
      var current = category;
      var guard = 0;
      while (guard++ < 64) {
        if (current.name.isNotEmpty) names.add(current.name);
        final parent = byId[current.parentId];
        if (parent == null) break;
        current = parent;
      }
      return names.reversed.join(' / ');
    }

    for (final category in categories) {
      final path = pathFor(category);
      if (path.isEmpty) continue;
      final fallbackIconId = defaultIconForCategoryPath(path);
      final resolvedIconId = uiIconForSpbIcon(category.iconId);
      final iconId = (resolvedIconId == null ||
              (resolvedIconId == 'key' && fallbackIconId != 'key') ||
              (resolvedIconId == 'folder' && fallbackIconId != 'folder'))
          ? fallbackIconId
          : resolvedIconId;
      rememberSpbIcon(iconId, category.iconId);
      result[path] = iconId;
    }
    return result;
  }

  Set<String> spbCategoryPathsToUi(List<SpbWalletCategoryRecord> categories) {
    final byId = {for (final category in categories) category.id: category};
    final result = <String>{};
    String pathFor(SpbWalletCategoryRecord category) {
      final names = <String>[];
      var current = category;
      var guard = 0;
      while (guard++ < 64) {
        if (current.name.isNotEmpty) names.add(current.name);
        final parent = byId[current.parentId];
        if (parent == null) break;
        current = parent;
      }
      return names.reversed.join(' / ');
    }

    for (final category in categories) {
      final path = pathFor(category);
      if (path.isNotEmpty) result.add(path);
    }
    return result;
  }

  String defaultIconForCategoryPath(String path) {
    final normalized = path.toLowerCase();
    if (normalized.contains('пример') || normalized.contains('demo')) {
      if (normalized.contains('финанс')) return 'bank';
      if (normalized.contains('работ')) return 'briefcase';
      if (normalized.contains('сервис')) return 'globe';
      if (normalized.contains('документ')) return 'id';
      if (normalized.contains('доступ')) return 'key';
      return 'bookmark';
    }
    if (normalized.contains('кредит') ||
        normalized.contains('карта') ||
        normalized.contains('card')) {
      return 'card';
    }
    if (normalized.contains('личн') ||
        normalized.contains('паспорт') ||
        normalized.contains('документ') ||
        normalized.contains('personal')) {
      return normalized.contains('паспорт') || normalized.contains('документ')
          ? 'id'
          : 'contact';
    }
    if (normalized.contains('путеше') ||
        normalized.contains('ави') ||
        normalized.contains('билет') ||
        normalized.contains('travel') ||
        normalized.contains('flight')) {
      return 'plane';
    }
    if (normalized.contains('программ') ||
        normalized.contains('about') ||
        normalized.contains('spb')) {
      return 'info';
    }
    if (normalized.contains('банк') ||
        normalized.contains('финанс') ||
        normalized.contains('деньг') ||
        normalized.contains('money')) {
      return 'bank';
    }
    if (normalized.contains('почт') || normalized.contains('mail')) {
      return 'mail';
    }
    if (normalized.contains('работ') ||
        normalized.contains('проект') ||
        normalized.contains('office') ||
        normalized.contains('work')) {
      return 'briefcase';
    }
    if (normalized.contains('сервис') ||
        normalized.contains('сайт') ||
        normalized.contains('web') ||
        normalized.contains('internet')) {
      return 'globe';
    }
    if (normalized.contains('дом') || normalized.contains('home')) {
      return 'home';
    }
    if (normalized.contains('здоров') || normalized.contains('мед')) {
      return 'heart';
    }
    if (normalized.contains('сем') || normalized.contains('family')) {
      return 'family';
    }
    if (normalized.contains('покуп') || normalized.contains('shop')) {
      return 'cart';
    }
    if (normalized.contains('архив') || normalized.contains('archive')) {
      return 'snowflake';
    }
    return 'folder';
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
    synchronizeWindowMode();
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
                      SizedBox(width: 56, child: buildCollapsedRail()),
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

  bool isMenuOpen(bool compact) => menuOpenOverride ?? false;

  void toggleMenu(bool compact) {
    final current = isMenuOpen(compact);
    setState(() => menuOpenOverride = !current);
  }

  Future<void> lockVault() async {
    await writeBackSpbWallet();
    spbWallet?.close();
    spbWallet = null;
    syncSourcePath = null;
    syncSourceUrl = null;
    syncOriginProvider = null;
    passwordController.clear();
    setState(() {
      unlocked = false;
      message = null;
    });
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

  Widget buildCollapsedRail() {
    return Material(
      color: Colors.white,
      child: Column(
        children: [
          const SizedBox(height: 8),
          IconButton(
            tooltip: 'Меню',
            icon: const Icon(Icons.menu),
            onPressed: () => toggleMenu(false),
          ),
          const Divider(height: 16),
          ...navEntries.map(
            (entry) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: IconButton(
                tooltip: entry.label,
                isSelected: activeView == entry.id,
                icon: Icon(entry.icon),
                selectedIcon: Icon(entry.icon),
                style: IconButton.styleFrom(
                  backgroundColor: activeView == entry.id
                      ? Theme.of(context).colorScheme.primaryContainer
                      : null,
                  foregroundColor: activeView == entry.id
                      ? Theme.of(context).colorScheme.onPrimaryContainer
                      : null,
                ),
                onPressed: () => setState(() => activeView = entry.id),
              ),
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Заблокировать',
            icon: const Icon(Icons.lock_outline),
            onPressed: lockVault,
          ),
          const SizedBox(height: 8),
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
      final path = spbWalletDisplayPath ?? spbWalletPath;
      if (path == null || path.isEmpty) return '.swl база';
      if (path.startsWith('content://')) {
        final name = vaultNameController.text.trim();
        return name.isEmpty ? '.swl база' : name;
      }
      return File(path).uri.pathSegments.isEmpty
          ? path
          : File(path).uri.pathSegments.last;
    }
    final name = vaultNameController.text.trim();
    return name.isEmpty ? 'personal' : name;
  }

  String? spbWalletUserPath() => spbWalletDisplayPath ?? spbWalletPath;

  String lastSyncText() {
    final value = lastSyncAt;
    if (value == null) return 'не выполнялась';
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(local.day)}.${two(local.month)}.${local.year} ${two(local.hour)}:${two(local.minute)}';
  }

  String get selectedVaultTitle {
    final path = spbWalletDisplayPath ?? spbWalletPath;
    String withoutSwlExtension(String name) =>
        name.replaceFirst(RegExp(r'\.swl$', caseSensitive: false), '');
    if (path != null && path.isNotEmpty) {
      if (path.startsWith('content://')) {
        final name = vaultNameController.text.trim();
        return name.isEmpty ? 'база' : withoutSwlExtension(name);
      }
      return withoutSwlExtension(_vaultTitleFromPath(path));
    }
    if (recentVaults.isNotEmpty) {
      return withoutSwlExtension(recentVaults.first.title);
    }
    return 'файл не выбран';
  }

  void insertPasswordText(String value) {
    final nextText = '${passwordController.text}$value';
    passwordController.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextText.length),
    );
    passwordFocusNode.requestFocus();
  }

  void backspacePassword() {
    final text = passwordController.text;
    if (text.isNotEmpty) {
      final nextText = text.substring(0, text.length - 1);
      passwordController.value = TextEditingValue(
        text: nextText,
        selection: TextSelection.collapsed(offset: nextText.length),
      );
    }
    passwordFocusNode.requestFocus();
  }

  void clearPassword() {
    passwordController.clear();
    passwordFocusNode.requestFocus();
  }

  Future<void> exitApplication() async {
    passwordController.clear();
    confirmController.clear();
    spbWallet?.close();
    spbWallet = null;
    spbWalletPath = null;
    spbWalletUri = null;
    spbWalletDisplayPath = null;
    recentVaults.clear();
    try {
      final historyFile = await recentVaultsFile();
      if (historyFile.existsSync()) {
        await historyFile.delete();
      }
    } catch (_) {
      // Exit must still complete if the recent-file state cannot be removed.
    }
    if (Platform.isAndroid || Platform.isIOS) {
      await SystemNavigator.pop();
    } else {
      exit(0);
    }
  }

  Widget passwordKey({
    required String label,
    required VoidCallback onPressed,
    Color top = const Color(0xff2483bc),
    Color bottom = const Color(0xff07436c),
    double fontSize = 34,
    FontWeight fontWeight = FontWeight.w500,
    double height = 62,
    Key? key,
  }) {
    return Semantics(
      button: true,
      label: label,
      child: SizedBox(
        height: height,
        child: Material(
          key: key,
          color: Colors.transparent,
          child: Ink(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [top, bottom],
              ),
              border: Border.all(color: const Color(0xff5c6870)),
              borderRadius: BorderRadius.circular(3),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  offset: Offset(0, 2),
                  blurRadius: 2,
                ),
              ],
            ),
            child: InkWell(
              onTap: onPressed,
              borderRadius: BorderRadius.circular(3),
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: fontSize,
                    height: 1,
                    fontWeight: fontWeight,
                    shadows: const [
                      Shadow(color: Colors.black45, offset: Offset(1, 1)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget keypadRow(List<Widget> children) => Row(
        children: [
          for (var index = 0; index < children.length; index++) ...[
            if (index > 0) const SizedBox(width: 5),
            Expanded(child: children[index]),
          ],
        ],
      );

  void selectVirtualKeyboardMode(VirtualKeyboardMode mode) {
    setState(() => virtualKeyboardMode = mode);
    passwordFocusNode.requestFocus();
  }

  Widget buildPasswordKeyboard({
    required Color redTop,
    required Color redBottom,
  }) {
    if (virtualKeyboardMode == VirtualKeyboardMode.symbols) {
      Widget symbolKey(String symbol) => passwordKey(
            key: Key('keypadSymbol$symbol'),
            label: symbol,
            height: 84,
            fontSize: 25,
            onPressed: () => insertPasswordText(symbol),
          );

      return Column(
        children: [
          keypadRow([
            for (final symbol in [
              '+',
              '×',
              '÷',
              '=',
              '/',
              '_',
              '<',
              '>',
              '[',
              ']'
            ])
              symbolKey(symbol),
          ]),
          const SizedBox(height: 5),
          keypadRow([
            for (final symbol in [
              '!',
              '@',
              '#',
              r'$',
              '%',
              '^',
              '&',
              '*',
              '(',
              ')'
            ])
              symbolKey(symbol),
          ]),
          const SizedBox(height: 5),
          keypadRow([
            passwordKey(
              key: const Key('keypadSymbolsPage'),
              label: '1/2',
              height: 84,
              fontSize: 18,
              onPressed: passwordFocusNode.requestFocus,
            ),
            for (final symbol in ['-', "'", '"', ':', ';', ',', '?'])
              symbolKey(symbol),
            passwordKey(
              key: const Key('keypadBackspace'),
              label: '<-',
              height: 84,
              fontSize: 22,
              top: redTop,
              bottom: redBottom,
              onPressed: backspacePassword,
            ),
          ]),
        ],
      );
    }

    if (virtualKeyboardMode != VirtualKeyboardMode.numeric) {
      final uppercase = virtualKeyboardMode == VirtualKeyboardMode.uppercase;
      Widget letterKey(String baseLetter) {
        final letter = uppercase ? baseLetter : baseLetter.toLowerCase();
        return passwordKey(
          key: Key('keypadLetter$letter'),
          label: letter,
          height: 84,
          fontSize: 24,
          onPressed: () => insertPasswordText(letter),
        );
      }

      return Column(
        children: [
          keypadRow([
            for (final letter in [
              'Q',
              'W',
              'E',
              'R',
              'T',
              'Y',
              'U',
              'I',
              'O',
              'P'
            ])
              letterKey(letter),
          ]),
          const SizedBox(height: 5),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: keypadRow([
              for (final letter in [
                'A',
                'S',
                'D',
                'F',
                'G',
                'H',
                'J',
                'K',
                'L'
              ])
                letterKey(letter),
            ]),
          ),
          const SizedBox(height: 5),
          keypadRow([
            passwordKey(
              key: const Key('keypadClear'),
              label: 'CLR',
              height: 84,
              fontSize: 17,
              top: redTop,
              bottom: redBottom,
              onPressed: clearPassword,
            ),
            for (final letter in ['Z', 'X', 'C', 'V', 'B', 'N', 'M'])
              letterKey(letter),
            passwordKey(
              key: const Key('keypadBackspace'),
              label: '<-',
              height: 84,
              fontSize: 22,
              top: redTop,
              bottom: redBottom,
              onPressed: backspacePassword,
            ),
          ]),
        ],
      );
    }

    return Column(
      children: [
        keypadRow([
          for (final digit in ['1', '2', '3'])
            passwordKey(
              key: Key('keypad$digit'),
              label: digit,
              onPressed: () => insertPasswordText(digit),
            ),
        ]),
        const SizedBox(height: 5),
        keypadRow([
          for (final digit in ['4', '5', '6'])
            passwordKey(
              key: Key('keypad$digit'),
              label: digit,
              onPressed: () => insertPasswordText(digit),
            ),
        ]),
        const SizedBox(height: 5),
        keypadRow([
          for (final digit in ['7', '8', '9'])
            passwordKey(
              key: Key('keypad$digit'),
              label: digit,
              onPressed: () => insertPasswordText(digit),
            ),
        ]),
        const SizedBox(height: 5),
        keypadRow([
          passwordKey(
            key: const Key('keypadClear'),
            label: 'CLR',
            fontSize: 29,
            top: redTop,
            bottom: redBottom,
            onPressed: clearPassword,
          ),
          passwordKey(
            key: const Key('keypad0'),
            label: '0',
            onPressed: () => insertPasswordText('0'),
          ),
          passwordKey(
            key: const Key('keypadBackspace'),
            label: '<-',
            fontSize: 31,
            top: redTop,
            bottom: redBottom,
            onPressed: backspacePassword,
          ),
        ]),
      ],
    );
  }

  Widget buildLocked() {
    const redTop = Color(0xffd32b31);
    const redBottom = Color(0xff7f0609);
    const modeTop = Color(0xffb96b25);
    const modeBottom = Color(0xff6d3107);

    return Scaffold(
      backgroundColor: const Color(0xfff4f4f4),
      body: SafeArea(
        child: Center(
          child: FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(
              width: 562,
              height: message == null ? 590 : 650,
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  padding: EdgeInsets.zero,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Container(
                      width: constraints.maxWidth,
                      decoration: BoxDecoration(
                        color: const Color(0xfff4f4f4),
                        border: Border.all(color: const Color(0xffc6c6c6)),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onPanStart: (_) {
                              unawaited(startLoginWindowDrag());
                            },
                            child: Container(
                              height: 44,
                              color: const Color(0xff777777),
                              alignment: Alignment.centerLeft,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              child: const Text(
                                'Пароль',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                ),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  'Введите пароль ($selectedVaultTitle)',
                                  key: const Key('passwordPrompt'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    color: Color(0xff16212a),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                FractionallySizedBox(
                                  widthFactor: 2 / 3,
                                  alignment: Alignment.centerLeft,
                                  child: TextField(
                                    key: const Key('passwordInput'),
                                    controller: passwordController,
                                    focusNode: passwordFocusNode,
                                    autofocus: true,
                                    obscureText: true,
                                    enableSuggestions: false,
                                    autocorrect: false,
                                    keyboardType: TextInputType.visiblePassword,
                                    textInputAction: TextInputAction.done,
                                    onSubmitted: (_) => unlock(),
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      filled: true,
                                      fillColor: Colors.white,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.zero,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 20),
                                buildPasswordKeyboard(
                                  redTop: redTop,
                                  redBottom: redBottom,
                                ),
                                const SizedBox(height: 6),
                                keypadRow([
                                  passwordKey(
                                    key: const Key('keypadModeUppercase'),
                                    label: 'ABC',
                                    fontSize: 23,
                                    top: modeTop,
                                    bottom: modeBottom,
                                    onPressed: () => selectVirtualKeyboardMode(
                                      VirtualKeyboardMode.uppercase,
                                    ),
                                  ),
                                  passwordKey(
                                    key: const Key('keypadModeLowercase'),
                                    label: 'abc',
                                    fontSize: 23,
                                    top: modeTop,
                                    bottom: modeBottom,
                                    onPressed: () => selectVirtualKeyboardMode(
                                      VirtualKeyboardMode.lowercase,
                                    ),
                                  ),
                                  passwordKey(
                                    key: const Key('keypadModeNumeric'),
                                    label: '123',
                                    fontSize: 23,
                                    top: modeTop,
                                    bottom: modeBottom,
                                    onPressed: () => selectVirtualKeyboardMode(
                                      VirtualKeyboardMode.numeric,
                                    ),
                                  ),
                                  passwordKey(
                                    key: const Key('keypadModeSymbols'),
                                    label: '#!?',
                                    fontSize: 23,
                                    top: modeTop,
                                    bottom: modeBottom,
                                    onPressed: () => selectVirtualKeyboardMode(
                                      VirtualKeyboardMode.symbols,
                                    ),
                                  ),
                                ]),
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 18),
                                  child: Divider(height: 1),
                                ),
                                Row(
                                  children: [
                                    PopupMenuButton<String>(
                                      key: const Key('fileMenu'),
                                      tooltip: 'Файл',
                                      onSelected: (value) {
                                        if (value == 'open') {
                                          pickSpbWalletFile();
                                        }
                                      },
                                      itemBuilder: (context) => const [
                                        PopupMenuItem(
                                          value: 'open',
                                          child: Row(
                                            children: [
                                              Icon(Icons.folder_open_outlined),
                                              SizedBox(width: 10),
                                              Text('Открыть файл…'),
                                            ],
                                          ),
                                        ),
                                      ],
                                      child: SizedBox(
                                        width: 110,
                                        height: 40,
                                        child: IgnorePointer(
                                          child: passwordKey(
                                            label: 'X',
                                            height: 40,
                                            fontSize: 18,
                                            onPressed: () {},
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    SizedBox(
                                      width: 110,
                                      child: passwordKey(
                                        key: const Key('createVault'),
                                        label: '+',
                                        height: 40,
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                        onPressed: createNewVaultFromLogin,
                                      ),
                                    ),
                                    const Spacer(),
                                    SizedBox(
                                      width: 110,
                                      child: passwordKey(
                                        key: const Key('loginOk'),
                                        label: 'OK',
                                        height: 40,
                                        fontSize: 18,
                                        onPressed: unlock,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    SizedBox(
                                      width: 124,
                                      child: passwordKey(
                                        key: const Key('loginCancel'),
                                        label: 'Отмена',
                                        height: 40,
                                        fontSize: 17,
                                        top: redTop,
                                        bottom: redBottom,
                                        onPressed: () {
                                          exitApplication();
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                                if (message != null) ...[
                                  const SizedBox(height: 12),
                                  Text(
                                    message!,
                                    key: const Key('loginMessage'),
                                    style: TextStyle(
                                      color:
                                          Theme.of(context).colorScheme.error,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget buildCreatingVaultOverlay() {
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.18),
        child: Center(
          child: Card(
            elevation: 8,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
                  const SizedBox(height: 16),
                  Text('Создаем .swl базу',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 6),
                  const Text(
                    'Добавляем шаблоны, папки и демо-карточки...',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget buildRecentVaultsPicker() {
    final visibleRows = min(recentVaults.length, 2);
    final height = 48.0 + visibleRows * 58.0 + max(0, visibleRows - 1) * 4.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        height: height.clamp(106.0, 168.0).toDouble(),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: Column(
          children: [
            SizedBox(
              height: 40,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Последние файлы',
                      style: Theme.of(context).textTheme.titleSmall),
                ),
              ),
            ),
            Divider(
              height: 1,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            Expanded(
              child: ListView.separated(
                primary: false,
                padding: const EdgeInsets.all(6),
                itemCount: recentVaults.length,
                separatorBuilder: (_, __) => const SizedBox(height: 4),
                itemBuilder: (context, index) {
                  final vault = recentVaults[index];
                  return SizedBox(
                    height: 54,
                    child: Material(
                      color:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () {
                          chooseExistingVault(vault);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 7),
                          child: Row(
                            children: [
                              const Icon(Icons.history, size: 20),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(vault.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 13)),
                                    const SizedBox(height: 2),
                                    Text(
                                      vault.displayPath ??
                                          vault.path ??
                                          vault.uri ??
                                          '',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
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
              subtitle: Text(spbWalletUserPath() ?? 'открытая .swl база'),
            ),
            const SizedBox(height: 12),
            ...navButtons(),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: lockVault,
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
        child: Row(
          children: [
            ...navButtons(compact: compact),
            Padding(
              padding: EdgeInsets.only(right: compact ? 8 : 0),
              child: OutlinedButton.icon(
                onPressed: lockVault,
                icon: const Icon(Icons.lock_outline),
                label: const Text('Заблокировать'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> navButtons({bool compact = false}) {
    return navEntries
        .map(
          (entry) => Padding(
            padding: EdgeInsets.only(
                bottom: compact ? 0 : 8, right: compact ? 8 : 0),
            child: NavigationButton(
              selected: activeView == entry.id,
              icon: entry.icon,
              label: entry.label,
              onTap: () => setState(() => activeView = entry.id),
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
                ],
              ),
              if (activeView != 'settings')
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
            child: ListView(
              children: [
                ExpansionTile(
                  initiallyExpanded: true,
                  leading: const Icon(Icons.account_balance_wallet_outlined),
                  title: Row(
                    children: [
                      const Expanded(child: Text('Мой кошелёк')),
                      Tooltip(
                        message: 'Создать папку',
                        child: IconButton(
                          icon: const Icon(Icons.create_new_folder_outlined),
                          onPressed: () => openCategoryEditorDialog(
                              parentPath: '', folder: null),
                        ),
                      ),
                    ],
                  ),
                  children: root.isEmpty
                      ? const [
                          ListTile(
                              dense: true, title: Text('Карточек не найдено'))
                        ]
                      : treeChildren(root, 0,
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
    for (final path in {...categoryPaths, ...categoryIconsByPath.keys}) {
      ensureCategoryTreeNode(root, path);
    }
    for (final item in source) {
      final node = ensureCategoryTreeNode(root, item.category);
      node.cards.add(item);
    }
    return root;
  }

  CategoryTreeNode ensureCategoryTreeNode(CategoryTreeNode root, String path) {
    var node = root;
    final pathParts = <String>[];
    for (final part in categoryParts(path)) {
      pathParts.add(part);
      final currentPath = pathParts.join(' / ');
      node = node.children.putIfAbsent(
        part,
        () => CategoryTreeNode(
          part,
          path: currentPath,
          iconId: categoryIconsByPath[currentPath],
        ),
      );
    }
    return node;
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
      ...categoryPaths,
      ...categoryIconsByPath.keys,
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
            leading: categoryFolderIcon(
                folder.iconId ?? defaultIconForCategoryPath(folder.path)),
            title: Row(
              children: [
                Expanded(
                  child: Text(folder.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                Tooltip(
                  message: 'Изменить папку',
                  child: IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => openCategoryEditorDialog(folder: folder),
                  ),
                ),
                Tooltip(
                  message: 'Создать подпапку',
                  child: IconButton(
                    icon: const Icon(Icons.create_new_folder_outlined),
                    onPressed: () => openCategoryEditorDialog(
                        parentPath: folder.path, folder: null),
                  ),
                ),
              ],
            ),
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
            leading: templateIconWidget(itemIconId(item, template)),
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

  Widget categoryFolderIcon(String iconId) {
    return SizedBox(
      width: 38,
      height: 38,
      child: Center(
        child: templateIconWidget(
          iconId.isEmpty ? 'folder' : iconId,
          size: 30,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Future<void> openCategoryEditorDialog({
    required CategoryTreeNode? folder,
    String parentPath = '',
  }) async {
    final wallet = spbWallet;
    if (wallet == null) {
      setState(() =>
          message = 'Откройте или создайте .swl базу перед изменением папок.');
      return;
    }
    final editing = folder != null;
    final nameController = TextEditingController(text: folder?.name ?? '');
    var iconId = folder?.iconId ?? defaultIconForCategoryPath(parentPath);
    final saved = await showDialog<({String name, String iconId})>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(editing ? 'Изменить папку' : 'Создать папку'),
          content: SizedBox(
            width: min(MediaQuery.of(context).size.width - 48, 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Название папки',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) {
                    final name = nameController.text.trim();
                    if (name.isNotEmpty && !name.contains('/')) {
                      Navigator.pop(context, (name: name, iconId: iconId));
                    }
                  },
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: templateIconWidget(iconId),
                    label: const Text('Пиктограмма папки'),
                    onPressed: () async {
                      final picked =
                          await showIconPickerDialog(context, iconId);
                      if (picked != null) {
                        setDialogState(() => iconId = picked);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            if (editing)
              TextButton.icon(
                onPressed: () => Navigator.pop(
                    context, (name: '__delete__', iconId: iconId)),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Удалить'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isEmpty || name.contains('/')) return;
                Navigator.pop(context, (name: name, iconId: iconId));
              },
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      nameController.dispose();
    });
    if (saved == null) return;
    if (editing && saved.name == '__delete__') {
      await Future<void>.delayed(Duration.zero);
      if (!mounted) return;
      final confirmed = await confirmDeleteCategory(folder);
      if (confirmed != true || !mounted) return;
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      try {
        wallet.deleteCategory(folder.path);
        await writeBackSpbWallet();
        final snapshot = wallet.loadSnapshot();
        setState(() {
          applySpbSnapshot(snapshot);
          if (selectedItemId != null &&
              !items.any((entry) => entry.id == selectedItemId)) {
            selectedItemId = null;
          }
          message = null;
        });
      } catch (error) {
        setState(() => message = 'Не удалось удалить папку: $error');
      }
      return;
    }
    final fullPath = [
      if (!editing && parentPath.trim().isNotEmpty) parentPath.trim(),
      saved.name,
    ].join(' / ');
    try {
      final spbIconId = spbIconIdForUi(saved.iconId, 'folder') ??
          syntheticSpbIconIdForUi(saved.iconId);
      if (editing) {
        wallet.renameCategory(folder.path, saved.name, spbIconId);
      } else {
        wallet.createCategory(fullPath, spbIconId);
      }
      await writeBackSpbWallet();
      final snapshot = wallet.loadSnapshot();
      setState(() {
        applySpbSnapshot(snapshot);
        message = null;
      });
    } catch (error) {
      setState(() => message = 'Не удалось сохранить папку: $error');
    }
  }

  Future<bool?> confirmDeleteCategory(CategoryTreeNode folder) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить папку?'),
        content: Text(
          'Папка "${folder.name}", ее подпапки и все карточки внутри будут удалены.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
  }

  Widget emptyCardDetail() {
    return const Card(
      elevation: 0,
      child: Center(child: Text('Выберите карточку в дереве слева')),
    );
  }

  Widget itemDetail(SecretItem item) {
    return itemCard(item, onDelete: deleteItemWithConfirmation);
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
                  leading: templateIconWidget(itemIconId(item, template)),
                  title: Text(item.title,
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  onTap: () => openCardPreviewDialog(item),
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
                  spbColor: entry.spbColor,
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
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, dialogSetState) {
          final currentItem = items.firstWhere(
            (entry) => entry.id == item.id,
            orElse: () => item,
          );
          return Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: min(MediaQuery.of(context).size.width - 24, 520),
                maxHeight: MediaQuery.of(context).size.height - 40,
              ),
              child: itemCard(
                currentItem,
                onClose: () => Navigator.pop(dialogContext),
                showFooterActions: true,
                showNotesAction: false,
                attachmentsReadOnly: true,
                onEdit: (editedItem) async {
                  final updated = await openItemDialog(item: editedItem);
                  if (updated == null || !mounted) return;
                  dialogSetState(() {});
                },
                onDelete: (deletedItem) async {
                  final deleted = await deleteItemWithConfirmation(deletedItem);
                  if (deleted && dialogContext.mounted) {
                    Navigator.pop(dialogContext);
                  }
                  return deleted;
                },
                onStateChange: (action) {
                  setState(action);
                  dialogSetState(() {});
                },
              ),
            ),
          );
        },
      ),
    );
  }

  void updateItemCardState(
    VoidCallback action,
    void Function(VoidCallback action)? onStateChange,
  ) {
    if (onStateChange == null) {
      setState(action);
    } else {
      onStateChange(action);
    }
  }

  Future<void> saveNoteFromDialog(
    SecretItem item,
    String fieldId,
    String saved,
  ) async {
    if (!mounted) return;
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
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
        spbColor: item.spbColor,
      ),
    );
  }

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
    await saveNoteFromDialog(item, fieldId, saved);
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
            leading: templateIconWidget(itemIconId(item, template), size: 24),
            title: Text(item.title),
            subtitle: Text('${template.name} · открытий: ${item.hitCount}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => openCardPreviewDialog(item),
          ),
        );
      },
    );
  }

  Widget itemCard(
    SecretItem item, {
    VoidCallback? onClose,
    bool showFooterActions = true,
    bool showNotesAction = false,
    bool attachmentsReadOnly = true,
    Future<void> Function(SecretItem item)? onEdit,
    Future<bool> Function(SecretItem item)? onDelete,
    void Function(VoidCallback action)? onStateChange,
  }) {
    final template = templateFor(item.templateId);
    final color = itemDisplayColor(item, template);
    final noteCount = noteText(item).trim().isEmpty ? 0 : 1;
    final attachmentCount =
        item.attachments.where((attachment) => !attachment.deleted).length;
    final backgroundImage = backgroundImageFor(item);
    return Card(
      color: backgroundImage == null ? color.bg : Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(
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
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 72),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    templateIconWidget(itemIconId(item, template), size: 28),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: color.fg)),
                          Text(template.name,
                              style: TextStyle(
                                  color: color.fg.withValues(alpha: 0.72))),
                        ],
                      ),
                    ),
                    if (onClose != null) ...[
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        tooltip: 'Закрыть',
                        icon: const Icon(Icons.close),
                        onPressed: onClose,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: template.fields
                        .where(
                            (field) => (item.values[field.id] ?? '').isNotEmpty)
                        .map((field) {
                      final revealKey = '${item.id}:${field.id}';
                      final isRevealed = revealed.contains(revealKey);
                      final value = item.values[field.id]!;
                      final secret = fieldDefinitionIsSecret(field);
                      return FieldValueRow(
                        label: field.label,
                        value: secret && !isRevealed ? '••••••••' : value,
                        copyValue: value,
                        foreground: color.fg,
                        secret: secret,
                        revealed: isRevealed,
                        onToggle: secret
                            ? () => updateItemCardState(() {
                                  isRevealed
                                      ? revealed.remove(revealKey)
                                      : revealed.add(revealKey);
                                }, onStateChange)
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
                if (showFooterActions)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (showNotesAction)
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
                        onPressed: () => attachmentsReadOnly
                            ? openAttachmentsPreviewDialog(item)
                            : openAttachmentsDialog(item),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          if (onDelete != null)
            Positioned(
              left: 12,
              bottom: 12,
              child: IconButton.filledTonal(
                tooltip: 'Удалить карточку',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => onDelete(item),
              ),
            ),
          Positioned(
            right: 12,
            bottom: 12,
            child: IconButton.filled(
              tooltip: 'Редактировать',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () async {
                if (onEdit == null) {
                  await openItemDialog(item: item);
                } else {
                  await onEdit(item);
                }
              },
            ),
          ),
        ],
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
    return noteFieldIdForTemplate(templateFor(item.templateId));
  }

  String noteText(SecretItem item) => item.values[noteFieldIdFor(item)] ?? '';

  Future<void> openAttachmentsDialog(SecretItem item) async {
    await openItemDialog(item: item);
  }

  Future<bool> deleteItemWithConfirmation(SecretItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить карточку?'),
        content: Text('Карточка "${item.title}" будет удалена из базы.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;
    final wallet = spbWallet;
    if (wallet == null) {
      setState(() => message =
          'Откройте или создайте .swl базу перед удалением карточек.');
      return false;
    }
    try {
      wallet.deleteCard(item.id);
      await writeBackSpbWallet();
      final snapshot = wallet.loadSnapshot();
      setState(() {
        applySpbSnapshot(snapshot);
        if (selectedItemId == item.id) selectedItemId = null;
        message = null;
      });
      return true;
    } catch (error) {
      setState(() => message = 'Не удалось удалить карточку: $error');
      return false;
    }
  }

  Future<void> openAttachmentsPreviewDialog(SecretItem item) async {
    final visibleAttachments =
        item.attachments.where((attachment) => !attachment.deleted).toList();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Вложения: ${item.title}'),
        content: SizedBox(
          width: min(MediaQuery.of(context).size.width - 48, 560),
          child: visibleAttachments.isEmpty
              ? const Text('Вложений нет')
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: visibleAttachments.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final attachment = visibleAttachments[index];
                    final hasError = attachment.decodeError != null;
                    return ListTile(
                      leading: attachmentPreview(attachment, hasError),
                      title: Text(attachment.fileName),
                      subtitle: Text(
                        hasError
                            ? 'Ошибка чтения: ${attachment.decodeError}'
                            : attachment.size >= 0
                                ? '${attachment.size} байт'
                                : 'Размер неизвестен',
                      ),
                      onTap: hasError
                          ? null
                          : () => viewReadOnlyAttachment(attachment),
                      trailing: hasError
                          ? null
                          : IconButton(
                              tooltip: 'Сохранить вложение',
                              icon: const Icon(Icons.download_outlined),
                              onPressed: () =>
                                  exportReadOnlyAttachment(attachment),
                            ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  Widget attachmentPreview(SecretAttachment attachment, bool hasError) {
    if (hasError) {
      return const SizedBox(
        width: 56,
        height: 56,
        child: Icon(Icons.error_outline),
      );
    }
    if (isImageAttachment(attachment.fileName) && attachment.id.isNotEmpty) {
      return FutureBuilder<Uint8List>(
        future: readAttachmentData(attachment),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const SizedBox(
              width: 56,
              height: 56,
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          return ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.memory(
              snapshot.data!,
              width: 56,
              height: 56,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox(
                width: 56,
                height: 56,
                child: Icon(Icons.broken_image_outlined),
              ),
            ),
          );
        },
      );
    }
    return SizedBox(
      width: 56,
      height: 56,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Theme.of(context).colorScheme.outline),
        ),
        child: Icon(
          isPdfAttachment(attachment.fileName)
              ? Icons.picture_as_pdf_outlined
              : Icons.insert_drive_file_outlined,
        ),
      ),
    );
  }

  Future<Uint8List> readAttachmentData(SecretAttachment attachment) async {
    final wallet = spbWallet;
    if (wallet == null || attachment.id.isEmpty) return Uint8List(0);
    return Uint8List.fromList(wallet.readAttachmentBytes(attachment.id));
  }

  bool isImageAttachment(String fileName) {
    final lower = fileName.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.bmp');
  }

  bool isPdfAttachment(String fileName) =>
      fileName.toLowerCase().endsWith('.pdf');

  Future<void> viewReadOnlyAttachment(SecretAttachment attachment) async {
    try {
      final bytes = await readAttachmentData(attachment);
      if (bytes.isEmpty) return;
      if (isImageAttachment(attachment.fileName)) {
        await showImageAttachmentDialog(attachment.fileName, bytes);
      } else {
        await openAttachmentExternally(attachment.fileName, bytes);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось открыть вложение: $error')),
      );
    }
  }

  Future<void> showImageAttachmentDialog(
      String fileName, Uint8List bytes) async {
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: min(MediaQuery.of(context).size.width - 32, 900),
            maxHeight: MediaQuery.of(context).size.height - 32,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(fileName,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: IconButton(
                  tooltip: 'Закрыть',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              Flexible(
                child: InteractiveViewer(
                  child: Image.memory(bytes, fit: BoxFit.contain),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> openAttachmentExternally(
      String fileName, Uint8List bytes) async {
    final directory = await getTemporaryDirectory();
    final safeName = fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final file = File('${directory.path}/actitpass_$safeName');
    await file.writeAsBytes(bytes, flush: true);
    final mimeType = isPdfAttachment(fileName)
        ? 'application/pdf'
        : isImageAttachment(fileName)
            ? 'image/*'
            : 'application/octet-stream';
    if (Platform.isAndroid) {
      await spbWalletChannel.invokeMethod<bool>('openFile', {
        'path': file.path,
        'mimeType': mimeType,
      });
      return;
    }
    if (Platform.isWindows) {
      await Process.start('cmd', ['/c', 'start', '', file.path],
          runInShell: true);
    } else if (Platform.isMacOS) {
      await Process.start('open', [file.path]);
    } else {
      await Process.start('xdg-open', [file.path]);
    }
  }

  Future<void> exportReadOnlyAttachment(SecretAttachment attachment) async {
    final wallet = spbWallet;
    if (wallet == null || attachment.id.isEmpty) return;
    try {
      final bytes =
          Uint8List.fromList(wallet.readAttachmentBytes(attachment.id));
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Сохранить вложение',
        fileName: attachment.fileName,
        bytes: bytes,
      );
      if (path != null && !Platform.isAndroid && !Platform.isIOS) {
        final file = File(path);
        if (!file.existsSync() || file.lengthSync() != bytes.length) {
          await file.writeAsBytes(bytes, flush: true);
        }
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось сохранить вложение: $error')),
      );
    }
  }

  Widget buildTemplatesView() {
    final query = templateSearchQuery.trim().toLowerCase();
    final visibleTemplates = templates.where((template) {
      if (query.isEmpty) return true;
      final haystack = [
        template.name,
        ...template.fields.map((field) => field.label),
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList();
    return ListView(
      children: [
        TextField(
          decoration: const InputDecoration(
            labelText: 'Поиск по шаблонам',
            prefixIcon: Icon(Icons.search),
            border: OutlineInputBorder(),
          ),
          onChanged: (value) => setState(() => templateSearchQuery = value),
        ),
        const SizedBox(height: 12),
        if (visibleTemplates.isEmpty)
          const Center(child: Text('Шаблоны не найдены'))
        else
          ...visibleTemplates.map((template) {
            final color = colorById('neutral');
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                elevation: 0,
                child: ListTile(
                  leading: CircleAvatar(
                      backgroundColor: color.bg,
                      foregroundColor: color.fg,
                      child:
                          templateIconWidget(template.iconId, color: color.fg)),
                  title: Text(template.name),
                  subtitle: Text(
                    template.fields
                        .map((field) =>
                            '${field.label}${fieldDefinitionIsSecret(field) ? ' (скрыто)' : ''}')
                        .join(', '),
                  ),
                  trailing: Wrap(
                    spacing: 4,
                    children: [
                      if (template.builtIn)
                        const Chip(label: Text('Встроенный')),
                      IconButton(
                        tooltip: 'Скопировать в новый шаблон',
                        icon: const Icon(Icons.copy),
                        onPressed: () => copyTemplate(template),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
      ],
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
            secret: fieldDefinitionIsSecret(field),
          ),
      ],
    );
    await openTemplateDialog(draft: copy);
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
            subtitle: Text(spbWalletUserPath() ?? 'локальный .swl файл'),
          ),
        ),
      ],
    );
  }

  CardTemplate templateFor(String id) => templates.firstWhere(
        (template) => template.id == id,
        orElse: () => templates.first,
      );

  SecretItem? itemById(String id) {
    for (final item in items) {
      if (item.id == id) return item;
    }
    return null;
  }

  Future<SecretItem?> openItemDialog({SecretItem? item}) async {
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
    if (saved == null) return null;
    final savedId = await persistItem(saved);
    if (savedId == null) return null;
    return itemById(savedId) ?? saved;
  }

  Future<String?> persistItem(SecretItem saved) async {
    if (spbWallet != null) {
      return saveSpbItem(saved);
    }
    setState(() => message =
        'Откройте или создайте .swl базу перед сохранением карточек.');
    return null;
  }

  Future<String?> saveSpbItem(SecretItem saved) async {
    final wallet = spbWallet;
    if (wallet == null) return null;
    final cardId = isSpbHexId(saved.id) ? saved.id : SpbWalletDatabase.makeId();
    final template = templateFor(saved.templateId);
    final descriptionFieldId = noteFieldIdForTemplate(template);
    try {
      wallet.saveCard(
        SpbWalletCardDraft(
          id: cardId,
          title: saved.title,
          description: descriptionFieldId == spbDescriptionFieldId
              ? saved.values[spbDescriptionFieldId] ?? ''
              : '',
          categoryPath: saved.category,
          templateId: saved.templateId,
          fieldValues: {
            for (final entry in saved.values.entries)
              if (entry.key != spbDescriptionFieldId) entry.key: entry.value,
          },
          cardColor: saved.spbColor ?? paletteColorToSpb(saved.colorId),
          iconId: spbIconIdForUi(
            itemIconId(saved, template),
            template.iconId,
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
        applySpbSnapshot(snapshot);
        selectedItemId = cardId;
        message = null;
      });
      return cardId;
    } catch (error) {
      setState(() => message = 'Не удалось сохранить .swl базу: $error');
      return null;
    }
  }

  Future<void> openTemplateDialog(
      {CardTemplate? template, CardTemplate? draft}) async {
    if (template != null && draft == null) {
      setState(() => message =
          'Существующие шаблоны доступны только для просмотра. Создайте новый шаблон или копию.');
      return;
    }
    final saved = await showDialog<CardTemplate>(
      context: context,
      builder: (context) => TemplateEditorDialog(initial: draft),
    );
    if (saved == null) return;
    if (spbWallet != null) {
      final prepared = prepareSpbTemplate(saved, true);
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
          applySpbSnapshot(snapshot);
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
          .where((field) => field.id != spbDescriptionFieldId)
          .map((field) => FieldDefinition(
                id: spbTemplateFieldId(field.id, isNew),
                label: field.label,
                type: field.type,
                required: field.required,
                secret: fieldTypeIsSecret(field.type),
              ))
          .toList(),
    );
  }

  String spbTemplateFieldId(String fieldId, bool templateIsNew) {
    if (templateIsNew || !isSpbHexId(fieldId)) {
      return SpbWalletDatabase.makeId();
    }
    return fieldId;
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
    this.onChanged,
    this.onSubmitted,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final bool visible;
  final VoidCallback onToggle;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: !visible,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
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

class FieldValueRow extends StatefulWidget {
  const FieldValueRow({
    required this.label,
    required this.value,
    required this.copyValue,
    required this.foreground,
    this.secret = false,
    this.revealed = false,
    this.onToggle,
    super.key,
  });

  final String label;
  final String value;
  final String copyValue;
  final Color foreground;
  final bool secret;
  final bool revealed;
  final VoidCallback? onToggle;

  @override
  State<FieldValueRow> createState() => _FieldValueRowState();
}

class _FieldValueRowState extends State<FieldValueRow> {
  Timer? copiedTimer;
  bool copied = false;

  @override
  void dispose() {
    copiedTimer?.cancel();
    super.dispose();
  }

  Future<void> copyValue() async {
    await copyCardFieldValue(widget.copyValue);
    if (!mounted) return;
    copiedTimer?.cancel();
    setState(() => copied = true);
    copiedTimer = Timer(const Duration(seconds: 10), () {
      if (mounted) setState(() => copied = false);
    });
  }

  Future<void> showCopyMenu(LongPressStartDetails details) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final picked = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(
          details.globalPosition.dx,
          details.globalPosition.dy,
          1,
          1,
        ),
        Offset.zero & overlay.size,
      ),
      items: const [
        PopupMenuItem(
          value: 'copy',
          child: ListTile(
            dense: true,
            leading: Icon(Icons.copy),
            title: Text('Копировать'),
          ),
        ),
      ],
    );
    if (picked == 'copy') await copyValue();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: copyValue,
        onLongPressStart: showCopyMenu,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.44),
            borderRadius: BorderRadius.circular(8),
            border:
                Border.all(color: widget.foreground.withValues(alpha: 0.10)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: widget.foreground.withValues(alpha: 0.62),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 180),
                      child: SingleChildScrollView(
                        primary: false,
                        child: Text(
                          widget.value,
                          style: TextStyle(
                              color: widget.foreground,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: copied ? 'Скопировано' : 'Копировать',
                icon: Icon(copied ? Icons.check : Icons.copy),
                onPressed: copyValue,
              ),
              if (widget.secret && widget.onToggle != null)
                IconButton(
                  tooltip: widget.revealed ? 'Скрыть' : 'Показать',
                  icon: Icon(widget.revealed
                      ? Icons.visibility_off
                      : Icons.visibility),
                  onPressed: widget.onToggle,
                ),
            ],
          ),
        ),
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
        CircleAvatar(child: Icon(templateIconGlyph(icon.id), size: 20)),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () async {
              final picked = await showIconPickerDialog(context, iconId);
              if (picked != null) onChanged(picked);
            },
            icon: Icon(templateIconGlyph(icon.id), size: 18),
            label: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
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
                    child: Icon(templateIconGlyph(icon.id), size: 24),
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
  int? spbColor;
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
    spbColor = widget.initial?.spbColor;
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
    final dialogWidth = max(
      260.0,
      min(MediaQuery.of(context).size.width - 96, 680.0),
    );
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: Text(
          widget.initial == null ? 'Новая карточка' : 'Редактировать карточку'),
      content: SizedBox(
        width: dialogWidth,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: templateId,
                decoration: const InputDecoration(
                    labelText: 'Шаблон', border: OutlineInputBorder()),
                items: widget.templates
                    .map((template) => DropdownMenuItem(
                        value: template.id,
                        child: templateMenuIconLabel(
                            template.iconId, template.name)))
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
                  onChanged: (value) => setState(() {
                        colorId = value;
                        // Пользователь явно выбрал новый цвет - заменяем
                        // точный RGB из SPB Wallet на цвет выбранного пресета.
                        spbColor = paletteColorToSpb(value);
                      })),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.start,
                children: [
                  OutlinedButton.icon(
                    onPressed: pickBackgroundImage,
                    icon: const Icon(Icons.image_outlined),
                    label: Text(backgroundImageBase64 == null
                        ? 'Добавить фон'
                        : 'Заменить фон'),
                  ),
                  if (backgroundImageBase64 != null)
                    IconButton(
                      tooltip: 'Убрать фон',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () =>
                          setState(() => backgroundImageBase64 = null),
                    ),
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
                    obscureText: fieldDefinitionIsSecret(field) && !visible,
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
                spbColor: spbColor,
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
          isExpanded: true,
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
    if (fieldDefinitionIsSecret(field)) {
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
        label = TextEditingController(text: field.label);

  final String id;
  final TextEditingController label;
  String type;
  bool get secret => fieldTypeIsSecret(type);

  void dispose() => label.dispose();

  FieldDefinition toField() => FieldDefinition(
        id: id,
        label: label.text.trim().isEmpty ? 'Поле' : label.text.trim(),
        type: type,
        secret: secret,
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
    final sourceFields = widget.initial?.fields ??
        const [
          FieldDefinition(id: 'username', label: 'Логин', type: 'username'),
          FieldDefinition(
              id: 'password', label: 'Пароль', type: 'password', secret: true),
          FieldDefinition(
              id: 'notes', label: 'Заметки', type: 'multiline_note'),
        ];
    fields = [
      for (final field
          in sourceFields.where((field) => field.id != spbDescriptionFieldId))
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
              label: Icon(templateIconGlyph(icon.id), size: 18),
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
