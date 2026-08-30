import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as image;
import 'package:path_provider/path_provider.dart';

import 'data/spb_wallet_repository.dart';
import 'controllers/entity_index.dart';
import 'controllers/vault_session_controller.dart';
import 'core/id_generator.dart';
import 'features/cards/card_models.dart';
import 'features/cards/field_projection.dart';
import 'features/cards/field_types.dart';
import 'features/categories/category_path_index.dart';
import 'features/navigation/vault_navigation_controller.dart';
import 'features/search/wallet_search_controller.dart';
import 'features/templates/swt_template_codec.dart';
import 'features/templates/template_defaults.dart';
import 'features/templates/template_order.dart';
import 'services/wallet_rekey_service.dart';
import 'services/platform/secure_clipboard_service.dart';
import 'services/vault_operation_coordinator.dart';
import 'services/vault_persistence.dart';
import 'spb_wallet/wallet_image_codec.dart';
import 'widgets/card_surface.dart';

export 'features/cards/card_models.dart';
export 'features/cards/field_types.dart';
export 'features/templates/swt_template_codec.dart';

part 'features/cards/card_editor_dialog.dart';
part 'features/cards/card_field_values_list.dart';
part 'features/cards/card_operations.dart';
part 'features/cards/card_preview_dialog.dart';
part 'features/categories/category_editor_dialog.dart';
part 'features/mapping/spb_ui_mapping.dart';
part 'features/templates/template_dialogs.dart';
part 'features/templates/template_operations.dart';
part 'features/workspace/workspace_actions_panel.dart';
part 'features/workspace/workspace_center_panel.dart';
part 'features/workspace/workspace_navigation_panel.dart';
part 'services/vault_file_session_operations.dart';
part 'services/local_recovery_operations.dart';
part 'services/common_resources.dart';
part 'controllers/password_lock_operations.dart';
part 'widgets/action_controls.dart';
part 'widgets/icon_picker_controls.dart';
part 'widgets/password_navigation_controls.dart';

void main(List<String> arguments) {
  final initialVaultPath = arguments.cast<String?>().firstWhere(
        (argument) =>
            argument != null &&
            argument.toLowerCase().endsWith('.swl') &&
            File(argument).existsSync(),
        orElse: () => null,
      );
  runApp(WalletApsApp(initialVaultPath: initialVaultPath));
}

class WalletApsApp extends StatelessWidget {
  const WalletApsApp({this.initialVaultPath, super.key});

  final String? initialVaultPath;

  @override
  Widget build(BuildContext context) {
    final baseTheme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xff2d6f73),
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: const Color(0xfff5f7f8),
      visualDensity: VisualDensity.standard,
      scrollbarTheme: const ScrollbarThemeData(
        thickness: WidgetStatePropertyAll<double>(13.6),
      ),
    );
    TextStyle enlarged(TextStyle? style, double defaultSize) =>
        (style ?? const TextStyle()).copyWith(
          fontSize: (style?.fontSize ?? defaultSize) + 2,
          fontWeight: FontWeight.normal,
        );
    final baseText = baseTheme.textTheme;
    final enlargedText = TextTheme(
      displayLarge: enlarged(baseText.displayLarge, 57),
      displayMedium: enlarged(baseText.displayMedium, 45),
      displaySmall: enlarged(baseText.displaySmall, 36),
      headlineLarge: enlarged(baseText.headlineLarge, 32),
      headlineMedium: enlarged(baseText.headlineMedium, 28),
      headlineSmall: enlarged(baseText.headlineSmall, 24),
      titleLarge: enlarged(baseText.titleLarge, 22),
      titleMedium: enlarged(baseText.titleMedium, 16),
      titleSmall: enlarged(baseText.titleSmall, 14),
      bodyLarge: enlarged(baseText.bodyLarge, 16),
      bodyMedium: enlarged(baseText.bodyMedium, 14),
      bodySmall: enlarged(baseText.bodySmall, 12),
      labelLarge: enlarged(baseText.labelLarge, 14),
      labelMedium: enlarged(baseText.labelMedium, 12),
      labelSmall: enlarged(baseText.labelSmall, 11),
    );
    return MaterialApp(
      scaffoldMessengerKey: rootScaffoldMessengerKey,
      title: 'Wallet APS',
      debugShowCheckedModeBanner: false,
      builder: (context, child) => child ?? const SizedBox.shrink(),
      theme: baseTheme.copyWith(textTheme: enlargedText),
      home: VaultShell(initialVaultPath: initialVaultPath),
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

class EnsureVisibleWhenFocused extends StatelessWidget {
  const EnsureVisibleWhenFocused({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (focused) {
        if (!focused) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          Scrollable.ensureVisible(
            context,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            alignment: 0.3,
          );
        });
      },
      child: child,
    );
  }
}

class TemplateIcon {
  const TemplateIcon(this.id, this.label, this.symbol);

  final String id;
  final String label;
  final String symbol;
}

typedef CategoryTreeNode = VaultTreeNode<SecretItem>;
typedef SpbVisibleTreeEntry = VaultVisibleTreeEntry<SecretItem>;

enum SessionTrashKind { card, folder, template }

class SessionTrashEntry {
  const SessionTrashEntry({
    required this.kind,
    required this.id,
    required this.title,
    required this.iconId,
  });

  final SessionTrashKind kind;
  final String id;
  final String title;
  final String iconId;
}

class SessionUndoEntry {
  const SessionUndoEntry({
    required this.label,
    required this.iconId,
    required this.databaseSnapshot,
    required this.trash,
    required this.trashCardIds,
    required this.trashFolderPaths,
    required this.trashTemplateIds,
  });

  final String label;
  final String iconId;
  final SpbWalletUndoSnapshot databaseSnapshot;
  final List<SessionTrashEntry> trash;
  final Set<String> trashCardIds;
  final Set<String> trashFolderPaths;
  final Set<String> trashTemplateIds;
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
        fieldOrder: item.fieldOrder,
        hiddenFieldIds: item.hiddenFieldIds,
        modifiedAt: item.modifiedAt,
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
            .map(
              (field) => SpbWalletTemplateFieldRecord(
                id: field.id,
                name: field.label,
                templateId: template.id,
                fieldTypeId: spbFieldTypeId(field),
              ),
            )
            .toList(),
      ),
    );
    await load();
  }

  @override
  Future<void> saveAttachment(
    String itemId,
    SecretAttachment attachment,
  ) async {
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

const templateColorPalette = [
  PaletteColor(
    'template_gray',
    'Бледно-серый',
    Color(0xffe8e8e8),
    Color(0xff242424),
  ),
  PaletteColor(
    'template_red',
    'Бледно-красный',
    Color(0xfff8d7da),
    Color(0xff54292d),
  ),
  PaletteColor(
    'template_coral',
    'Бледно-коралловый',
    Color(0xfff9ddd2),
    Color(0xff583329),
  ),
  PaletteColor(
    'template_orange',
    'Бледно-оранжевый',
    Color(0xfffbe5c8),
    Color(0xff583c20),
  ),
  PaletteColor(
    'template_yellow',
    'Бледно-жёлтый',
    Color(0xfffbf3c4),
    Color(0xff51491e),
  ),
  PaletteColor(
    'template_lime',
    'Бледно-салатовый',
    Color(0xffedf5c8),
    Color(0xff414b22),
  ),
  PaletteColor(
    'template_green',
    'Бледно-зелёный',
    Color(0xffdaf1d8),
    Color(0xff294b2a),
  ),
  PaletteColor(
    'template_mint',
    'Бледно-мятный',
    Color(0xffd5f1e3),
    Color(0xff24493a),
  ),
  PaletteColor(
    'template_cyan',
    'Бледно-бирюзовый',
    Color(0xffd5f2f2),
    Color(0xff21494b),
  ),
  PaletteColor(
    'template_sky',
    'Бледно-голубой',
    Color(0xffd8ecfa),
    Color(0xff24445a),
  ),
  PaletteColor(
    'template_blue',
    'Бледно-синий',
    Color(0xffdce4fa),
    Color(0xff293b61),
  ),
  PaletteColor(
    'template_indigo',
    'Бледно-индиго',
    Color(0xffe2dff7),
    Color(0xff39345e),
  ),
  PaletteColor(
    'template_violet',
    'Бледно-фиолетовый',
    Color(0xffeaddf6),
    Color(0xff49335c),
  ),
  PaletteColor(
    'template_pink',
    'Бледно-розовый',
    Color(0xfff5ddf0),
    Color(0xff58344f),
  ),
  PaletteColor(
    'template_rose',
    'Бледно-розово-серый',
    Color(0xfff7e1e8),
    Color(0xff583943),
  ),
  PaletteColor('template_white', 'Белый', Color(0xffffffff), Color(0xff222222)),
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
            secret: true,
          ),
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
            required: true,
          ),
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
            required: true,
          ),
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
            id: 'full_name',
            label: 'ФИО',
            type: 'text',
            required: true,
          ),
          FieldDefinition(
            id: 'document_number',
            label: 'Номер документа',
            type: 'custom_secret',
            required: true,
          ),
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
            required: true,
          ),
          FieldDefinition(
            id: 'password',
            label: 'Пароль или фраза ключа',
            type: 'password',
            secret: true,
          ),
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
            id: 'product',
            label: 'Продукт',
            type: 'text',
            required: true,
          ),
          FieldDefinition(
            id: 'license_key',
            label: 'Лицензионный ключ',
            type: 'custom_secret',
            required: true,
          ),
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
            id: 'ssid',
            label: 'Название сети',
            type: 'text',
            required: true,
          ),
          FieldDefinition(
            id: 'password',
            label: 'Пароль Wi-Fi',
            type: 'password',
            required: true,
            secret: true,
          ),
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
            required: true,
          ),
          FieldDefinition(
            id: 'login',
            label: 'Логин интернет-банка',
            type: 'username',
          ),
          FieldDefinition(
            id: 'password',
            label: 'Пароль интернет-банка',
            type: 'password',
            secret: true,
          ),
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
            id: 'email',
            label: 'Email',
            type: 'email',
            required: true,
          ),
          FieldDefinition(
            id: 'password',
            label: 'Пароль',
            type: 'password',
            required: true,
            secret: true,
          ),
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
            id: 'service',
            label: 'Сервис',
            type: 'text',
            required: true,
          ),
          FieldDefinition(id: 'url', label: 'Панель', type: 'url'),
          FieldDefinition(
            id: 'token',
            label: 'Токен',
            type: 'custom_secret',
            required: true,
          ),
          FieldDefinition(
            id: 'notes',
            label: 'Права и ограничения',
            type: 'multiline_note',
          ),
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
            required: true,
          ),
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
            id: 'service',
            label: 'Сервис',
            type: 'text',
            required: true,
          ),
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
            id: 'company',
            label: 'Компания',
            type: 'text',
            required: true,
          ),
          FieldDefinition(
            id: 'policy',
            label: 'Номер полиса',
            type: 'custom_secret',
            required: true,
          ),
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

