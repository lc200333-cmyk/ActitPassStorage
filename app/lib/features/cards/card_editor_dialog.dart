part of '../../main.dart';

class CardEditorSnapshot {
  const CardEditorSnapshot({
    required this.templateId,
    required this.colorId,
    required this.categorySelection,
    required this.iconId,
    required this.title,
    required this.category,
    required this.values,
    required this.fieldOrder,
    required this.hiddenFieldIds,
    required this.attachments,
    this.backgroundImageBase64,
    this.spbColor,
  });

  final String templateId;
  final String colorId;
  final String categorySelection;
  final String iconId;
  final String title;
  final String category;
  final Map<String, String> values;
  final List<String> fieldOrder;
  final Set<String> hiddenFieldIds;
  final List<SecretAttachment> attachments;
  final String? backgroundImageBase64;
  final int? spbColor;

  String get signature => [
        templateId,
        colorId,
        categorySelection,
        iconId,
        title,
        category,
        backgroundImageBase64 ?? '',
        spbColor?.toString() ?? '',
        fieldOrder.join('\u0001'),
        (hiddenFieldIds.toList()..sort()).join('\u0001'),
        for (final entry in values.entries) '${entry.key}\u0001${entry.value}',
        for (final entry in attachments)
          '${entry.id}\u0001${entry.fileName}\u0001${entry.size}\u0001${entry.deleted}',
      ].join('\u0002');
}

class ItemEditorDialog extends StatefulWidget {
  const ItemEditorDialog({
    required this.templates,
    required this.categories,
    this.initial,
    this.initialCategory,
    this.supportsAttachments = false,
    this.loadAttachmentBytes,
    super.key,
  });

  final List<CardTemplate> templates;
  final List<String> categories;
  final SecretItem? initial;
  final String? initialCategory;
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
  late final DateTime editorOpenedAt;
  late final TextEditingController title;
  late final TextEditingController category;
  late final Map<String, TextEditingController> values;
  late List<String> fieldOrder;
  late Set<String> hiddenFieldIds;
  late List<SecretAttachment> attachments;
  String? backgroundImageBase64;
  int? spbColor;
  final Set<String> visibleSecrets = {};
  final List<CardEditorSnapshot> undoHistory = [];
  final Map<String, Future<Uint8List>> attachmentByteLoads = {};
  String? cachedBackgroundBase64;
  ImageProvider? cachedBackgroundImage;

  Color get editorBackgroundColor => spbColor == null
      ? colorById(colorId).bg
      : Color(0xff000000 | (spbColor! & 0x00ffffff));

  ImageProvider? get editorBackgroundImage {
    final encoded = backgroundImageBase64;
    if (encoded == cachedBackgroundBase64) return cachedBackgroundImage;
    cachedBackgroundBase64 = encoded;
    if (encoded == null || encoded.isEmpty) {
      return cachedBackgroundImage = null;
    }
    try {
      return cachedBackgroundImage = MemoryImage(base64Decode(encoded));
    } catch (_) {
      return cachedBackgroundImage = null;
    }
  }

  CardTemplate get template =>
      widget.templates.firstWhere((entry) => entry.id == templateId);

  List<FieldDefinition> get allCardFields {
    final result = <FieldDefinition>[...template.fields];
    final known = result.map((field) => field.id).toSet();
    for (final id in widget.initial?.values.keys ?? const <String>[]) {
      if (known.add(id)) {
        result.add(
          FieldDefinition(
            id: id,
            label:
                'Сохранённое поле ${id.length > 8 ? id.substring(0, 8) : id}',
            type: 'text',
          ),
        );
      }
    }
    return result;
  }

