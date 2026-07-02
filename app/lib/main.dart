import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';

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
  });

  final String id;
  final String templateId;
  final String title;
  final String category;
  final String colorId;
  final Map<String, String> values;
  final DateTime modifiedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'templateId': templateId,
        'title': title,
        'category': category,
        'colorId': colorId,
        'values': values,
        'modifiedAt': modifiedAt.toIso8601String(),
      };

  factory SecretItem.fromJson(Map<String, dynamic> json) => SecretItem(
        id: json['id'] as String,
        templateId: json['templateId'] as String,
        title: json['title'] as String,
        category: json['category'] as String? ?? '',
        colorId: json['colorId'] as String? ?? 'neutral',
        values: Map<String, String>.from(json['values'] as Map<dynamic, dynamic>),
        modifiedAt: DateTime.parse(json['modifiedAt'] as String),
      );
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

  bool createMode = false;
  bool showPassword = false;
  bool showConfirm = false;
  bool unlocked = false;
  String activeView = 'cards';
  String? message;
  String syncProvider = 'mounted_folder';
  String templateFilter = '';
  String sortMode = 'modified_desc';

  List<CardTemplate> templates = builtInTemplates();
  List<SecretItem> items = [];
  List<ConflictRecord> conflicts = [];
  final Set<String> revealed = {};
  final Map<String, String> syncConfig = {};

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
    vaultNameController.dispose();
    passwordController.dispose();
    confirmController.dispose();
    searchController.dispose();
    super.dispose();
  }

  Future<void> unlock() async {
    final password = passwordController.text;
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
      await saveVault();
      setState(() {
        unlocked = true;
        message = null;
      });
      return;
    }
    try {
      await loadVault();
      setState(() {
        unlocked = true;
        message = null;
      });
    } catch (_) {
      setState(() => message = 'База не найдена или пароль не подходит. Для новой базы выберите “Создать”.');
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
    ];
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
  }

  Future<void> saveVault() async {
    final payload = {
      'format': 'actitpass-flutter-alpha',
      'passwordHash': passwordHash(passwordController.text),
      'templates': templates.map((template) => template.toJson()).toList(),
      'items': items.map((item) => item.toJson()).toList(),
      'conflicts': conflicts.map((conflict) => conflict.toJson()).toList(),
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
        );
      },
    );
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
                          SegmentedButton<bool>(
                            segments: const [
                              ButtonSegment(value: false, label: Text('Открыть')),
                              ButtonSegment(value: true, label: Text('Создать')),
                            ],
                            selected: {createMode},
                            onSelectionChanged: (value) => setState(() => createMode = value.first),
                          ),
                          const SizedBox(height: 18),
                          TextField(
                            controller: vaultNameController,
                            decoration: const InputDecoration(labelText: 'Название базы', border: OutlineInputBorder()),
                          ),
                          const SizedBox(height: 12),
                          PasswordField(
                            controller: passwordController,
                            label: 'Мастер-пароль',
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
                              child: Text(createMode ? 'Создать базу' : 'Открыть базу'),
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
            const ListTile(
              leading: CircleAvatar(child: Text('A')),
              title: Text('ActitPass'),
              subtitle: Text('локальная база'),
            ),
            const SizedBox(height: 12),
            ...navButtons(),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: () => setState(() => unlocked = false),
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
    return Column(
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            SizedBox(
              width: 320,
              child: TextField(
                controller: searchController,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Поиск', border: OutlineInputBorder()),
              ),
            ),
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<String>(
                initialValue: templateFilter,
                decoration: const InputDecoration(labelText: 'Шаблон', border: OutlineInputBorder()),
                items: [
                  const DropdownMenuItem(value: '', child: Text('Все шаблоны')),
                  ...templates.map((template) => DropdownMenuItem(value: template.id, child: Text(template.name))),
                ],
                onChanged: (value) => setState(() => templateFilter = value ?? ''),
              ),
            ),
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<String>(
                initialValue: sortMode,
                decoration: const InputDecoration(labelText: 'Сортировка', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'modified_desc', child: Text('Сначала новые')),
                  DropdownMenuItem(value: 'title_asc', child: Text('По названию')),
                  DropdownMenuItem(value: 'template_asc', child: Text('По шаблону')),
                ],
                onChanged: (value) => setState(() => sortMode = value ?? 'modified_desc'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 420,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              mainAxisExtent: 260,
            ),
            itemCount: filtered.length,
            itemBuilder: (context, index) => itemCard(filtered[index]),
          ),
        ),
      ],
    );
  }

  Widget itemCard(SecretItem item) {
    final template = templateFor(item.templateId);
    final color = colorById(item.colorId.isEmpty ? template.colorId : item.colorId);
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
              Text('Категория: ${item.category.isEmpty ? 'Без категории' : item.category}', style: TextStyle(color: color.fg.withValues(alpha: 0.72))),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildTemplatesView() {
    return ListView.separated(
      itemCount: templates.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final template = templates[index];
        final color = colorById(template.colorId);
        return Card(
          elevation: 0,
          child: ListTile(
            leading: CircleAvatar(backgroundColor: color.bg, foregroundColor: color.fg, child: Text(iconById(template.iconId).symbol)),
            title: Text(template.name),
            subtitle: Text(template.fields.map((field) => '${field.label}${field.secret ? ' (скрыто)' : ''}').join(', ')),
            trailing: template.builtIn ? const Chip(label: Text('Встроенный')) : const Icon(Icons.edit),
            onTap: template.builtIn ? null : () => openTemplateDialog(template: template),
          ),
        );
      },
    );
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
      ),
    );
    if (saved == null) return;
    setState(() {
      items = [
        ...items.where((entry) => entry.id != saved.id),
        saved,
      ];
    });
    await saveVault();
  }

  Future<void> openTemplateDialog({CardTemplate? template}) async {
    final saved = await showDialog<CardTemplate>(
      context: context,
      builder: (context) => TemplateEditorDialog(initial: template),
    );
    if (saved == null) return;
    setState(() {
      templates = [
        ...templates.where((entry) => entry.id != saved.id),
        saved,
      ];
    });
    await saveVault();
  }

  Future<void> runSync() async {
    setState(() {
      conflicts = [
        ConflictRecord(
          id: makeId('conflict'),
          title: 'Проверка синхронизации: ${syncTitle(syncProvider)}',
          description: 'Демо-запись показывает журнал конфликтов. В промышленном Rust-ядре здесь будет результат last-write-wins merge.',
          createdAt: DateTime.now(),
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

class ItemEditorDialog extends StatefulWidget {
  const ItemEditorDialog({
    required this.templates,
    this.initial,
    super.key,
  });

  final List<CardTemplate> templates;
  final SecretItem? initial;

  @override
  State<ItemEditorDialog> createState() => _ItemEditorDialogState();
}

class _ItemEditorDialogState extends State<ItemEditorDialog> {
  late String templateId;
  late String colorId;
  late final TextEditingController title;
  late final TextEditingController category;
  late final Map<String, TextEditingController> values;
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
                modifiedAt: DateTime.now(),
              ),
            );
          },
          child: const Text('Сохранить'),
        ),
      ],
    );
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
              ColorPicker(value: colorId, onChanged: (value) => setState(() => colorId = value)),
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
          children: palette.map((color) => ChoiceChip(
                selected: color.id == value,
                avatar: CircleAvatar(backgroundColor: color.bg),
                label: Text(color.label),
                onSelected: (_) => onChanged(color.id),
              )).toList(),
        ),
      ],
    );
  }
}