PaletteColor colorById(String id) {
  for (final color in [...palette, ...templateColorPalette]) {
    if (color.id == id) return color;
  }
  return palette.first;
}

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

String spbTemplateColorToPaletteId(int color) {
  final normalized = color & 0x00ffffff;
  for (final candidate in templateColorPalette) {
    if ((candidate.bg.toARGB32() & 0x00ffffff) == normalized) {
      return candidate.id;
    }
  }
  return spbColorToPaletteId(color);
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

Color templatePictogramColor(String colorId) {
  return pictogramColorForBackground(colorById(colorId).bg);
}

Color pictogramColorForBackground(Color background) {
  return Color.lerp(background, Colors.black, 0.20)!;
}

Color categoryPictogramColor(String? colorId) => pictogramColorForBackground(
      colorById(colorId == null || colorId.isEmpty ? 'template_gray' : colorId)
          .bg,
    );

Color itemPictogramColor(SecretItem item, CardTemplate template) =>
    pictogramColorForBackground(itemDisplayColor(item, template).bg);

Color templateDisplayBackground(CardTemplate template) =>
    template.spbColor == null
        ? colorById(template.colorId).bg
        : Color(0xff000000 | (template.spbColor! & 0x00ffffff));

Color templateDisplayPictogramColor(CardTemplate template) =>
    pictogramColorForBackground(templateDisplayBackground(template));

Widget templateIconWidget(String id, {double size = 20, Color? color}) {
  final embeddedBytes = spbEmbeddedIconPngs[id.toUpperCase()];
  if (embeddedBytes != null) {
    return Image.memory(
      embeddedBytes,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, __, ___) =>
          Icon(Icons.vpn_key_outlined, size: size, color: color),
    );
  }
  final originalAsset = spbPngIconAsset(id);
  if (originalAsset != null) {
    // Original SPB Wallet icons are 64x64. Do not scale them down to the
    // Material icon size requested by compact callers.
    return SizedBox(
      width: 64,
      height: 64,
      child: spbPackedImage(
        originalAsset,
        width: 64,
        height: 64,
        fit: BoxFit.none,
        filterQuality: FilterQuality.none,
        fallback: Icon(Icons.vpn_key_outlined, size: size, color: color),
      ),
    );
  }
  return Icon(templateIconGlyph(id), size: size, color: color);
}

String registerEmbeddedIcon(Uint8List bytes) {
  final id = SpbWalletDatabase.makeId();
  spbEmbeddedIconPngs[id.toUpperCase()] = bytes;
  return id;
}

Uint8List normalizeUserIconPng(image.Image source, {int size = 128}) {
  final scale = min(size / source.width, size / source.height);
  final width = max(1, (source.width * scale).round());
  final height = max(1, (source.height * scale).round());
  final resized = image.copyResize(
    source,
    width: width,
    height: height,
    interpolation: image.Interpolation.cubic,
  );
  final canvas = image.Image(width: size, height: size, numChannels: 4);
  final offsetX = (size - width) ~/ 2;
  final offsetY = (size - height) ~/ 2;
  final radius = max(1, (min(width, height) * 0.10).round());
  final cornerCenter = radius - 0.5;
  final radiusSquared = radius * radius;

  for (final pixel in resized) {
    final x = pixel.x;
    final y = pixel.y;
    final cornerX = x < radius
        ? cornerCenter
        : x >= width - radius
            ? width - radius - 0.5
            : null;
    final cornerY = y < radius
        ? cornerCenter
        : y >= height - radius
            ? height - radius - 0.5
            : null;
    final outsideRoundedCorner = cornerX != null &&
        cornerY != null &&
        ((x - cornerX) * (x - cornerX) + (y - cornerY) * (y - cornerY) >
            radiusSquared);
    canvas.setPixelRgba(
      offsetX + x,
      offsetY + y,
      pixel.r,
      pixel.g,
      pixel.b,
      outsideRoundedCorner ? 0 : pixel.a,
    );
  }
  return Uint8List.fromList(image.encodePng(canvas));
}

Future<({Uint8List bytes, String fileName})?> pickUserIconFile(
  BuildContext context,
) async {
  try {
    final picked = Platform.isAndroid
        ? await FilePicker.platform.pickFiles(
            type: FileType.image,
            withData: true,
            // Android converts gallery formats such as HEIC into an image
            // that the Dart decoder can reliably read.
            compressionQuality: 95,
          )
        : await FilePicker.platform.pickFiles(
            type: FileType.custom,
            allowedExtensions: const [
              'png',
              'ico',
              'jpg',
              'jpeg',
              'bmp',
              'gif',
              'webp',
            ],
            withData: true,
          );
    final file = picked?.files.single;
    if (file == null) return null;
    Uint8List? bytes = file.bytes;
    if ((bytes == null || bytes.isEmpty) && file.path != null) {
      bytes = await File(file.path!).readAsBytes();
    }
    if (bytes == null || bytes.isEmpty) {
      throw const FormatException('Выбранный файл пуст или недоступен.');
    }
    image.Image? decoded;
    try {
      decoded = image.IcoDecoder().decodeImageLargest(bytes);
    } catch (_) {
      // The selected file can be a regular bitmap rather than ICO.
    }
    decoded ??= image.decodeImage(bytes);
    if (decoded == null) {
      throw const FormatException('Формат изображения не поддерживается.');
    }
    final pngBytes = normalizeUserIconPng(decoded);
    final baseName = file.name.replaceFirst(RegExp(r'\.[^.]+$'), '');
    return (
      bytes: pngBytes,
      fileName: '${baseName.isEmpty ? 'icon' : baseName}.png',
    );
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось загрузить изображение: $error')),
      );
    }
    return null;
  }
}

String attachmentMimeType(String fileName) {
  final lower = fileName.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  if (lower.endsWith('.gif')) return 'image/gif';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.bmp')) return 'image/bmp';
  if (lower.endsWith('.pdf')) return 'application/pdf';
  if (lower.endsWith('.doc')) return 'application/msword';
  if (lower.endsWith('.docx')) {
    return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
  }
  if (lower.endsWith('.xls')) return 'application/vnd.ms-excel';
  if (lower.endsWith('.xlsx')) {
    return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
  }
  if (lower.endsWith('.odt')) {
    return 'application/vnd.oasis.opendocument.text';
  }
  if (lower.endsWith('.ods')) {
    return 'application/vnd.oasis.opendocument.spreadsheet';
  }
  if (lower.endsWith('.rtf')) return 'application/rtf';
  if (lower.endsWith('.txt') ||
      lower.endsWith('.log') ||
      lower.endsWith('.csv') ||
      lower.endsWith('.json') ||
      lower.endsWith('.xml') ||
      lower.endsWith('.md') ||
      lower.endsWith('.yaml') ||
      lower.endsWith('.yml')) {
    return 'text/plain';
  }
  if (lower.endsWith('.mp3')) return 'audio/mpeg';
  if (lower.endsWith('.wav')) return 'audio/wav';
  if (lower.endsWith('.ogg')) return 'audio/ogg';
  if (lower.endsWith('.m4a')) return 'audio/mp4';
  if (lower.endsWith('.mp4')) return 'video/mp4';
  if (lower.endsWith('.webm')) return 'video/webm';
  return 'application/octet-stream';
}