  @override
  void initState() {
    super.initState();
    editorOpenedAt = DateTime.now();
    templateId = widget.initial?.templateId ?? widget.templates.first.id;
    colorId = widget.initial?.colorId ?? template.colorId;
    iconId = widget.initial?.iconId ?? template.iconId;
    title = TextEditingController(text: widget.initial?.title ?? '');
    final initialCategory =
        widget.initial?.category.trim() ?? widget.initialCategory?.trim() ?? '';
    category = TextEditingController(text: initialCategory);
    categorySelection = initialCategory.isEmpty
        ? emptyCategoryValue
        : widget.categories.contains(initialCategory)
            ? initialCategory
            : newCategoryValue;
    values = {
      for (final field in allCardFields)
        field.id: TextEditingController(
          text: widget.initial?.values[field.id] ??
              (field.type == 'url' ? 'http://www' : ''),
        ),
    };
    hiddenFieldIds = {...?widget.initial?.hiddenFieldIds};
    final availableIds = allCardFields.map((field) => field.id).toSet();
    fieldOrder = [
      for (final id in widget.initial?.fieldOrder ?? const <String>[])
        if (availableIds.contains(id) && !hiddenFieldIds.contains(id)) id,
      for (final field in allCardFields)
        if (!(widget.initial?.fieldOrder.contains(field.id) ?? false) &&
            !hiddenFieldIds.contains(field.id))
          field.id,
    ];
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

  CardEditorSnapshot currentSnapshot() => CardEditorSnapshot(
        templateId: templateId,
        colorId: colorId,
        categorySelection: categorySelection,
        iconId: iconId,
        title: title.text,
        category: category.text,
        values: {
          for (final entry in values.entries) entry.key: entry.value.text
        },
        fieldOrder: [...fieldOrder],
        hiddenFieldIds: {...hiddenFieldIds},
        attachments: [...attachments],
        backgroundImageBase64: backgroundImageBase64,
        spbColor: spbColor,
      );

  void rememberCurrentAction() {
    final snapshot = currentSnapshot();
    if (undoHistory.isNotEmpty &&
        undoHistory.last.signature == snapshot.signature) {
      return;
    }
    setState(() {
      undoHistory.add(snapshot);
      if (undoHistory.length > 100) undoHistory.removeAt(0);
    });
  }

  void undoLastAction() {
    if (undoHistory.isEmpty) return;
    final snapshot = undoHistory.removeLast();
    setState(() {
      templateId = snapshot.templateId;
      colorId = snapshot.colorId;
      categorySelection = snapshot.categorySelection;
      iconId = snapshot.iconId;
      title.text = snapshot.title;
      category.text = snapshot.category;
      for (final entry in values.entries) {
        entry.value.text = snapshot.values[entry.key] ?? '';
      }
      for (final entry in snapshot.values.entries) {
        values.putIfAbsent(
          entry.key,
          () => TextEditingController(text: entry.value),
        );
      }
      fieldOrder = [...snapshot.fieldOrder];
      hiddenFieldIds = {...snapshot.hiddenFieldIds};
      attachments = [...snapshot.attachments];
      backgroundImageBase64 = snapshot.backgroundImageBase64;
      spbColor = snapshot.spbColor;
    });
  }

  Widget cardIconPickers() {
    final buttons = [
      SpbGrayPickerButton(
        key: const Key('spbCardIconPicker'),
        label: 'SPB',
        icon: Icons.photo_library_outlined,
        tooltip: 'Иконки из базы SPB',
        onTap: pickSpbCardIcon,
      ),
      SpbGrayPickerButton(
        key: const Key('cardPictogramPicker'),
        label: 'пиктограммы',
        icon: Icons.category_outlined,
        tooltip: 'Выбрать пиктограмму',
        onTap: pickCardPictogram,
      ),
      SpbGrayPickerButton(
        key: const Key('cardThirdPartyPicker'),
        label: 'сторонние',
        icon: Icons.public_outlined,
        tooltip: 'Иконки Visual Studio',
        onTap: pickCardThirdPartyIcon,
      ),
      SpbGrayPickerButton(
        key: const Key('cardUploadIconButton'),
        label: 'загрузить иконку',
        icon: Icons.upload_file_outlined,
        tooltip: 'Загрузить файл PNG или ICO',
        onTap: pickCardCustomIconFile,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 420) {
          return Row(
            children: [
              for (var index = 0; index < buttons.length; index++) ...[
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
            for (final button in buttons) SizedBox(width: width, child: button),
          ],
        );
      },
    );
  }

  Future<void> pickSpbCardIcon() async {
    final picked = await showSpbOriginalIconPickerDialog(context, iconId);
    if (picked == null || !mounted) return;
    rememberCurrentAction();
    setState(() => iconId = picked);
  }

  Future<void> pickCardPictogram() async {
    final picked = await showIconPickerDialog(context, iconId);
    if (picked == null || !mounted) return;
    rememberCurrentAction();
    setState(() => iconId = picked);
  }

  Future<void> pickCardThirdPartyIcon() async {
    final picked = await showThirdPartyIconPickerDialog(context);
    if (picked == null || !mounted) return;
    final bytes = thirdPartyIconPngs[picked];
    if (bytes == null) return;
    rememberCurrentAction();
    setState(() => iconId = registerEmbeddedIcon(bytes));
  }

  Future<void> pickCardCustomIconFile() async {
    final picked = await pickUserIconFile(context);
    if (picked == null || !mounted) return;
    rememberCurrentAction();
    setState(() => iconId = registerEmbeddedIcon(picked.bytes));
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
            key: const Key('cardEditorSurface'),
            width: fullScreen ? media.width : min(media.width - 24, 720),
            height: fullScreen
                ? availableHeight
                : min(max(0.0, availableHeight - 24), 760),
            child: Column(
              children: [
                Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xffa9c9e3), Color(0xffe9f1f8)],
                    ),
                    border: Border(
                      bottom: BorderSide(color: Color(0xff7f8d98)),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          title.text.trim().isEmpty
                              ? (widget.initial == null
                                  ? 'Новая карточка'
                                  : 'Редактировать карточку')
                              : title.text,
                          key: const Key('cardWindowTitle'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 18),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        formatCardModifiedAt(
                          widget.initial?.modifiedAt ?? editorOpenedAt,
                        ),
                        key: const Key('cardEditorModifiedAt'),
                        maxLines: 1,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: DecoratedBox(
                    decoration: cardSurfaceDecoration(
                      color: editorBackgroundColor,
                      backgroundImage: editorBackgroundImage,
                    ),
                    child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                        14,
                        14,
                        14,
                        18 + mediaQuery.viewInsets.bottom,
                      ),
                      child: buildCardEditorContent(),
                    ),
                  ),
                ),
                Container(
                  height: 64,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: const BoxDecoration(
                    color: Color(0xffdce8f1),
                    border: Border(top: BorderSide(color: Color(0xff7f8d98))),
                  ),
                  child: Row(
                    children: [
                      if (widget.supportsAttachments) ...[
                        if (activeAttachments.isNotEmpty) ...[
                          SpbGradientActionButton(
                            key: const Key('cardEditorSaveAttachmentButton'),
                            icon: Icons.folder_outlined,
                            tooltip: 'Сохранить вложение',
                            colors: const [
                              Color(0xff555555),
                              Color(0xff050505),
                            ],
                            onTap: chooseAttachmentToExport,
                          ),
                          const SizedBox(width: 6),
                        ],
                        SpbGradientActionButton(
                          key: const Key('cardEditorAddAttachmentButton'),
                          icon: Icons.add,
                          tooltip: 'Загрузить вложение',
                          colors: const [Color(0xff5b9dff), Color(0xff0752b5)],
                          onTap: addAttachment,
                        ),
                        if (activeAttachments.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          SpbGradientActionButton(
                            key: const Key('cardEditorDeleteAttachmentButton'),
                            icon: Icons.delete,
                            tooltip: 'Удалить вложение',
                            colors: const [
                              Color(0xffff5a5f),
                              Color(0xffa90000),
                            ],
                            onTap: chooseAttachmentToDelete,
                          ),
                        ],
                      ],
                      const Spacer(),
                      SpbGradientActionButton(
                        key: const Key('cardUndoButton'),
                        icon: Icons.undo,
                        tooltip: 'Отменить последнее действие',
                        colors: const [Color(0xffffdc58), Color(0xffc58a00)],
                        onTap: undoHistory.isEmpty ? null : undoLastAction,
                      ),
                      const SizedBox(width: 6),
                      SpbGradientActionButton(
                        key: const Key('cardSaveButton'),
                        icon: Icons.check,
                        tooltip: 'Сохранить карточку',
                        colors: const [Color(0xff5bc96d), Color(0xff08772f)],
                        onTap: saveCard,
                      ),
                      const SizedBox(width: 6),
                      SpbGradientActionButton(
                        key: const Key('cardCloseButton'),
                        icon: Icons.close,
                        tooltip: 'Закрыть без сохранения',
                        colors: const [Color(0xffff5a5f), Color(0xffa90000)],
                        onTap: () => Navigator.pop(context),
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
  }

  Widget buildCardEditorContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              key: const Key('cardBoundIcon'),
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
              child: templateIconWidget(
                iconId,
                size: 88,
                color: pictogramColorForBackground(editorBackgroundColor),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(child: cardIconPickers()),
          ],
        ),
        const SizedBox(height: 12),
        ColorPicker(
          value: colorId,
          onChanged: (value) {
            if (value == colorId) return;
            rememberCurrentAction();
            setState(() {
              colorId = value;
              spbColor = paletteColorToSpb(value);
            });
          },
        ),
        const SizedBox(height: 10),
        EnsureVisibleWhenFocused(
          child: SizedBox(
            height: 45,
            child: TextField(
              key: const Key('cardTitleField'),
              controller: title,
              onTap: rememberCurrentAction,
              contextMenuBuilder: usesDesktopCardTextControls
                  ? desktopCardTextContextMenu
                  : null,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Название карточки',
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 45,
          child: DropdownButtonFormField<String>(
            key: const Key('cardTemplateField'),
            isExpanded: true,
            initialValue: templateId,
            decoration: const InputDecoration(
              labelText: 'Название шаблона',
              border: OutlineInputBorder(),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            ),
            items: widget.templates
                .map(
                  (entry) => DropdownMenuItem(
                    value: entry.id,
                    child: cardTemplateMenuLabel(entry),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value == null || value == templateId) return;
              rememberCurrentAction();
              setState(() {
                templateId = value;
                if (widget.initial == null || widget.initial?.iconId == null) {
                  iconId = template.iconId;
                }
                for (final field in template.fields) {
                  values.putIfAbsent(
                    field.id,
                    () => TextEditingController(
                      text: widget.initial?.values[field.id] ?? '',
                    ),
                  );
                }
                hiddenFieldIds = {};
                fieldOrder = [for (final field in template.fields) field.id];
              });
            },
          ),
        ),
        const SizedBox(height: 10),
        categoryEditor(),
        const SizedBox(height: 10),
        for (final field in orderedCardFields)
          EnsureVisibleWhenFocused(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: buildCardValueField(field),
            ),
          ),
        if (widget.supportsAttachments) buildCardAttachmentsEditor(),
      ],
    );
  }

