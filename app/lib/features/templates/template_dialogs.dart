part of '../../main.dart';

class TemplatePreviewDialog extends StatelessWidget {
  const TemplatePreviewDialog({required this.template, super.key});

  final CardTemplate template;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.sizeOf(context);
    final fullScreen = Platform.isAndroid || media.width < 700;
    final backgroundColor = templateDisplayBackground(template);
    Uint8List? customIconBytes;
    try {
      final encoded = template.embeddedIconBase64;
      if (encoded != null) customIconBytes = base64Decode(encoded);
    } catch (_) {
      customIconBytes = null;
    }
    return Align(
      alignment: Alignment.center,
      child: Material(
        color: const Color(0xfff4f4f4),
        elevation: 24,
        clipBehavior: Clip.antiAlias,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(color: Color(0xff7f8d98)),
        ),
        child: SizedBox(
          key: const Key('templatePreviewSurface'),
          width: fullScreen ? media.width : min(media.width - 24, 720),
          height: fullScreen ? media.height : min(media.height - 24, 760),
          child: Column(
            children: [
              Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xffa9c9e3), Color(0xffe9f1f8)],
                  ),
                  border: Border(bottom: BorderSide(color: Color(0xff7f8d98))),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        template.name,
                        key: const Key('templatePreviewTitle'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 18),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Tooltip(
                      message: 'Закрыть просмотр',
                      child: Material(
                        key: const Key('templatePreviewCloseButton'),
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => Navigator.pop(context),
                          child: Ink(
                            width: 38,
                            height: 34,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Color(0xffff5a5f), Color(0xffa90000)],
                              ),
                              border: Border.all(
                                color: const Color(0xff56636c),
                              ),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: const Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ColoredBox(
                  color: backgroundColor,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Container(
                            width: 112,
                            height: 112,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border.all(
                                color: const Color(0xff82929d),
                                width: 2,
                              ),
                              borderRadius: BorderRadius.circular(5),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x26000000),
                                  offset: Offset(1, 2),
                                  blurRadius: 5,
                                ),
                              ],
                            ),
                            child: customIconBytes == null
                                ? templateIconWidget(
                                    template.iconId,
                                    size: 88,
                                    color: pictogramColorForBackground(
                                      backgroundColor,
                                    ),
                                  )
                                : Image.memory(
                                    customIconBytes,
                                    width: 88,
                                    height: 88,
                                    fit: BoxFit.contain,
                                    filterQuality: FilterQuality.medium,
                                  ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        for (final field in template.fields)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: TextFormField(
                              key: ValueKey('templatePreviewField-${field.id}'),
                              initialValue: '',
                              readOnly: true,
                              minLines: field.type == 'multiline_note' ? 3 : 1,
                              maxLines: field.type == 'multiline_note' ? 5 : 1,
                              decoration: InputDecoration(
                                labelText: field.label,
                                hintText: _fieldTypeLabel(field.type),
                                prefixIcon: Icon(_fieldTypeIcon(field.type)),
                                border: const OutlineInputBorder(),
                                filled: true,
                                fillColor: backgroundColor,
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                prefixIconConstraints:
                                    const BoxConstraints.tightFor(
                                  width: 40,
                                  height: 40,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _fieldTypeIcon(String type) => switch (type) {
        'password' || 'custom_secret' => Icons.lock_outline,
        'username' => Icons.person_outline,
        'url' => Icons.link,
        'email' => Icons.email_outlined,
        'phone' => Icons.phone_outlined,
        'date' => Icons.calendar_today_outlined,
        'number' => Icons.numbers,
        'totp' => Icons.timer_outlined,
        'multiline_note' => Icons.notes,
        _ => Icons.text_fields,
      };

  static String _fieldTypeLabel(String type) => switch (type) {
        'password' => 'Пароль',
        'custom_secret' => 'Секрет',
        'username' => 'Логин',
        'url' => 'Сайт',
        'email' => 'Email',
        'phone' => 'Телефон',
        'date' => 'Дата',
        'number' => 'Число',
        'totp' => 'TOTP',
        'multiline_note' => 'Большая строка',
        _ => 'Маленькая строка',
      };
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
        type = field.type == 'totp' ? 'url' : field.type,
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

class TemplateFieldSnapshot {
  const TemplateFieldSnapshot({
    required this.id,
    required this.label,
    required this.type,
  });

  final String id;
  final String label;
  final String type;
}

class TemplateEditorSnapshot {
  const TemplateEditorSnapshot({
    required this.name,
    required this.iconId,
    required this.colorId,
    required this.categoryPath,
    this.spbColor,
    this.customIconBase64,
    this.customIconFileName,
    required this.fields,
  });

  final String name;
  final String iconId;
  final String colorId;
  final String categoryPath;
  final int? spbColor;
  final String? customIconBase64;
  final String? customIconFileName;
  final List<TemplateFieldSnapshot> fields;

  String get signature => [
        name,
        iconId,
        colorId,
        categoryPath,
        spbColor?.toString() ?? '',
        customIconBase64 ?? '',
        customIconFileName ?? '',
        for (final field in fields)
          '${field.id}\u0001${field.label}\u0001${field.type}',
      ].join('\u0002');
}

class _TemplateEditorDialogState extends State<TemplateEditorDialog> {
  late final TextEditingController name;
  late String iconId;
  late String colorId;
  late String categoryPath;
  bool invalidName = false;
  int? spbColor;
  Uint8List? customIconBytes;
  String? customIconFileName;
  late final List<TemplateFieldDraft> fields;
  final List<TemplateEditorSnapshot> undoHistory = [];
  late String observedName;
  final Map<String, String> observedFieldLabels = {};

  Color get editorBackgroundColor => spbColor == null
      ? colorById(colorId).bg
      : Color(0xff000000 | (spbColor! & 0x00ffffff));

  @override
  void initState() {
    super.initState();
    name = TextEditingController(text: widget.initial?.name ?? '');
    final initialIconId = widget.initial?.iconId;
    iconId = initialIconId ?? spbPasswordTemplateIconAsset;
    colorId = widget.initial?.colorId ?? 'neutral';
    categoryPath = widget.initial?.categoryPath ?? '';
    spbColor = widget.initial?.spbColor;
    customIconBytes = widget.initial?.embeddedIconBase64 == null
        ? null
        : base64Decode(widget.initial!.embeddedIconBase64!);
    customIconFileName = widget.initial?.iconFileName;
    final sourceFields = widget.initial?.fields ??
        const [
          FieldDefinition(id: 'username', label: 'Логин', type: 'username'),
          FieldDefinition(
            id: 'password',
            label: 'Пароль',
            type: 'password',
            secret: true,
          ),
          FieldDefinition(
            id: 'notes',
            label: 'Заметки',
            type: 'multiline_note',
          ),
        ];
    fields = [
      for (final field in sourceFields.where(
        (field) => field.id != spbDescriptionFieldId,
      ))
        TemplateFieldDraft(field),
    ];
    observedName = name.text;
    for (final field in fields) {
      observedFieldLabels[field.id] = field.label.text;
    }
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
    final mediaQuery = MediaQuery.of(context);
    final media = mediaQuery.size;
    // Keyboard avoidance is owned by the dialog route. Keep the editor surface
    // stable and let its scroll view reveal the focused control.
    final availableHeight = media.height;
    final fullScreen = Platform.isAndroid || media.width < 700;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.zero,
      child: Align(
        alignment: Alignment.center,
        child: Material(
          color: const Color(0xfff4f4f4),
          elevation: 24,
          clipBehavior: Clip.antiAlias,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.zero,
            side: BorderSide(color: Color(0xff7f8d98)),
          ),
          child: SizedBox(
            key: const Key('templateEditorSurface'),
            width: fullScreen ? media.width : min(media.width - 24, 720),
            height:
                fullScreen ? availableHeight : max(0.0, availableHeight - 24),
            child: Column(
              children: [
                templateTitleBar(),
                Expanded(
                  child: ColoredBox(
                    color: editorBackgroundColor,
                    child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                        14,
                        14,
                        14,
                        12 + mediaQuery.viewInsets.bottom,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          templateIconPicker(),
                          const SizedBox(height: 12),
                          templateColorPicker(),
                          const SizedBox(height: 10),
                          templateNameField(),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Text(
                                'Поля',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const Spacer(),
                              TextButton.icon(
                                key: const Key('templateAddFieldButton'),
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
                ),
                templateBottomBar(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget templateTitleBar() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xffa9c9e3), Color(0xffe9f1f8)],
        ),
        border: Border(bottom: BorderSide(color: Color(0xff7f8d98))),
      ),
      child: TextField(
        key: const Key('templateTitleNameField'),
        controller: name,
        readOnly: true,
        onChanged: rememberNameChange,
        style: const TextStyle(fontSize: 18),
        decoration: const InputDecoration(
          hintText: 'Название шаблона',
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  Widget templateNameField() {
    return EnsureVisibleWhenFocused(
      child: SizedBox(
        height: 45,
        child: TextField(
          key: const Key('templateNameField'),
          controller: name,
          onChanged: (value) {
            rememberNameChange(value);
            if (invalidName) setState(() => invalidName = false);
          },
          decoration: InputDecoration(
            labelText: 'Название шаблона',
            border: const OutlineInputBorder(),
            filled: true,
            fillColor: editorBackgroundColor,
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            errorText: invalidName ? 'Название обязательно' : null,
          ),
        ),
      ),
    );
  }

  Widget templateIconPicker() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          key: const Key('templateBoundIcon'),
          width: 112,
          height: 112,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0xff82929d), width: 2),
            borderRadius: BorderRadius.circular(5),
            boxShadow: const [
              BoxShadow(
                color: Color(0x26000000),
                offset: Offset(1, 2),
                blurRadius: 5,
              ),
            ],
          ),
          child: customIconBytes == null
              ? templateIconWidget(
                  iconId,
                  size: 88,
                  color: pictogramColorForBackground(editorBackgroundColor),
                )
              : Image.memory(
                  customIconBytes!,
                  width: 88,
                  height: 88,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.medium,
                ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Выбрать иконку',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 7),
              LayoutBuilder(
                builder: (context, constraints) {
                  final buttons = [
                    templatePickerButton(
                      key: const Key('templateSpbDefaultButton'),
                      label: 'SPB',
                      icon: Icons.photo_library_outlined,
                      tooltip: 'Иконки из базы SPB',
                      onPressed: pickSpbIcon,
                    ),
                    templatePickerButton(
                      key: const Key('templatePictogramsButton'),
                      label: 'пиктограммы',
                      icon: Icons.category_outlined,
                      tooltip: 'Выбрать пиктограмму',
                      onPressed: pickPictogram,
                    ),
                    templatePickerButton(
                      key: const Key('templateIconsButton'),
                      label: 'сторонние',
                      icon: Icons.public_outlined,
                      tooltip: 'Иконки Visual Studio',
                      onPressed: pickThirdPartyIcon,
                    ),
                    templatePickerButton(
                      key: const Key('templateUploadIconButton'),
                      label: 'загрузить иконку',
                      icon: Icons.upload_file_outlined,
                      tooltip: 'Загрузить файл PNG или ICO',
                      onPressed: pickCustomIconFile,
                    ),
                  ];
                  if (constraints.maxWidth >= 420) {
                    return Row(
                      children: [
                        for (var index = 0;
                            index < buttons.length;
                            index++) ...[
                          if (index > 0) const SizedBox(width: 7),
                          Expanded(child: buttons[index]),
                        ],
                      ],
                    );
                  }
                  final width = (constraints.maxWidth - 7) / 2;
                  return Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      for (final button in buttons)
                        SizedBox(width: width, child: button),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget templatePickerButton({
    required Key key,
    required String label,
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: Opacity(
        opacity: onPressed == null ? 0.48 : 1,
        child: Material(
          key: key,
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(5),
            child: Ink(
              height: 48,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xfff4f4f4), Color(0xff969696)],
                ),
                border: Border.all(color: const Color(0xff676767)),
                borderRadius: BorderRadius.circular(5),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.white,
                    offset: Offset(-1, -1),
                    blurRadius: 0.5,
                  ),
                  BoxShadow(
                    color: Color(0x66000000),
                    offset: Offset(1, 1),
                    blurRadius: 1,
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 18, color: const Color(0xff303030)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xff303030),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget templateColorPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Цвет шаблона',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 5,
          runSpacing: 5,
          children: [
            for (final color in templateColorPalette)
              Tooltip(
                message: color.label,
                child: InkWell(
                  key: ValueKey('templateColor-${color.id}'),
                  onTap: () {
                    if (colorId == color.id) return;
                    rememberCurrentAction();
                    setState(() {
                      colorId = color.id;
                      spbColor = null;
                    });
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    width: 30,
                    height: 27,
                    decoration: BoxDecoration(
                      color: color.bg,
                      border: Border.all(
                        color: colorId == color.id
                            ? const Color(0xff253d4c)
                            : const Color(0xff8b969d),
                        width: colorId == color.id ? 2.5 : 1,
                      ),
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x1f000000),
                          offset: Offset(1, 1),
                          blurRadius: 2,
                        ),
                      ],
                    ),
                    child: colorId == color.id
                        ? const Icon(Icons.check, size: 17)
                        : null,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget templateBottomBar() {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: const BoxDecoration(
        color: Color(0xffdce8f1),
        border: Border(top: BorderSide(color: Color(0xff7f8d98))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          templateActionButton(
            key: const Key('templateUndoButton'),
            icon: Icons.undo,
            tooltip: 'Отменить последнее действие',
            colors: const [Color(0xffffdc58), Color(0xffc58a00)],
            onTap: undoHistory.isEmpty ? null : undoLastAction,
          ),
          const SizedBox(width: 6),
          templateActionButton(
            key: const Key('templateSaveButton'),
            icon: Icons.check,
            tooltip: 'Сохранить шаблон',
            colors: const [Color(0xff5bc96d), Color(0xff08772f)],
            onTap: saveTemplate,
          ),
          const SizedBox(width: 6),
          templateActionButton(
            key: const Key('templateCloseButton'),
            icon: Icons.close,
            tooltip: 'Закрыть без сохранения',
            colors: const [Color(0xffff5a5f), Color(0xffa90000)],
            onTap: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget templateActionButton({
    required Key key,
    required IconData icon,
    required String tooltip,
    required List<Color> colors,
    required VoidCallback? onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Opacity(
        opacity: onTap == null ? 0.55 : 1,
        child: Material(
          key: key,
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Ink(
              width: 38,
              height: 34,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: colors,
                ),
                border: Border.all(color: const Color(0xff56636c)),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
          ),
        ),
      ),
    );
  }

  Widget fieldEditor(TemplateFieldDraft field) {
    return EnsureVisibleWhenFocused(
      child: Card(
        key: ValueKey('templateField-${field.id}'),
        elevation: 0,
        color: editorBackgroundColor,
        surfaceTintColor: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 36,
                      child: TextField(
                        key: ValueKey('templateFieldName-${field.id}'),
                        controller: field.label,
                        onChanged: (value) =>
                            rememberFieldLabelChange(field.id, value),
                        decoration: InputDecoration(
                          labelText: 'Название поля',
                          border: const OutlineInputBorder(),
                          filled: true,
                          fillColor: editorBackgroundColor,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 7),
                  fieldMoveButtons(field),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 36,
                      child: DropdownButtonFormField<String>(
                        key: ValueKey('templateFieldType-${field.id}'),
                        initialValue: field.type,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: 'Тип',
                          border: const OutlineInputBorder(),
                          filled: true,
                          fillColor: editorBackgroundColor,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 5,
                          ),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'text',
                            child: Text('Маленькая строка'),
                          ),
                          DropdownMenuItem(
                            value: 'username',
                            child: Text('Логин'),
                          ),
                          DropdownMenuItem(
                            value: 'multiline_note',
                            child: Text('Большая строка'),
                          ),
                          DropdownMenuItem(
                            value: 'password',
                            child: Text('Пароль'),
                          ),
                          DropdownMenuItem(
                            value: 'custom_secret',
                            child: Text('Секрет'),
                          ),
                          DropdownMenuItem(
                            value: 'number',
                            child: Text('Число'),
                          ),
                          DropdownMenuItem(
                            value: 'email',
                            child: Text('Email'),
                          ),
                          DropdownMenuItem(
                            value: 'phone',
                            child: Text('Телефон'),
                          ),
                          DropdownMenuItem(value: 'date', child: Text('Дата')),
                          DropdownMenuItem(value: 'url', child: Text('WEB')),
                        ],
                        onChanged: (value) {
                          rememberCurrentAction();
                          setState(() => field.type = value ?? 'text');
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 7),
                  fieldMoveButton(
                    key: ValueKey('templateFieldDelete-${field.id}'),
                    tooltip: 'Удалить поле',
                    icon: Icons.delete_outline,
                    height: 36,
                    onTap: fields.length <= 1 ? null : () => removeField(field),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget fieldMoveButtons(TemplateFieldDraft field) {
    final index = fields.indexOf(field);
    return SizedBox(
      width: 31,
      height: 36,
      child: Column(
        children: [
          fieldMoveButton(
            key: ValueKey('templateFieldUp-${field.id}'),
            icon: Icons.keyboard_arrow_up,
            tooltip: 'Переместить поле вверх',
            onTap: index > 0 ? () => moveField(field, -1) : null,
          ),
          const SizedBox(height: 2),
          fieldMoveButton(
            key: ValueKey('templateFieldDown-${field.id}'),
            icon: Icons.keyboard_arrow_down,
            tooltip: 'Переместить поле вниз',
            onTap: index < fields.length - 1 ? () => moveField(field, 1) : null,
          ),
        ],
      ),
    );
  }

  Widget fieldMoveButton({
    required Key key,
    required IconData icon,
    required String tooltip,
    required VoidCallback? onTap,
    double height = 17,
  }) {
    return Tooltip(
      message: tooltip,
      child: Opacity(
        opacity: onTap == null ? 0.45 : 1,
        child: Material(
          key: key,
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(3),
            child: Ink(
              width: 31,
              height: height,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xfff4f4f4), Color(0xff8d8d8d)],
                ),
                border: Border.all(color: const Color(0xff676767)),
                borderRadius: BorderRadius.circular(3),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.white,
                    offset: Offset(-1, -1),
                    blurRadius: 0.5,
                  ),
                  BoxShadow(
                    color: Color(0x66000000),
                    offset: Offset(1, 1),
                    blurRadius: 1,
                  ),
                ],
              ),
              child: Icon(icon, size: 19, color: const Color(0xff303030)),
            ),
          ),
        ),
      ),
    );
  }

  void addField() {
    rememberCurrentAction();
    setState(() {
      final field = TemplateFieldDraft(
        FieldDefinition(id: makeId('field'), label: 'Новое поле', type: 'text'),
      );
      fields.add(field);
      observedFieldLabels[field.id] = field.label.text;
    });
  }

  void removeField(TemplateFieldDraft field) {
    rememberCurrentAction();
    setState(() {
      fields.remove(field);
      observedFieldLabels.remove(field.id);
      field.dispose();
    });
  }

  void moveField(TemplateFieldDraft field, int offset) {
    final oldIndex = fields.indexOf(field);
    final newIndex = oldIndex + offset;
    if (oldIndex < 0 || newIndex < 0 || newIndex >= fields.length) return;
    rememberCurrentAction();
    setState(() {
      fields.removeAt(oldIndex);
      fields.insert(newIndex, field);
    });
  }

  TemplateEditorSnapshot currentSnapshot({
    String? nameOverride,
    String? fieldIdOverride,
    String? fieldLabelOverride,
  }) =>
      TemplateEditorSnapshot(
        name: nameOverride ?? name.text,
        iconId: iconId,
        colorId: colorId,
        categoryPath: categoryPath,
        spbColor: spbColor,
        customIconBase64:
            customIconBytes == null ? null : base64Encode(customIconBytes!),
        customIconFileName: customIconFileName,
        fields: [
          for (final field in fields)
            TemplateFieldSnapshot(
              id: field.id,
              label: field.id == fieldIdOverride
                  ? fieldLabelOverride ?? field.label.text
                  : field.label.text,
              type: field.type,
            ),
        ],
      );

  void rememberCurrentAction() {
    rememberSnapshot(currentSnapshot());
  }

  void rememberNameChange(String value) {
    if (value == observedName) return;
    rememberSnapshot(currentSnapshot(nameOverride: observedName));
    observedName = value;
  }

  void rememberFieldLabelChange(String fieldId, String value) {
    final previous = observedFieldLabels[fieldId] ?? '';
    if (value == previous) return;
    rememberSnapshot(
      currentSnapshot(fieldIdOverride: fieldId, fieldLabelOverride: previous),
    );
    observedFieldLabels[fieldId] = value;
  }

  void rememberSnapshot(TemplateEditorSnapshot snapshot) {
    if (undoHistory.isNotEmpty &&
        undoHistory.last.signature == snapshot.signature) {
      return;
    }
    setState(() {
      undoHistory.add(snapshot);
      if (undoHistory.length > 200) undoHistory.removeAt(0);
    });
  }

  void undoLastAction() {
    if (undoHistory.isEmpty) return;
    final snapshot = undoHistory.removeLast();
    setState(() {
      name.text = snapshot.name;
      iconId = snapshot.iconId;
      colorId = snapshot.colorId;
      categoryPath = snapshot.categoryPath;
      spbColor = snapshot.spbColor;
      customIconBytes = snapshot.customIconBase64 == null
          ? null
          : base64Decode(snapshot.customIconBase64!);
      customIconFileName = snapshot.customIconFileName;
      for (final field in fields) {
        field.dispose();
      }
      fields
        ..clear()
        ..addAll(
          snapshot.fields.map(
            (field) => TemplateFieldDraft(
              FieldDefinition(
                id: field.id,
                label: field.label,
                type: field.type,
                secret: fieldTypeIsSecret(field.type),
              ),
            ),
          ),
        );
      observedName = snapshot.name;
      observedFieldLabels
        ..clear()
        ..addEntries(
          snapshot.fields.map((field) => MapEntry(field.id, field.label)),
        );
    });
  }

  void changeIcon(String selectedIconId) {
    if (selectedIconId == iconId) return;
    rememberCurrentAction();
    setState(() {
      iconId = selectedIconId;
      customIconBytes = null;
      customIconFileName = null;
    });
  }

  Future<void> pickPictogram() async {
    final picked = await showIconPickerDialog(context, iconId);
    if (picked != null && mounted) changeIcon(picked);
  }

  Future<void> pickSpbIcon() async {
    final picked = await showSpbOriginalIconPickerDialog(context, iconId);
    if (picked != null && mounted) changeIcon(picked);
  }

  Future<void> pickThirdPartyIcon() async {
    final picked = await showThirdPartyIconPickerDialog(context);
    if (picked == null || !mounted) return;
    final bytes = thirdPartyIconPngs[picked];
    if (bytes == null) return;
    applyCustomIcon(bytes, picked.split('/').last);
  }

  Future<void> pickCustomIconFile() async {
    final picked = await pickUserIconFile(context);
    if (picked == null || !mounted) return;
    applyCustomIcon(picked.bytes, picked.fileName);
  }

  void applyCustomIcon(Uint8List pngBytes, String fileName) {
    rememberCurrentAction();
    setState(() {
      iconId = SpbWalletDatabase.makeId();
      customIconBytes = pngBytes;
      customIconFileName = fileName;
    });
  }

  void saveTemplate() {
    if (name.text.trim().isEmpty) {
      setState(() => invalidName = true);
      return;
    }
    Navigator.pop(
      context,
      CardTemplate(
        id: widget.initial?.id ?? makeId('tpl'),
        name: name.text.trim().isEmpty ? 'Новый шаблон' : name.text.trim(),
        iconId: iconId,
        colorId: colorId,
        categoryPath: categoryPath,
        spbColor: spbColor,
        builtIn: widget.initial?.builtIn ?? false,
        embeddedIconBase64:
            customIconBytes == null ? null : base64Encode(customIconBytes!),
        iconFileName: customIconFileName,
        fields: fields.map((field) => field.toField()).toList(),
      ),
    );
  }
}