({String fileName, Uint8List bytes}) gallerySafeAttachmentExport(
  String originalFileName,
  Uint8List bytes, {
  bool? isAndroid,
}) {
  final lowerName = originalFileName.toLowerCase();
  final isGalleryImage = const <String>[
    '.png',
    '.jpg',
    '.jpeg',
    '.gif',
    '.webp',
    '.bmp',
    '.heic',
    '.heif',
    '.tif',
    '.tiff',
    '.avif',
    '.dng',
    '.svg',
  ].any(lowerName.endsWith);
  if (!(isAndroid ?? Platform.isAndroid) || !isGalleryImage) {
    return (fileName: originalFileName, bytes: bytes);
  }
  final safeOriginal = originalFileName
      .replaceAll(RegExp(r'[\\/:*?<>|]'), '_')
      .replaceAll(String.fromCharCode(34), '_')
      .trim();
  final archiveName = safeOriginal.isEmpty ? 'attachment' : safeOriginal;
  final baseName = archiveName.replaceFirst(RegExp(r'\.[^.]+$'), '');
  final archive = Archive()..addFile(ArchiveFile.bytes(archiveName, bytes));
  return (
    fileName: '${baseName.isEmpty ? 'attachment' : baseName}.apsattachment.zip',
    bytes: Uint8List.fromList(ZipEncoder().encode(archive)),
  );
}

Future<void> openAttachmentBytesWithSystem(
  String fileName,
  Uint8List bytes,
) async {
  final directory = await getTemporaryDirectory();
  final safeName = fileName
      .replaceAll(RegExp(r'[\\/:*?<>|]'), '_')
      .replaceAll(String.fromCharCode(34), '_');
  // FileProvider supplies the real MIME type. The service extension prevents
  // gallery applications from treating the private working copy as a photo.
  final temporaryName = Platform.isAndroid
      ? 'wallet_aps_${safeName.hashCode.toUnsigned(32)}.apsblob'
      : 'wallet_aps_$safeName';
  final file = File('${directory.path}${Platform.pathSeparator}$temporaryName');
  await file.writeAsBytes(bytes, flush: true);
  if (Platform.isAndroid) {
    final opened = await spbWalletChannel.invokeMethod<bool>('openFile', {
      'path': file.path,
      'mimeType': attachmentMimeType(fileName),
    });
    if (opened != true) {
      throw StateError('Android не смог открыть файл системным приложением.');
    }
    return;
  }
  if (Platform.isWindows) {
    await Process.start(
        'cmd',
        [
          '/c',
          'start',
          '',
          file.path,
        ],
        runInShell: true);
  } else if (Platform.isMacOS) {
    await Process.start('open', [file.path]);
  } else {
    await Process.start('xdg-open', [file.path]);
  }
}

Widget templateMenuIconLabel(
  String iconId,
  String text, {
  double iconScale = 1,
}) {
  final icon = templateIconWidget(iconId, size: 18);
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (iconScale == 1)
        icon
      else
        SizedBox(
          width: 32,
          height: 32,
          child: Center(
            child: Transform.scale(scale: iconScale, child: icon),
          ),
        ),
      const SizedBox(width: 8),
      Flexible(child: Text(text, overflow: TextOverflow.ellipsis)),
    ],
  );
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
  for (final codeUnit in 'wallet-aps-icon:$uiIconId'.codeUnits) {
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
  for (final asset in spb64PngIconAssets) {
    if (syntheticSpbIconIdForUi(asset) == normalized) return asset;
    final relative = asset.startsWith('spb://') ? asset.substring(6) : asset;
    // Releases up to v0.1.18 hashed the loose-file asset path. Recognize
    // those IDs after moving the images into the single packed asset.
    if (syntheticSpbIconIdForUi('assets/spb_icons_package/$relative') ==
            normalized ||
        syntheticSpbIconIdForUi(
              'assets/spb_wallet_libraries/icons/$relative',
            ) ==
            normalized) {
      return asset;
    }
  }
  return null;
}

const _spbOriginalIconAssetDirectory = 'spb://apk_icons/res/drawable-hdpi';

// Built-in Spb Wallet IconID values are stable identifiers, not row numbers.
// Keep the correspondence explicit: database order differs from icons_NNN.png.
const spbOriginalIconAssets = <String, String>{
  // Finance.
  'A74FE6691728757D': '$_spbOriginalIconAssetDirectory/icons_010.png', // Visa
  'E4186A7B247E2B1D': '$_spbOriginalIconAssetDirectory/icons_068.png', // Bank
  '4428DBE8E0FDBEF5':
      '$_spbOriginalIconAssetDirectory/icons_011.png', // MasterCard
  'BD097D2EE2FA614A': '$_spbOriginalIconAssetDirectory/icons_012.png', // Cirrus
  '6FCAF114B73422CF':
      '$_spbOriginalIconAssetDirectory/icons_013.png', // Diners Club
  '490FA51A66910C69':
      '$_spbOriginalIconAssetDirectory/icons_014.png', // American Express
  '556D5E8F02589023':
      '$_spbOriginalIconAssetDirectory/icons_025.png', // Traveller cheque
  '7291F51A432B6530':
      '$_spbOriginalIconAssetDirectory/icons_052.png', // Loan / mortgage
  '40F61F0CE55A0757':
      '$_spbOriginalIconAssetDirectory/icons_053.png', // Investments
  'D3AB05E94F9E4C18':
      '$_spbOriginalIconAssetDirectory/icons_026.png', // Calling card
  '52AB4DC040DF39EA':
      '$_spbOriginalIconAssetDirectory/icons_027.png', // Personal insurance
  'AD817751F169F5F9':
      '$_spbOriginalIconAssetDirectory/icons_024.png', // Insurance policy
  'CEBAB052995FF2BA':
      '$_spbOriginalIconAssetDirectory/icons_017.png', // Generic card
  '71076D75AD9AD080':
      '$_spbOriginalIconAssetDirectory/icons_015.png', // Discover
  '26DAEC5D7E4E6715':
      '$_spbOriginalIconAssetDirectory/icons_016.png', // Maestro
  // Personal records.
  '289B3CF7980A951E':
      '$_spbOriginalIconAssetDirectory/icons_041.png', // Automobile
  '20678C366BED420F':
      '$_spbOriginalIconAssetDirectory/icons_055.png', // Clothing sizes
  'E8950204C5B13337':
      '$_spbOriginalIconAssetDirectory/icons_051.png', // Glasses
  '9DEB9BC675EC569A':
      '$_spbOriginalIconAssetDirectory/icons_033.png', // Voter card
  'AC2FDDB9D988A96E':
      '$_spbOriginalIconAssetDirectory/icons_018.png', // Driver license
  'F7F133A9EDA8AD3E':
      '$_spbOriginalIconAssetDirectory/icons_019.png', // Passport
  '364C9DE41B5927E4':
      '$_spbOriginalIconAssetDirectory/icons_035.png', // Personal card
  'C0F3D5137928104F':
      '$_spbOriginalIconAssetDirectory/icons_020.png', // Social security
  'D8466DC42C598628':
      '$_spbOriginalIconAssetDirectory/icons_036.png', // Library card
  'F1DF61C4072919F4':
      '$_spbOriginalIconAssetDirectory/icons_037.png', // Membership
  '55B25AA977BBABA0':
      '$_spbOriginalIconAssetDirectory/icons_056.png', // Prescription
  '5DB82F9F9859FF2C':
      '$_spbOriginalIconAssetDirectory/icons_058.png', // Meal delivery
  '7650B2DDF2971084':
      '$_spbOriginalIconAssetDirectory/icons_057.png', // Restaurant
  'D0A03FA49259E894':
      '$_spbOriginalIconAssetDirectory/icons_065.png', // Combination lock
  '6ACC0F32AAB28ED8': '$_spbOriginalIconAssetDirectory/icons_050.png', // Event
  'CAACFBE92AAC7C7D':
      '$_spbOriginalIconAssetDirectory/icons_028.png', // Frequent flyer
  'AB540457E8E62887':
      '$_spbOriginalIconAssetDirectory/icons_029.png', // Garage door
  'E610927897C0F039': '$_spbOriginalIconAssetDirectory/icons_060.png', // Pet
  'EDE2A1A2E3B172D5':
      '$_spbOriginalIconAssetDirectory/icons_066.png', // Warranty
  '38A06822A088D80F':
      '$_spbOriginalIconAssetDirectory/icons_067.png', // Training
  'BC8395AF3885E099':
      '$_spbOriginalIconAssetDirectory/icons_030.png', // Password history
  '28A67DABE33DA42B':
      '$_spbOriginalIconAssetDirectory/icons_046.png', // Mobile phone
  // Contacts, Internet and computers.
  '14BD44DE9F2F4F99':
      '$_spbOriginalIconAssetDirectory/icons_034.png', // Contact
  'B8058FF4BA946340':
      '$_spbOriginalIconAssetDirectory/icons_045.png', // Home service
  'E5442EED85AD0572':
      '$_spbOriginalIconAssetDirectory/icons_063.png', // Emergency
  '62767D3E1BC8E2C8':
      '$_spbOriginalIconAssetDirectory/icons_061.png', // Note / file
  '867CA874B9508C95': '$_spbOriginalIconAssetDirectory/icons_021.png', // Email
  'A6E0F0CFDFAF6928':
      '$_spbOriginalIconAssetDirectory/icons_022.png', // Website
  '087CF65FC366A122':
      '$_spbOriginalIconAssetDirectory/icons_038.png', // Serial number
  'B7D8EDDF4E4F493E':
      '$_spbOriginalIconAssetDirectory/icons_023.png', // Software serial
  '27445EACFC5DD8D9':
      '$_spbOriginalIconAssetDirectory/icons_062.png', // Voice mail
  '31785C316B046C3F':
      '$_spbOriginalIconAssetDirectory/icons_039.png', // Internet settings
  '24760DEDF9C71546':
      '$_spbOriginalIconAssetDirectory/icons_047.png', // Network
  '508A24D5C6B90C54': '$_spbOriginalIconAssetDirectory/icons_031.png', // Server
  'BC51FC021F344286':
      '$_spbOriginalIconAssetDirectory/icons_040.png', // Hosting
  '243B78A1D8C7E32C':
      '$_spbOriginalIconAssetDirectory/icons_032.png', // Online shopping
  // Travel.
  '97973FA7389FFE1C':
      '$_spbOriginalIconAssetDirectory/icons_054.png', // Car rental
  '68E51FEE9B8D4E7C': '$_spbOriginalIconAssetDirectory/icons_044.png', // Flight
  '06D4F7F69F1E42E5': '$_spbOriginalIconAssetDirectory/icons_049.png', // Hotel
  'DAECE1D88696E125':
      '$_spbOriginalIconAssetDirectory/icons_064.png', // Ground transport
  '5DEF85654F9DC2CD': '$_spbOriginalIconAssetDirectory/icons_042.png', // ISIC
  'A06AD15403B46BAB': '$_spbOriginalIconAssetDirectory/icons_043.png', // ITIC
  '30E614ECB34BA668':
      '$_spbOriginalIconAssetDirectory/icons_048.png', // Travel visa
  // Default folders.
  '54320B4412A08007':
      '$_spbOriginalIconAssetDirectory/icons_003.png', // Credit cards
  'E864A803F91DA5C4':
      '$_spbOriginalIconAssetDirectory/icons_005.png', // Finance
  '4863F2D4E9D399F6':
      '$_spbOriginalIconAssetDirectory/icons_006.png', // Personal
  '96DAFC9A4C1F55F6': '$_spbOriginalIconAssetDirectory/icons_004.png', // Family
  '5D595FE47887E6C9': '$_spbOriginalIconAssetDirectory/icons_008.png', // Work
  '6E4AAD6B4F39E378':
      '$_spbOriginalIconAssetDirectory/icons_002.png', // Computers
  '0C1E037B56E9E59B':
      '$_spbOriginalIconAssetDirectory/icons_001.png', // Leisure
};