  List<FieldDefinition> get orderedCardFields {
    final ordered = [
      for (final id in fieldOrder)
        for (final field in allCardFields)
          if (field.id == id) field,
    ];
    return [
      ...ordered.where((field) => field.type != 'multiline_note'),
      ...ordered.where((field) => field.type == 'multiline_note'),
    ];
  }

  Widget cardTemplateMenuLabel(CardTemplate entry) {
    return Row(
      children: [
        Container(
          key: ValueKey('cardTemplateIcon-${entry.id}'),
          width: 42,
          height: 42,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0xff82929d)),
          ),
          child: FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(
              width: 64,
              height: 64,
              child: Center(
                child: templateIconWidget(
                  entry.iconId,
                  size: 60,
                  color: templateDisplayPictogramColor(entry),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }

  Widget buildCardValueField(FieldDefinition field) {
    final controller = values.putIfAbsent(
      field.id,
      () => TextEditingController(),
    );
    final visible = visibleSecrets.contains(field.id);
    final index = fieldOrder.indexOf(field.id);
    final multiline = field.type == 'multiline_note';
    final textField = TextField(
      key: ValueKey('cardField-${field.id}'),
      controller: controller,
      onTap: rememberCurrentAction,
      contextMenuBuilder:
          usesDesktopCardTextControls ? desktopCardTextContextMenu : null,
      obscureText: fieldDefinitionIsSecret(field) && !visible,
      keyboardType:
          multiline ? TextInputType.multiline : keyboardTypeForField(field),
      textInputAction:
          multiline ? TextInputAction.newline : TextInputAction.next,
      inputFormatters: inputFormattersForField(field),
      minLines: multiline ? null : 1,
      maxLines: multiline ? null : 1,
      expands: multiline,
      scrollPadding: const EdgeInsets.only(bottom: 140),
      decoration: InputDecoration(
        labelText: '${field.label}${field.required ? ' *' : ''}',
        hintText: hintTextForField(field),
        border: const OutlineInputBorder(),
        filled: true,
        fillColor: editorBackgroundColor,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        suffixIcon: fieldSuffixIcon(field, controller, visible),
      ),
    );

    if (multiline) {
      return SizedBox(
        height: 180,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: textField),
            const SizedBox(width: 5),
            SizedBox(
              width: 73,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 34,
                        height: 34,
                        child: fieldOrderButton(
                          key: ValueKey('cardFieldUp-${field.id}'),
                          icon: Icons.keyboard_arrow_up,
                          tooltip: 'Переместить поле вверх',
                          onTap: index > 0
                              ? () => moveCardField(field.id, -1)
                              : null,
                        ),
                      ),
                      const SizedBox(width: 5),
                      SizedBox(
                        width: 34,
                        height: 34,
                        child: fieldOrderButton(
                          key: ValueKey('cardFieldDelete-${field.id}'),
                          icon: Icons.delete_outline,
                          tooltip: 'Удалить поле из списка',
                          onTap: () => removeCardField(field.id),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  SizedBox(
                    width: 34,
                    height: 34,
                    child: fieldOrderButton(
                      key: ValueKey('cardFieldDown-${field.id}'),
                      icon: Icons.keyboard_arrow_down,
                      tooltip: 'Переместить поле вниз',
                      onTap: index >= 0 && index < fieldOrder.length - 1
                          ? () => moveCardField(field.id, 1)
                          : null,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: SizedBox(height: 45, child: textField)),
          const SizedBox(width: 5),
          SizedBox(
            width: 34,
            child: Column(
              children: [
                fieldOrderButton(
                  key: ValueKey('cardFieldUp-${field.id}'),
                  icon: Icons.keyboard_arrow_up,
                  tooltip: 'Переместить поле вверх',
                  onTap: index > 0 ? () => moveCardField(field.id, -1) : null,
                  expanded: true,
                ),
                const SizedBox(height: 3),
                fieldOrderButton(
                  key: ValueKey('cardFieldDown-${field.id}'),
                  icon: Icons.keyboard_arrow_down,
                  tooltip: 'Переместить поле вниз',
                  onTap: index >= 0 && index < fieldOrder.length - 1
                      ? () => moveCardField(field.id, 1)
                      : null,
                  expanded: true,
                ),
              ],
            ),
          ),
          const SizedBox(width: 5),
          SizedBox(
            width: 38,
            child: fieldOrderButton(
              key: ValueKey('cardFieldDelete-${field.id}'),
              icon: Icons.delete_outline,
              tooltip: 'Удалить поле из списка',
              onTap: () => removeCardField(field.id),
            ),
          ),
        ],
      ),
    );
  }

  Widget fieldOrderButton({
    required Key key,
    required IconData icon,
    required String tooltip,
    required VoidCallback? onTap,
    bool expanded = false,
  }) {
    final button = Tooltip(
      message: tooltip,
      child: Opacity(
        opacity: onTap == null ? 0.45 : 1,
        child: Material(
          key: key,
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Ink(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xfff4f4f4), Color(0xff969696)],
                ),
                border: Border.all(color: const Color(0xff676767)),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Center(
                child: Icon(icon, size: 19, color: const Color(0xff303030)),
              ),
            ),
          ),
        ),
      ),
    );
    return expanded ? Expanded(child: button) : button;
  }