const spbDefaultOriginalIconAsset =
    '$_spbOriginalIconAssetDirectory/icons_001.png';
const spbPasswordTemplateIconAsset =
    '$_spbOriginalIconAssetDirectory/icons_030.png';

const spbFolderIconAssetsById = <String, String>{
  '54320B4412A08007': '$_spbOriginalIconAssetDirectory/icons_003.png',
  'E864A803F91DA5C4': '$_spbOriginalIconAssetDirectory/icons_005.png',
  '4863F2D4E9D399F6': '$_spbOriginalIconAssetDirectory/icons_006.png',
  '96DAFC9A4C1F55F6': '$_spbOriginalIconAssetDirectory/icons_004.png',
  '5D595FE47887E6C9': '$_spbOriginalIconAssetDirectory/icons_008.png',
  '6E4AAD6B4F39E378': '$_spbOriginalIconAssetDirectory/icons_002.png',
  '0C1E037B56E9E59B': '$_spbOriginalIconAssetDirectory/icons_001.png',
};

const spbFolderIconAssetsByName = <String, String>{
  'air': '$_spbOriginalIconAssetDirectory/icons_007.png',
  'auto': '$_spbOriginalIconAssetDirectory/icons_009.png',
  'bank': '$_spbOriginalIconAssetDirectory/icons_005.png',
  'business': '$_spbOriginalIconAssetDirectory/icons_008.png',
  'internet': '$_spbOriginalIconAssetDirectory/icons_002.png',
};

String spbFolderIconAsset(String path, String iconId) {
  final normalizedIconId = iconId.toUpperCase();
  if (spbEmbeddedIconPngs.containsKey(normalizedIconId)) {
    return normalizedIconId;
  }
  final selectedUiIcon = uiIconIdFromSyntheticSpbIcon(normalizedIconId);
  if (selectedUiIcon != null) return selectedUiIcon;
  final storedFolderIcon = spbFolderIconAssetsById[normalizedIconId];
  if (storedFolderIcon != null) return storedFolderIcon;
  final originalIcon = spbOriginalIconAsset(normalizedIconId);
  if (originalIcon != null) return originalIcon;
  final name = path.split(RegExp(r'\s*/\s*')).last.trim().toLowerCase();
  return spbFolderIconAssetsByName[name] ?? spbDefaultOriginalIconAsset;
}

String formatCardModifiedAt(DateTime value) {
  final local = value.toLocal();
  String twoDigits(int number) => number.toString().padLeft(2, '0');
  return '${twoDigits(local.day)}.${twoDigits(local.month)}.${local.year} '
      '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
}

String spbTemplateIconForUi(SpbWalletTemplateRecord template) {
  final iconId = template.iconId.toUpperCase();
  if (spbEmbeddedIconPngs.containsKey(iconId)) return iconId;
  final normalizedName = template.name.toLowerCase();
  if (iconId == '62767D3E1BC8E2C8' &&
      (normalizedName.contains('парол') ||
          normalizedName.contains('password'))) {
    return spbPasswordTemplateIconAsset;
  }
  if (spbOriginalIconAsset(iconId) != null) return iconId;
  final selectedUiIcon = uiIconIdFromSyntheticSpbIcon(iconId);
  if (selectedUiIcon != null) return selectedUiIcon;
  return defaultIconForTemplateName(
    template.name,
    template.fields.map((field) => field.name),
  );
}

String? spbOriginalIconAsset(String iconId) {
  return spbOriginalIconAssets[iconId.toUpperCase()];
}

String? spbPngIconAsset(String iconId) {
  if ((iconId.startsWith('spb://') ||
          iconId.startsWith('assets/spb_icons_package/') ||
          iconId.startsWith('assets/spb_wallet_libraries/icons/')) &&
      iconId.toLowerCase().endsWith('.png')) {
    return normalizeSpbPackedIconId(iconId);
  }
  return spbOriginalIconAsset(iconId);
}

bool spbIconCanRender(String iconId) =>
    spbEmbeddedIconPngs.containsKey(iconId.toUpperCase()) ||
    spbPngIconAsset(iconId) != null;

String spbCardIconForUi(String cardIconId, String templateIconId) {
  if (cardIconId.isEmpty) return templateIconId;
  final normalized = cardIconId.toUpperCase();
  if (spbIconCanRender(normalized)) return normalized;
  return uiIconIdFromSyntheticSpbIcon(cardIconId) ?? templateIconId;
}

enum EntryMode { openSwl, createSwl }

enum VirtualKeyboardMode { numeric, uppercase, lowercase, symbols }

const spbWalletChannel = MethodChannel('wallet_aps/spb_wallet');
const windowChannel = MethodChannel('wallet_aps/window');

Map<String, String> spbCardValuesForUi(
  CardTemplate template,
  SpbWalletCardRecord card,
) {
  final values = Map<String, String>.from(card.fieldValues);
  values.remove(spbDescriptionFieldId);
  if (card.description.trim().isNotEmpty) {
    values[spbDescriptionFieldId] = card.description;
  }
  return values;
}