  void moveCardField(String fieldId, int offset) {
    final oldIndex = fieldOrder.indexOf(fieldId);
    final newIndex = oldIndex + offset;
    if (oldIndex < 0 || newIndex < 0 || newIndex >= fieldOrder.length) return;
    rememberCurrentAction();
    setState(() {
      fieldOrder.removeAt(oldIndex);
      fieldOrder.insert(newIndex, fieldId);
    });
  }

  void removeCardField(String fieldId) {
    if (!fieldOrder.contains(fieldId)) return;
    rememberCurrentAction();
    setState(() {
      fieldOrder.remove(fieldId);
      hiddenFieldIds.add(fieldId);
    });
  }

  Widget buildCardAttachmentsEditor() {
    final active = activeAttachments;
    if (active.isEmpty) return const SizedBox.shrink();
    final files = active.where(
      (attachment) => !isEditorInlineImage(attachment.fileName),
    );
    final images = active.where(
      (attachment) => isEditorInlineImage(attachment.fileName),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final attachment in files)
          Material(
            key: ValueKey('cardEditorAttachment-${attachment.fileName}'),
            color: Colors.transparent,
            child: InkWell(
              onTap: () => previewEditorAttachment(attachment),
              onSecondaryTap: () => previewEditorAttachment(attachment),
              onLongPress: () => previewEditorAttachment(attachment),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: [
                    const Icon(Icons.attach_file, size: 19),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        attachment.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        for (final attachment in images)
          editorInlineImageAttachment(attachment),
      ],
    );
  }

  bool isEditorInlineImage(String fileName) {
    final lower = fileName.toLowerCase();
    return const [
      '.png',
      '.jpg',
      '.jpeg',
      '.gif',
      '.webp',
      '.bmp',
    ].any(lower.endsWith);
  }

  Widget editorInlineImageAttachment(SecretAttachment attachment) {
    return FutureBuilder<Uint8List>(
      future: editorAttachmentBytes(attachment),
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        return Padding(
          key: ValueKey('cardEditorInlineAttachment-${attachment.fileName}'),
          padding: const EdgeInsets.only(top: 10),
          child: Material(
            color: editorBackgroundColor.withValues(alpha: 0.9),
            shape: RoundedRectangleBorder(
              side: const BorderSide(color: Color(0xff82929d)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: InkWell(
              onTap: () => previewEditorAttachment(attachment),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      attachment.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (bytes == null)
                      const SizedBox(
                        height: 72,
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 320),
                        child: Image.memory(
                          bytes,
                          width: double.infinity,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const SizedBox(
                            height: 72,
                            child: Center(
                              child: Icon(Icons.broken_image_outlined),
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
      },
    );
  }

  void saveCard() {
    Navigator.pop(
      context,
      SecretItem(
        id: widget.initial?.id ?? makeId('item'),
        templateId: templateId,
        title: title.text.trim().isEmpty ? template.name : title.text.trim(),
        category: category.text.trim(),
        colorId: colorId,
        values: {
          for (final field in allCardFields)
            field.id: field.type == 'url'
                ? normalizeUrlInput(values[field.id]?.text ?? '')
                : (values[field.id]?.text.trim() ?? ''),
        },
        attachments: attachments,
        modifiedAt: DateTime.now().toUtc(),
        hitCount: widget.initial?.hitCount ?? 0,
        iconId: iconId,
        backgroundImageBase64: backgroundImageBase64,
        spbColor: spbColor,
        fieldOrder: fieldOrder,
        hiddenFieldIds: hiddenFieldIds,
      ),
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
        SizedBox(
          height: 45,
          child: DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: selectedValue,
            decoration: const InputDecoration(
              labelText: 'Папка / каталог',
              hintText: 'Место размещения карточки',
              border: OutlineInputBorder(),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 7),
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
            onChanged: (value) {
              rememberCurrentAction();
              setState(() {
                categorySelection = value ?? emptyCategoryValue;
                if (categorySelection == emptyCategoryValue) {
                  category.clear();
                } else if (categorySelection != newCategoryValue) {
                  category.text = categorySelection;
                }
              });
            },
          ),
        ),
        if (selectedValue == newCategoryValue) ...[
          const SizedBox(height: 10),
          SizedBox(
            height: 45,
            child: TextField(
              controller: category,
              onTap: rememberCurrentAction,
              contextMenuBuilder: usesDesktopCardTextControls
                  ? desktopCardTextContextMenu
                  : null,
              decoration: const InputDecoration(
                labelText: 'Новая папка / каталог',
                hintText: 'Например: Финансы / Банк',
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
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
    rememberCurrentAction();
    setState(() => controller.text = formatDateInput(picked));
  }

  List<SecretAttachment> get activeAttachments => attachments
      .where(
        (attachment) => !attachment.deleted && attachment.decodeError == null,
      )
      .toList(growable: false);

  String attachmentCacheKey(SecretAttachment attachment) => attachment
          .id.isNotEmpty
      ? '${attachment.id}:${identityHashCode(attachment.pendingBytes)}:${attachment.size}'
      : 'pending:${identityHashCode(attachment.pendingBytes)}:${attachment.size}';

  Future<Uint8List> editorAttachmentBytes(SecretAttachment attachment) =>
      attachmentByteLoads.putIfAbsent(attachmentCacheKey(attachment), () async {
        if (attachment.pendingBytes != null) {
          return Uint8List.fromList(attachment.pendingBytes!);
        }
        final loader = widget.loadAttachmentBytes;
        if (loader == null || attachment.id.isEmpty) return Uint8List(0);
        return Uint8List.fromList(await loader(attachment.id));
      });

  Future<void> previewEditorAttachment(SecretAttachment attachment) async {
    try {
      final bytes = await editorAttachmentBytes(attachment);
      if (bytes.isEmpty) return;
      await openAttachmentBytesWithSystem(attachment.fileName, bytes);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось открыть вложение: $error')),
      );
    }
  }

  Future<SecretAttachment?> chooseEditorAttachment(String titleText) async {
    final source = activeAttachments;
    if (source.isEmpty) return null;
    if (source.length == 1) return source.single;
    return showDialog<SecretAttachment>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(titleText),
        children: [
          for (final attachment in source)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, attachment),
              child: Text(attachment.fileName),
            ),
        ],
      ),
    );
  }

  Future<void> chooseAttachmentToExport() async {
    final selected = await chooseEditorAttachment('Сохранить вложение');
    if (selected != null) await exportAttachment(selected);
  }

  Future<void> chooseAttachmentToDelete() async {
    final selected = await chooseEditorAttachment('Удалить вложение');
    if (selected == null || !mounted) return;
    rememberCurrentAction();
    setState(() {
      attachments = [
        for (final attachment in attachments)
          if (identical(attachment, selected))
            attachment.copyWith(deleted: true)
          else
            attachment,
      ];
    });
  }

  Future<void> addAttachment() async {
    final picked = await FilePicker.platform.pickFiles(withData: true);
    final file = picked?.files.single;
    if (file == null) return;
    final bytes = file.bytes ??
        (file.path == null ? null : await File(file.path!).readAsBytes());
    if (bytes == null) return;
    rememberCurrentAction();
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
    rememberCurrentAction();
    setState(() => backgroundImageBase64 = base64Encode(bytes));
  }

  Future<void> replaceAttachment(SecretAttachment attachment) async {
    final picked = await FilePicker.platform.pickFiles(withData: true);
    final file = picked?.files.single;
    if (file == null) return;
    final bytes = file.bytes ??
        (file.path == null ? null : await File(file.path!).readAsBytes());
    if (bytes == null) return;
    rememberCurrentAction();
    setState(() {
      attachments = attachments
          .map(
            (entry) => entry.id == attachment.id
                ? entry.copyWith(
                    fileName: file.name,
                    size: bytes.length,
                    decodeError: null,
                    pendingBytes: bytes,
                  )
                : entry,
          )
          .toList();
    });
  }

  Future<void> exportAttachment(SecretAttachment attachment) async {
    try {
      final data = await editorAttachmentBytes(attachment);
      if (data.isEmpty) return;
      final export = gallerySafeAttachmentExport(attachment.fileName, data);
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Сохранить вложение',
        fileName: export.fileName,
        bytes: export.bytes,
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