List<FieldDefinition> fieldsForItem(
  CardTemplate template,
  SecretItem item, {
  bool includeHidden = false,
}) {
  final byId = <String, FieldDefinition>{
    for (final field in template.fields) field.id: field,
  };
  for (final id in item.values.keys) {
    byId.putIfAbsent(
      id,
      () => FieldDefinition(
        id: id,
        label: 'Сохранённое поле ${id.length > 8 ? id.substring(0, 8) : id}',
        type: 'text',
      ),
    );
  }
  final visibleIds = projectVisibleFieldIds(
    definedIds: template.fields.map((field) => field.id),
    valueIds: item.values.keys,
    preferredOrder: item.fieldOrder,
    hiddenIds: includeHidden ? const {} : item.hiddenFieldIds,
  );
  return [for (final id in visibleIds) byId[id]!];
}

bool createInitialSwlVaultFile(Map<String, dynamic> payload) {
  final path = payload['path'] as String;
  final password = payload['password'] as String;
  final templates = (payload['templates'] as List<dynamic>)
      .map(
        (entry) =>
            CardTemplate.fromJson(Map<String, dynamic>.from(entry as Map)),
      )
      .toList();
  final itemEntries = (payload['items'] as List<dynamic>)
      .map((entry) => Map<String, dynamic>.from(entry as Map))
      .toList();
  final items = itemEntries.map((entry) => SecretItem.fromJson(entry)).toList();
  final categoryIcons = Map<String, String>.from(
    payload['categoryIcons'] as Map<dynamic, dynamic>,
  );
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
              .map(
                (field) => SpbWalletTemplateFieldRecord(
                  id: field.id,
                  name: field.label,
                  templateId: template.id,
                  fieldTypeId: spbFieldTypeId(field),
                ),
              )
              .toList(),
        ),
      );
    }
    final templateMap = {
      for (final template in templates) template.id: template,
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

bool cloneSwlVaultWithPassword(Map<String, dynamic> payload) {
  final path = payload['path'] as String;
  final password = payload['password'] as String;
  final sourcePassword = payload['sourcePassword'] as String;
  final passwordHint = payload['passwordHint'] as String? ?? '';
  final baseBytes = Uint8List.fromList(payload['baseBytes'] as List<int>);
  final targetFile = File(path);
  SpbWalletDatabase? verification;
  try {
    if (targetFile.existsSync()) {
      throw StateError('Файл новой базы уже существует.');
    }
    targetFile.writeAsBytesSync(baseBytes, flush: true);
    WalletRekeyService.rekeyFile(
      targetFile.path,
      oldPassword: sourcePassword,
      newPassword: password,
    );
    final opened = SpbWalletDatabase.open(targetFile.path, password);
    verification = opened;
    opened.runTransaction<void>(() {
      if (payload['renameNewWalletAboutFolder'] == true) {
        renameNewWalletAboutFolder(opened);
        opened.setImageEncodingPolicy(WalletImageEncoding.encrypted);
      }
      opened.savePasswordHint(passwordHint);
    });
    opened.flushToDisk();
    opened.close(flush: false);
    verification = null;
    return true;
  } catch (_) {
    try {
      verification?.close(flush: false);
    } catch (_) {}
    try {
      if (targetFile.existsSync()) targetFile.deleteSync();
    } catch (_) {}
    rethrow;
  }
}

void renameNewWalletAboutFolder(SpbWalletDatabase wallet) {
  final categories = wallet.loadSnapshot().categories;
  final byId = {for (final category in categories) category.id: category};
  for (final category in categories) {
    if (category.name.trim().toLowerCase() != 'о программе spb wallet') {
      continue;
    }
    final names = <String>[category.name];
    var parentId = category.parentId;
    final visited = <String>{category.id};
    while (parentId.isNotEmpty && visited.add(parentId)) {
      final parent = byId[parentId];
      if (parent == null) break;
      names.insert(0, parent.name);
      parentId = parent.parentId;
    }
    wallet.renameCategory(
      names.join(' / '),
      'О программе Wallet',
      category.iconId,
      colorId: category.colorId,
    );
  }
}

bool createSwlVaultFromBaseFile(Map<String, dynamic> payload) =>
    cloneSwlVaultWithPassword({
      ...payload,
      'sourcePassword': '0000',
      'renameNewWalletAboutFolder': true,
    });

String? normalizeNewVaultDirectorySelection(
  String selectedPath,
  FileSystemEntityType entityType,
) {
  final path = selectedPath.trim();
  if (path.isEmpty || entityType == FileSystemEntityType.notFound) return null;
  if (entityType == FileSystemEntityType.file) return File(path).parent.path;
  return entityType == FileSystemEntityType.directory ? path : null;
}

int passwordStrengthScore(String password) {
  if (password.isEmpty) {
    return 0;
  }
  var score = 1;
  if (password.length >= 8) score++;
  if (password.length >= 12) score++;
  if (RegExp(r'[a-zа-я]').hasMatch(password) &&
      RegExp(r'[A-ZА-Я]').hasMatch(password)) {
    score++;
  }
  if (RegExp(r'\d').hasMatch(password) &&
      RegExp(r'[^A-Za-zА-Яа-я0-9]').hasMatch(password)) {
    score++;
  }
  return score.clamp(0, 5);
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
    var digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final removedAutomaticDot = newValue.text.length < oldValue.text.length &&
        oldValue.text.endsWith('.') &&
        newValue.text == oldValue.text.substring(0, oldValue.text.length - 1);
    if (removedAutomaticDot && digits.isNotEmpty) {
      digits = digits.substring(0, digits.length - 1);
    }
    final trimmed = digits.length > 8 ? digits.substring(0, 8) : digits;
    final buffer = StringBuffer();
    if (trimmed.isNotEmpty) {
      buffer.write(trimmed.substring(0, min(2, trimmed.length)));
    }
    if (trimmed.length >= 2) buffer.write('.');
    if (trimmed.length > 2) {
      buffer.write(trimmed.substring(2, min(4, trimmed.length)));
    }
    if (trimmed.length >= 4) buffer.write('.');
    if (trimmed.length > 4) buffer.write(trimmed.substring(4));
    final text = buffer.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

class VaultShell extends StatefulWidget {
  const VaultShell({
    this.initiallyUnlocked = false,
    this.initialVaultPath,
    super.key,
  });

  final bool initiallyUnlocked;
  final String? initialVaultPath;

  @override
  State<VaultShell> createState() => _VaultShellState();
}

class _VaultShellState extends State<VaultShell> with WidgetsBindingObserver {
  void _updateShellState(VoidCallback callback) => setState(callback);

  Future<String?> showMoveTargetDialog({
    required String initialPath,
    Set<String> excludedPaths = const {},
  }) =>
      _VaultWorkspaceCenterPanel(this)._showMoveTargetDialogImpl(
        initialPath: initialPath,
        excludedPaths: excludedPaths,
      );

  Future<File> createSpbItemsExportFile(
    List<SecretItem> exportItems, {
    required String password,
    String? categoryPath,
    String? targetPath,
  }) =>
      _VaultWorkspaceCenterPanel(this)._createSpbItemsExportFileImpl(
        exportItems,
        password: password,
        categoryPath: categoryPath,
        targetPath: targetPath,
      );

  List<SpbVisibleTreeEntry> buildSpbVisibleTreeEntries(
    CategoryTreeNode root, {
    required bool showWalletRoot,
  }) =>
      _VaultWorkspaceNavigationPanel(this)._buildSpbVisibleTreeEntriesImpl(
        root,
        showWalletRoot: showWalletRoot,
      );

  Future<bool> closeCurrentVaultForPasswordPrompt() =>
      _VaultFileSessionOperations(this)
          ._closeCurrentVaultForPasswordPromptImpl();

  Future<void> openChangePasswordDialog() =>
      _PasswordLockOperations(this)._openChangePasswordDialogImpl();

  Future<void> showInactivityWarning() =>
      _PasswordLockOperations(this)._showInactivityWarningImpl();

  Future<bool> deleteItemWithConfirmation(SecretItem item) =>
      _CardOperations(this)._deleteItemWithConfirmationImpl(item);

  void applySpbSnapshot(SpbWalletSnapshot snapshot) =>
      _SpbUiMapping(this)._applySpbSnapshotImpl(snapshot);

  final vaultNameController = TextEditingController(text: 'личная');
  final passwordController = TextEditingController();
  final confirmController = TextEditingController();
  final searchController = TextEditingController();
  final walletSearchController = WalletSearchController();
  final navigationController = VaultNavigationController<SecretItem>();
  final sessionController = VaultSessionController();
  final passwordFocusNode = FocusNode(debugLabel: 'vaultPassword');

  EntryMode entryMode = EntryMode.openSwl;
  bool showPassword = false;
  bool showConfirm = false;
  bool loginHintVisible = false;
  String loginPasswordHint = '';
  bool unlocked = false;
  bool? menuOpenOverride;
  bool creatingVault = false;
  String? configuredWindowMode;
  String? configuredMainWindowTitle;
  VirtualKeyboardMode virtualKeyboardMode = VirtualKeyboardMode.numeric;
  String activeView = 'cards';
  String? message;
  String? spbWalletPath;
  String? spbWalletUri;
  String? spbWalletDisplayPath;
  bool spbWalletWritable = true;
  bool spbWritePending = false;
  bool vaultDirty = false;
  final VaultOperationCoordinator vaultOperations = VaultOperationCoordinator();
  String? syncSourcePath;
  int? syncSourceLength;
  String? syncSourceSha256;
  String? syncSourceUrl;
  String? syncSourceEtag;
  String? syncOriginProvider;
  SpbWalletDatabase? spbWallet;
  String syncProvider = 'mounted_folder';
  String templateFilter = '';
  String templateSearchQuery = '';
  String sortMode = 'modified_desc';
  String? selectedItemId;
  final List<String> recentlyOpenedItemIds = [];
  String get selectedCategoryPath => navigationController.selectedCategoryPath;
  set selectedCategoryPath(String value) =>
      navigationController.selectedCategoryPath = value;
  String? get selectedCategoryId => navigationController.selectedCategoryId;
  set selectedCategoryId(String? value) =>
      navigationController.selectedCategoryId = value;
  bool get mobileTemplatesOpen => navigationController.mobileTemplatesOpen;
  set mobileTemplatesOpen(bool value) =>
      navigationController.mobileTemplatesOpen = value;
  String? selectedTemplateId;
  int get mobilePane => navigationController.mobilePane;
  set mobilePane(int value) => navigationController.mobilePane = value;
  bool get rootTreeExpanded => navigationController.rootTreeExpanded;
  set rootTreeExpanded(bool value) =>
      navigationController.rootTreeExpanded = value;
  Set<String> get expandedCategoryPaths =>
      navigationController.expandedCategoryPaths;
  double? spbNavigatorWidth;
  double? spbActionsPanelWidth;
  String spbSubmittedSearchQuery = '';
  bool spbExactSearch = false;
  WalletSearchResult spbSearchResult = const WalletSearchResult.empty();
  Timer? spbSearchDebounce;
  int spbSearchRevision = 0;
  int spbSearchGeneration = 0;
  bool spbTasksExpanded = true;
  bool spbFoundExpanded = true;
  bool spbFrequentExpanded = true;
  bool spbObjectMenuPointerActive = false;
  bool spbContextMenuOpen = false;
  final GlobalKey spbSessionUndoButtonKey = GlobalKey();
  final GlobalKey spbSessionTrashButtonKey = GlobalKey();
  final ScrollController spbFoundScrollController = ScrollController();
  final ScrollController spbFrequentScrollController = ScrollController();
  final ScrollController spbMobileActionsScrollController = ScrollController();
  int get inactivitySecondsRemaining =>
      sessionController.inactivitySecondsRemaining;
  bool get inactivityWarningVisible =>
      sessionController.inactivityWarningVisible;
  int get lockedExitSecondsRemaining =>
      sessionController.lockedExitSecondsRemaining;
  bool get lockedExitWarningVisible =>
      sessionController.lockedExitWarningVisible;
  Timer? passwordUnlockDebounce;
  bool automaticUnlockInProgress = false;
  bool get closingForInactivity => sessionController.closingForInactivity;
  DateTime get lastUserActivityAt => sessionController.lastUserActivityAt;
  DateTime? lastSyncAt;

  List<CardTemplate> templates = builtInTemplates();
  List<SecretItem> items = [];
  Map<String, CardTemplate> templatesById = {};
  Map<String, SecretItem> itemsById = {};
  List<ConflictRecord> conflicts = [];
  List<SpbWalletCardLoadFailure> cardLoadFailures = [];
  WalletLoadReport walletLoadReport = const WalletLoadReport([]);
  List<ExistingVault> recentVaults = [];
  final Map<String, String> spbIconIdByUiIcon = {};
  Map<String, String> categoryIconsByPath = {};
  Map<String, String> categoryColorsByPath = {};
  Map<String, String> categoryIdsByPath = {};
  Map<String, String> categoryPathsById = {};
  Set<String> categoryPaths = {};
  final Set<String> revealed = {};
  final Map<String, String> syncConfig = {};
  final List<SessionTrashEntry> sessionTrash = [];
  final Set<String> sessionTrashCardIds = {};
  final Set<String> sessionTrashFolderPaths = {};
  final Set<String> sessionTrashTemplateIds = {};
  final List<SessionUndoEntry> sessionUndoHistory = [];
  static const int sessionUndoEntryLimit = 12;
  static const int sessionUndoByteLimit = 256 * 1024 * 1024;
  bool sessionUndoInProgress = false;

  bool get createMode => entryMode == EntryMode.createSwl;

  String get normalizedVaultBaseName {
    final rawName = vaultNameController.text.trim().replaceAll(
          RegExp(r'\.swl$', caseSensitive: false),
          '',
        );
    final safeName = rawName.isEmpty ? 'personal' : rawName;
    return safeName.replaceAll(RegExp(r'[^\wа-яА-ЯёЁ.-]+', unicode: true), '_');
  }

  @override
  void initState() {
    super.initState();
    templatesById = indexEntitiesById(templates, (template) => template.id);
    WidgetsBinding.instance.addObserver(this);
    unlocked = widget.initiallyUnlocked;
    final initialVaultPath = widget.initialVaultPath;
    if (initialVaultPath != null && initialVaultPath.isNotEmpty) {
      spbWalletPath = initialVaultPath;
      spbWalletDisplayPath = initialVaultPath;
      vaultNameController.text = _vaultTitleFromPath(initialVaultPath);
    }
    refreshSpbSearchIndex();
    passwordController.addListener(scheduleAutomaticUnlock);
    loadRecentVaults();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        passwordFocusNode.requestFocus();
        initializeExternalWalletHandling();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    sessionController.dispose();
    clearSessionUndoHistory();
    spbWallet?.close(flush: false);
    passwordUnlockDebounce?.cancel();
    spbSearchDebounce?.cancel();
    vaultNameController.dispose();
    passwordController.dispose();
    confirmController.dispose();
    searchController.dispose();
    spbFoundScrollController.dispose();
    spbFrequentScrollController.dispose();
    spbMobileActionsScrollController.dispose();
    passwordFocusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      unawaited(finalizeSessionTrash());
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      unawaited(writeBackSpbWallet());
    }
    if (state == AppLifecycleState.resumed) {
      final idleFor = sessionController.idleDuration;
      if (unlocked && idleFor >= const Duration(minutes: 3)) {
        unawaited(closeAfterInactivity());
      } else if (unlocked &&
          idleFor >= const Duration(minutes: 2, seconds: 45)) {
        unawaited(showInactivityWarning());
      } else if (!unlocked && idleFor >= const Duration(minutes: 5)) {
        unawaited(exitApplication());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    synchronizeWindowMode();
    if (!unlocked) {
      sessionController.cancelInactivityTimer();
      ensureLockedExitTimer();
      return Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => recordLockedUserActivity(),
        onPointerMove: (_) => recordLockedUserActivity(),
        onPointerSignal: (_) => recordLockedUserActivity(),
        child: Focus(
          canRequestFocus: false,
          onKeyEvent: (_, __) {
            recordLockedUserActivity();
            return KeyEventResult.ignored;
          },
          child: buildLocked(),
        ),
      );
    }
    sessionController.cancelLockedExitTimer();
    ensureInactivityTimer();
    final shell = LayoutBuilder(
      builder: (context, constraints) {
        final portraitTablet = constraints.maxHeight > constraints.maxWidth &&
            min(constraints.maxWidth, constraints.maxHeight) >= 600;
        final mobile = constraints.maxWidth < 700 ||
            constraints.maxHeight < 500 ||
            portraitTablet;
        return mobile ? buildSpbMobileShell() : buildSpbDesktopShell();
      },
    );
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => recordUserActivity(),
      onPointerMove: (_) => recordUserActivity(),
      onPointerHover: (_) => recordUserActivity(),
      onPointerSignal: (_) => recordUserActivity(),
      child: Focus(
        canRequestFocus: false,
        onKeyEvent: (_, __) {
          recordUserActivity();
          return KeyEventResult.ignored;
        },
        child: shell,
      ),
    );
  }

  static const _spbRightPanel = Color(0xffc7d9ea);
  static const _spbBorder = Color(0xffb7b7b7);

  Widget spbWorkspaceScrollbarTheme(Widget child) {
    return ScrollbarTheme(
      data: Theme.of(context).scrollbarTheme.copyWith(
            thickness: const WidgetStatePropertyAll<double>(10.88),
          ),
      child: child,
    );
  }

  Widget spbResourceIcon(String fileName, double size) => spbPackedImage(
        'spb://apk_icons/res/drawable-hdpi/$fileName',
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        fallback: Icon(Icons.image_outlined, size: size),
      );

  Widget spbSizedDataIcon(String iconId, double size, {Color? fallbackColor}) {
    final embeddedBytes = spbEmbeddedIconPngs[iconId.toUpperCase()];
    if (embeddedBytes != null) {
      return Image.memory(
        embeddedBytes,
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) => Icon(
          Icons.vpn_key_outlined,
          size: size,
          color: fallbackColor ?? const Color(0xffd79a00),
        ),
      );
    }
    final asset = spbPngIconAsset(iconId);
    if (asset != null) {
      return spbPackedImage(
        asset,
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        fallback: Icon(
          templateIconGlyph(iconId),
          size: size,
          color: fallbackColor ?? const Color(0xffd79a00),
        ),
      );
    }
    return Icon(
      templateIconGlyph(iconId),
      size: size,
      color: fallbackColor ?? const Color(0xffd79a00),
    );
  }

  Widget spbSectionHeader(
    String title, {
    Widget? leading,
    Widget? trailing,
    double height = 34,
    bool bold = false,
  }) {
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xffa9c9e3), Color(0xffe9f1f8)],
        ),
        border: Border(bottom: BorderSide(color: _spbBorder)),
      ),
      child: Row(
        children: [
          if (leading != null) ...[
            leading,
            const SizedBox(width: 7),
          ],
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 17,
                fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget buildSpbSearchBar({
    bool mobile = false,
    double? desktopNavigatorWidth,
    double? desktopActionsPanelWidth,
  }) {
    final searchField = OverflowBox(
      maxHeight: 68,
      alignment: Alignment.centerLeft,
      child: Transform.translate(
        offset: const Offset(0, 21),
        child: SizedBox(
          width: mobile ? double.infinity : 250.445,
          height: 68,
          child: TextField(
            key: const Key('spbSearchInput'),
            controller: searchController,
            onChanged: updateSpbSearch,
            onSubmitted: submitSpbSearch,
            textInputAction: TextInputAction.search,
            textAlignVertical: TextAlignVertical.bottom,
            style: const TextStyle(
              fontSize: 19,
              height: 1,
              fontWeight: FontWeight.normal,
            ),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: const Color(0xffffffff),
              border: const OutlineInputBorder(
                borderRadius: BorderRadius.zero,
                borderSide: BorderSide(color: Colors.black87, width: 1.2),
              ),
              enabledBorder: const OutlineInputBorder(
                borderRadius: BorderRadius.zero,
                borderSide: BorderSide(color: Colors.black87, width: 1.2),
              ),
              focusedBorder: const OutlineInputBorder(
                borderRadius: BorderRadius.zero,
                borderSide: BorderSide(color: Colors.black, width: 1.5),
              ),
              contentPadding: const EdgeInsets.fromLTRB(12, 0, 4, 12),
              suffixIcon: buildSearchClearButton(
                const Key('spbClearSearchButton'),
              ),
              suffixIconConstraints: const BoxConstraints(
                minWidth: 30,
                minHeight: 30,
              ),
            ),
          ),
        ),
      ),
    );
    return Container(
      height: 48,
      color: const Color(0xfff4f4f4),
      padding: EdgeInsets.fromLTRB(mobile ? 22 : 11, 7, 12, 7),
      child: mobile
          ? LayoutBuilder(
              builder: (context, constraints) => Row(
                children: [
                  if (constraints.maxWidth >= 316) ...[
                    Transform.translate(
                      offset: const Offset(0, 3),
                      child: const Text(
                        'Поиск',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xff202020),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(child: searchField),
                  const SizedBox(width: 4),
                  buildSpbSearchButton(
                    key: const Key('spbSubmitSearchButton'),
                    icon: Icons.search,
                    tooltip: 'Начать поиск',
                    gradient: const [Color(0xff42bff5), Color(0xff006fc4)],
                    onTap: () => submitSpbSearch(searchController.text),
                  ),
                  const SizedBox(width: 4),
                  buildSpbSearchButton(
                    key: spbSessionUndoButtonKey,
                    icon: Icons.undo,
                    tooltip: 'Отменить изменения этой сессии',
                    gradient: const [Color(0xffffdc58), Color(0xffc58a00)],
                    onTap: showSessionUndoMenu,
                  ),
                  const SizedBox(width: 4),
                  Transform.translate(
                    offset: const Offset(-1, 0),
                    child: buildSpbSearchButton(
                      key: const Key('spbForceCloseButton'),
                      icon: Icons.power_settings_new,
                      tooltip: 'Сохранить базу и закрыть программу',
                      gradient: const [Color(0xffff5a5f), Color(0xffa90000)],
                      onTap: exitApplication,
                    ),
                  ),
                ],
              ),
            )
          : Stack(
              clipBehavior: Clip.none,
              children: [
                Row(
                  children: [
                    Transform.translate(
                      offset: const Offset(0, 3),
                      child: const Text(
                        'Поиск',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xff202020),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(width: 250.445, child: searchField),
                  ],
                ),
                Positioned(
                  left: max(
                    0,
                    (desktopNavigatorWidth ?? 300) - 11 - 34.2,
                  ),
                  top: 0,
                  child: buildSpbSearchButton(
                    key: const Key('spbSubmitSearchButton'),
                    icon: Icons.search,
                    tooltip: 'Начать поиск',
                    gradient: const [Color(0xff42bff5), Color(0xff006fc4)],
                    onTap: () => submitSpbSearch(searchController.text),
                  ),
                ),
                Positioned(
                  right: (desktopActionsPanelWidth ?? 300) - 49.2,
                  top: 0,
                  child: Row(
                    children: [
                      buildSpbSearchButton(
                        key: spbSessionUndoButtonKey,
                        icon: Icons.undo,
                        tooltip: 'Отменить изменения этой сессии',
                        gradient: const [Color(0xffffdc58), Color(0xffc58a00)],
                        onTap: showSessionUndoMenu,
                      ),
                      const SizedBox(width: 4),
                      Transform.translate(
                        offset: const Offset(-1, 0),
                        child: buildSpbSearchButton(
                          key: const Key('spbForceCloseButton'),
                          icon: Icons.power_settings_new,
                          tooltip: 'Сохранить базу и закрыть программу',
                          gradient: const [
                            Color(0xffff5a5f),
                            Color(0xffa90000),
                          ],
                          onTap: exitApplication,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> showSessionUndoMenu() async {
    final buttonContext = spbSessionUndoButtonKey.currentContext;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    final button = buttonContext?.findRenderObject() as RenderBox?;
    if (button == null || overlay == null) return;
    final offset = button.localToGlobal(Offset.zero, ancestor: overlay);
    final selected = await showMenu<int>(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy + button.size.height,
        overlay.size.width - offset.dx - button.size.width,
        0,
      ),
      items: sessionUndoHistory.isEmpty
          ? const [
              PopupMenuItem<int>(
                enabled: false,
                child: Text('Нет изменений для отмены'),
              ),
            ]
          : [
              for (var index = sessionUndoHistory.length - 1;
                  index >= 0;
                  index--)
                PopupMenuItem<int>(
                  value: index,
                  child: Row(
                    children: [
                      templateIconWidget(
                        sessionUndoHistory[index].iconId,
                        size: 28,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          sessionUndoHistory[index].label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
    );
    if (selected != null && mounted) {
      await restoreSessionUndoAt(selected);
    }
  }

  Future<void> showSessionTrashMenu() async {
    final buttonContext = spbSessionTrashButtonKey.currentContext;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    final button = buttonContext?.findRenderObject() as RenderBox?;
    if (button == null || overlay == null) return;
    final offset = button.localToGlobal(Offset.zero, ancestor: overlay);
    final entries = sessionTrash.reversed.toList();
    final selected = await showMenu<SessionTrashEntry>(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy + button.size.height,
        overlay.size.width - offset.dx - button.size.width,
        0,
      ),
      items: entries.isEmpty
          ? const [
              PopupMenuItem<SessionTrashEntry>(
                enabled: false,
                child: Text('Корзина пуста'),
              ),
            ]
          : [
              for (final entry in entries)
                PopupMenuItem<SessionTrashEntry>(
                  value: entry,
                  child: Row(
                    children: [
                      templateIconWidget(entry.iconId, size: 28),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          entry.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
    );
    if (selected != null && mounted) {
      await restoreSessionTrashEntry(selected);
    }
  }

  Future<void> restoreSessionTrashEntry(SessionTrashEntry entry) async {
    final wallet = spbWallet;
    if (wallet == null) return;
    SessionUndoEntry? undoEntry;
    try {
      final kind = switch (entry.kind) {
        SessionTrashKind.card => 'карточки',
        SessionTrashKind.folder => 'папки',
        SessionTrashKind.template => 'шаблона',
      };
      undoEntry = await captureSessionUndo(
        'Восстановление $kind: ${entry.title}',
        entry.iconId,
      );
      switch (entry.kind) {
        case SessionTrashKind.card:
          sessionTrashCardIds.remove(entry.id);
          break;
        case SessionTrashKind.folder:
          sessionTrashFolderPaths.remove(entry.id);
          break;
        case SessionTrashKind.template:
          sessionTrashTemplateIds.remove(entry.id);
          break;
      }
      sessionTrash.remove(entry);
      final snapshot = wallet.loadSnapshot();
      setState(() {
        applySpbSnapshot(snapshot);
        message = null;
      });
      commitSessionUndo(undoEntry);
    } catch (error) {
      discardSessionUndo(undoEntry);
      showSpbOperationMessage('Не удалось восстановить объект: $error');
    }
  }

  Widget buildSpbSearchButton({
    required Key key,
    required IconData icon,
    required String tooltip,
    required List<Color> gradient,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: 34.2,
      height: 34,
      child: OverflowBox(
        minHeight: 34.2,
        maxHeight: 34.2,
        child: SizedBox.square(
          dimension: 34.2,
          child: Tooltip(
            message: tooltip,
            child: Material(
              color: Colors.transparent,
              child: Ink(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: gradient,
                  ),
                  borderRadius: BorderRadius.circular(2.7),
                  border: Border.all(color: const Color(0x99000000)),
                ),
                child: InkWell(
                  key: key,
                  borderRadius: BorderRadius.circular(2.7),
                  onTap: onTap,
                  child: Icon(icon, color: Colors.white, size: 22.5),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void refreshSpbSearchIndex() {
    final allPaths = <String>{};
    for (final category in existingCategories()) {
      final parts = categoryParts(category);
      for (var index = 1; index <= parts.length; index++) {
        allPaths.add(parts.take(index).join(' / '));
      }
    }
    spbSearchRevision++;
    walletSearchController.replaceIndex(
      revision: spbSearchRevision,
      folders: [
        for (final path in allPaths)
          WalletSearchDocument(
            id: path,
            sortValue: path,
            searchableText: path,
            exactValues: [
              path,
              if (categoryParts(path).isNotEmpty) categoryParts(path).last,
            ],
          ),
      ],
      cards: [
        for (final item in items)
          WalletSearchDocument(
            id: item.id,
            sortValue: item.title,
            searchableText: [
              item.title,
              item.category,
              templateFor(item.templateId).name,
              ...item.values.values,
            ].join(' '),
            exactValues: [
              item.title,
              item.category,
              templateFor(item.templateId).name,
              ...item.values.values,
            ],
          ),
      ],
    );
    final query = spbSubmittedSearchQuery;
    if (query.isNotEmpty) {
      unawaited(_performSpbSearch(query, exact: spbExactSearch));
    }
  }

  Future<void> _performSpbSearch(
    String query, {
    required bool exact,
  }) async {
    final generation = ++spbSearchGeneration;
    final result = await walletSearchController.search(query, exact: exact);
    if (!mounted ||
        generation != spbSearchGeneration ||
        query != spbSubmittedSearchQuery ||
        exact != spbExactSearch ||
        result.revision != walletSearchController.revision) {
      return;
    }
    setState(() => spbSearchResult = result);
  }

  void submitSpbSearch(String value) {
    spbSearchDebounce?.cancel();
    final query = value.trim();
    setState(() {
      spbSubmittedSearchQuery = query;
      spbExactSearch = true;
      spbSearchResult = const WalletSearchResult.empty();
    });
    if (query.isNotEmpty) {
      unawaited(_performSpbSearch(query, exact: true));
    } else {
      spbSearchGeneration++;
    }
  }

  void updateSpbSearch(String value) {
    spbSearchDebounce?.cancel();
    final query = value.trim();
    final size = MediaQuery.sizeOf(context);
    final portraitTablet =
        size.height > size.width && min(size.width, size.height) >= 600;
    final narrowLayout =
        size.width < 700 || size.height < 500 || portraitTablet;
    setState(() {
      spbSubmittedSearchQuery = query;
      spbExactSearch = false;
      spbSearchResult = const WalletSearchResult.empty();
      if (query.isNotEmpty &&
          (defaultTargetPlatform == TargetPlatform.android || narrowLayout)) {
        mobileTemplatesOpen = false;
        mobilePane = 1;
      }
    });
    if (query.isEmpty) {
      spbSearchGeneration++;
      return;
    }
    spbSearchDebounce = Timer(
      const Duration(milliseconds: 150),
      () => _performSpbSearch(query, exact: false),
    );
  }

  void clearSearch() {
    spbSearchDebounce?.cancel();
    spbSearchGeneration++;
    searchController.clear();
    setState(() {
      spbSubmittedSearchQuery = '';
      spbExactSearch = false;
      spbSearchResult = const WalletSearchResult.empty();
    });
  }

  Widget? buildSearchClearButton(Key key) {
    if (searchController.text.isEmpty) return null;
    return IconButton(
      key: key,
      tooltip: 'Очистить поиск',
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      icon: const Icon(Icons.close, size: 16),
      onPressed: clearSearch,
    );
  }

  bool spbSearchMatches(String text, String query) {
    return WalletSearchController.matches(text, query);
  }

  List<String> spbMatchingFolderPaths(String query) {
    if (query.trim() != spbSearchResult.query ||
        spbExactSearch != spbSearchResult.exact) {
      return const [];
    }
    return spbSearchResult.folderPaths;
  }

  List<SecretItem> spbMatchingCards(String query) {
    if (query.trim() != spbSearchResult.query ||
        spbExactSearch != spbSearchResult.exact) {
      return const [];
    }
    return [
      for (final id in spbSearchResult.cardIds)
        if (itemsById[id] case final item?) item,
    ];
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
                  Text(
                    viewTitle(),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
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

  CardTemplate templateFor(String id) {
    final indexed = templatesById[id];
    if (indexed != null) return indexed;
    return templates.isEmpty ? builtInTemplates().first : templates.first;
  }

  Future<void> runSync() async {
    if (spbWallet == null) {
      setState(() => message = 'Запись доступна после открытия .swl базы.');
      return;
    }
    if (!vaultDirty) {
      showSpbOperationMessage('Изменений нет. Файл базы не перезаписывался.');
      return;
    }
    final ok = await writeBackSpbWallet();
    if (!mounted) return;
    showSpbOperationMessage(
      ok
          ? 'База успешно сохранена.'
          : 'Исходный файл не записан. Можно повторить сохранение.',
    );
    setState(() {
      if (ok) {
        lastSyncAt = DateTime.now();
        message = syncSourcePath == null && syncSourceUrl == null
            ? 'База сохранена локально.'
            : 'База записана в исходное хранилище.';
      }
    });
  }

  Future<void> saveVaultThroughExplorer() async {
    final sourcePath = spbWalletPath;
    if (spbWallet == null || sourcePath == null || sourcePath.isEmpty) {
      setState(() => message = 'Запись доступна после открытия .swl базы.');
      return;
    }
    final written = await writeBackSpbWallet();
    if (!written || !mounted) return;
    final source = File(sourcePath);
    final suggestedName = spbWalletDisplayPath == null ||
            spbWalletDisplayPath!.startsWith('content://')
        ? '${selectedVaultTitle.replaceFirst(RegExp(r'\.swl$', caseSensitive: false), '')}.swl'
        : File(spbWalletDisplayPath!).uri.pathSegments.last;
    try {
      if (Platform.isAndroid) {
        final document = await spbWalletChannel
            .invokeMapMethod<String, Object?>('createSpbWalletDocument', {
          'displayName': suggestedName,
        });
        final uri = document?['uri']?.toString();
        if (uri == null || uri.isEmpty) return;
        final expectedLength = await source.length();
        final expectedSha256 = await sha256File(source);
        final copied = await spbWalletChannel
            .invokeMapMethod<String, Object?>('writeSpbWallet', {
          'uri': uri,
          'localPath': sourcePath,
          'expectedLength': expectedLength,
          'expectedSha256': expectedSha256,
        });
        if (copied == null ||
            copied['length'] != expectedLength ||
            copied['sha256'] != expectedSha256) {
          throw StateError('Системный проводник не записал выбранный файл.');
        }
      } else {
        final targetPath = await FilePicker.platform.saveFile(
          dialogTitle: 'Сохранить базу',
          fileName: suggestedName,
          initialDirectory: source.parent.path,
          type: FileType.custom,
          allowedExtensions: const ['swl'],
        );
        if (targetPath == null || targetPath.trim().isEmpty) return;
        if (File(targetPath).absolute.path.toLowerCase() !=
            source.absolute.path.toLowerCase()) {
          await source.copy(targetPath);
        }
      }
      if (!mounted) return;
      setState(() {
        lastSyncAt = DateTime.now();
        message = 'База сохранена.';
      });
      showSpbOperationMessage('База сохранена.');
    } catch (error) {
      if (!mounted) return;
      showSpbOperationMessage('Не удалось сохранить базу: $error');
    }
  }
}
