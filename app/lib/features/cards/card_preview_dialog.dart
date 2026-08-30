part of '../../main.dart';

enum CardPreviewAction { back, edit, delete }

class CardPreviewDialog extends StatefulWidget {
  const CardPreviewDialog({
    required this.item,
    required this.template,
    this.loadAttachmentBytes,
    this.onAddAttachment,
    super.key,
  });

  final SecretItem item;
  final CardTemplate template;
  final Future<List<int>> Function(String attachmentId)? loadAttachmentBytes;
  final Future<SecretItem?> Function(SecretItem item)? onAddAttachment;

  @override
  State<CardPreviewDialog> createState() => _CardPreviewDialogState();
}

class _CardPreviewDialogState extends State<CardPreviewDialog> {
  final Set<String> revealedFields = {};
  final Map<String, Future<Uint8List>> attachmentByteLoads = {};
  late SecretItem currentItem;
  ImageProvider? cachedBackgroundImage;

  ImageProvider? decodeBackgroundImage(String? encoded) {
    if (encoded == null || encoded.isEmpty) return null;
    try {
      return MemoryImage(base64Decode(encoded));
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    currentItem = widget.item;
    cachedBackgroundImage = decodeBackgroundImage(
      currentItem.backgroundImageBase64,
    );
  }

  String allCardText() {
    final lines = <String>[
      'Название:',
      currentItem.title,
      if (currentItem.category.trim().isNotEmpty) ...[
        'Категория:',
        currentItem.category,
      ],
    ];
    for (final field in fieldsForItem(widget.template, currentItem)) {
      final value = currentItem.values[field.id]?.trim() ?? '';
      if (value.isNotEmpty) lines.addAll(['${field.label}:', value]);
    }
    return lines.join('\n');
  }

  bool pointIsInsidePreviewTextField(Offset globalPosition) {
    var inside = false;
    void visit(Element element) {
      if (inside) return;
      if (element.widget is EditableText) {
        final renderObject = element.renderObject;
        if (renderObject is RenderBox && renderObject.hasSize) {
          final bounds =
              renderObject.localToGlobal(Offset.zero) & renderObject.size;
          inside = bounds.contains(globalPosition);
        }
      }
      if (!inside) element.visitChildren(visit);
    }

    (context as Element).visitChildren(visit);
    return inside;
  }

  void handlePreviewPointerDown(PointerDownEvent event) {
    if (event.buttons & kSecondaryMouseButton == 0 ||
        pointIsInsidePreviewTextField(event.position)) {
      return;
    }
    showCopyAllMenu(event.position);
  }

  Future<void> showCopyAllMenu(Offset globalPosition) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 1, 1),
        Offset.zero & overlay.size,
      ),
      items: const [
        PopupMenuItem(
          key: Key('copyAllCardFieldsAction'),
          value: 'copyAll',
          child: Text('Скопировать всё'),
        ),
      ],
    );
    if (!mounted || selected != 'copyAll') return;
    await copySensitiveText(allCardText());
  }

  List<SecretAttachment> get availableAttachments => currentItem.attachments
      .where(
        (attachment) => !attachment.deleted && attachment.decodeError == null,
      )
      .toList(growable: false);

  String attachmentCacheKey(SecretAttachment attachment) => attachment
          .id.isNotEmpty
      ? attachment.id
      : 'pending:${identityHashCode(attachment.pendingBytes)}:${attachment.size}';

  Future<Uint8List> attachmentBytes(SecretAttachment attachment) =>
      attachmentByteLoads.putIfAbsent(attachmentCacheKey(attachment), () async {
        if (attachment.pendingBytes != null) {
          return Uint8List.fromList(attachment.pendingBytes!);
        }
        final loader = widget.loadAttachmentBytes;
        if (loader == null || attachment.id.isEmpty) return Uint8List(0);
        return Uint8List.fromList(await loader(attachment.id));
      });

  Future<void> previewAttachment(SecretAttachment attachment) async {
    try {
      final bytes = await attachmentBytes(attachment);
      if (bytes.isEmpty) return;
      await openAttachmentBytesWithSystem(attachment.fileName, bytes);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось открыть вложение: $error')),
      );
    }
  }

  Future<void> saveAttachment(SecretAttachment attachment) async {
    try {
      final bytes = await attachmentBytes(attachment);
      if (bytes.isEmpty) return;
      final export = gallerySafeAttachmentExport(attachment.fileName, bytes);
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Сохранить вложение',
        fileName: export.fileName,
        bytes: export.bytes,
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

  Future<void> chooseAttachmentToSave() async {
    final source = availableAttachments;
    if (source.isEmpty) return;
    if (source.length == 1) {
      await saveAttachment(source.single);
      return;
    }
    final selected = await showDialog<SecretAttachment>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Сохранить вложение'),
        children: [
          for (final attachment in source)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, attachment),
              child: Text(attachment.fileName),
            ),
        ],
      ),
    );
    if (selected != null) await saveAttachment(selected);
  }

  Widget previewAttachmentNames() {
    final files = availableAttachments.where(
      (attachment) => !isInlineImage(attachment.fileName),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final attachment in files)
          Material(
            key: ValueKey('cardPreviewAttachment-${attachment.fileName}'),
            color: Colors.transparent,
            child: InkWell(
              onTap: () => previewAttachment(attachment),
              onSecondaryTap: () => previewAttachment(attachment),
              onLongPress: () => previewAttachment(attachment),
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
      ],
    );
  }

  bool isInlineImage(String fileName) {
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

  Widget inlineAttachmentPreview(
    SecretAttachment attachment,
    Color background,
  ) {
    return FutureBuilder<Uint8List>(
      future: attachmentBytes(attachment),
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        Widget content;
        if (bytes == null) {
          content = const SizedBox(
            height: 72,
            child: Center(child: CircularProgressIndicator()),
          );
        } else if (isInlineImage(attachment.fileName)) {
          content = ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: Image.memory(
              bytes,
              width: double.infinity,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) =>
                  const Center(child: Icon(Icons.broken_image_outlined)),
            ),
          );
        } else {
          return const SizedBox.shrink();
        }
        return Padding(
          key: ValueKey('cardPreviewInlineAttachment-${attachment.fileName}'),
          padding: const EdgeInsets.only(top: 10),
          child: Material(
            color: background.withValues(alpha: 0.9),
            shape: RoundedRectangleBorder(
              side: const BorderSide(color: Color(0xff82929d)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: InkWell(
              onTap: () => previewAttachment(attachment),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      attachment.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    content,
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.sizeOf(context);
    final fullScreen = Platform.isAndroid || media.width < 700;
    final color = itemDisplayColor(currentItem, widget.template);
    final visibleFields = fieldsForItem(
      widget.template,
      currentItem,
    ).where((field) => (currentItem.values[field.id] ?? '').trim().isNotEmpty);
    final orderedVisibleFields = [
      ...visibleFields.where((field) => field.type != 'multiline_note'),
      ...visibleFields.where((field) => field.type == 'multiline_note'),
    ];
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
          key: const Key('cardPreviewSurface'),
          width: fullScreen ? media.width : min(media.width - 24, 720),
          height: fullScreen ? media.height : min(media.height - 24, 760),
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: handlePreviewPointerDown,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onLongPressStart: (details) =>
                  showCopyAllMenu(details.globalPosition),
              child: Column(
                children: [
                  Container(
                    height: 48,
                    alignment: Alignment.centerLeft,
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
                            currentItem.title,
                            key: const Key('cardPreviewTitle'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 18),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          formatCardModifiedAt(currentItem.modifiedAt),
                          key: const Key('cardPreviewModifiedAt'),
                          maxLines: 1,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: DecoratedBox(
                      decoration: cardSurfaceDecoration(
                        color: color.bg,
                        backgroundImage: cachedBackgroundImage,
                      ),
                      child: SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(
                          14,
                          14,
                          14,
                          18 + MediaQuery.viewInsetsOf(context).bottom,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Center(
                              child: Container(
                                key: const Key('cardPreviewIcon'),
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
                                child: templateIconWidget(
                                  itemIconId(currentItem, widget.template),
                                  size: 88,
                                  color: pictogramColorForBackground(color.bg),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            for (final field in orderedVisibleFields)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: TextFormField(
                                  key: ValueKey('cardPreviewField-${field.id}'),
                                  initialValue:
                                      currentItem.values[field.id] ?? '',
                                  readOnly: true,
                                  contextMenuBuilder:
                                      usesDesktopCardTextControls
                                          ? desktopCardTextContextMenu
                                          : null,
                                  obscureText: fieldDefinitionIsSecret(field) &&
                                      !revealedFields.contains(field.id),
                                  minLines:
                                      field.type == 'multiline_note' ? 3 : 1,
                                  maxLines:
                                      field.type == 'multiline_note' ? null : 1,
                                  decoration: InputDecoration(
                                    labelText: field.label,
                                    border: const OutlineInputBorder(),
                                    filled: true,
                                    fillColor: color.bg,
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    suffixIconConstraints:
                                        BoxConstraints.tightFor(
                                      width: fieldDefinitionIsSecret(field)
                                          ? 72
                                          : 36,
                                      height: 40,
                                    ),
                                    suffixIcon: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (fieldDefinitionIsSecret(field))
                                          SizedBox(
                                            width: 36,
                                            child: IconButton(
                                              padding: EdgeInsets.zero,
                                              tooltip: revealedFields
                                                      .contains(field.id)
                                                  ? 'Скрыть'
                                                  : 'Показать',
                                              icon: Icon(
                                                revealedFields
                                                        .contains(field.id)
                                                    ? Icons.visibility_off
                                                    : Icons.visibility,
                                                size: 19,
                                              ),
                                              onPressed: () => setState(() {
                                                revealedFields
                                                        .contains(field.id)
                                                    ? revealedFields
                                                        .remove(field.id)
                                                    : revealedFields
                                                        .add(field.id);
                                              }),
                                            ),
                                          ),
                                        SizedBox(
                                          width: 36,
                                          child: IconButton(
                                            key: ValueKey(
                                                'cardPreviewCopy-${field.id}'),
                                            padding: EdgeInsets.zero,
                                            tooltip: 'Копировать',
                                            icon: const Icon(
                                              Icons.copy_outlined,
                                              size: 17,
                                              color: Color(0xff777777),
                                            ),
                                            onPressed: () => copyCardFieldValue(
                                              currentItem.values[field.id] ??
                                                  '',
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            if (availableAttachments.any(
                              (attachment) =>
                                  !isInlineImage(attachment.fileName),
                            )) ...[
                              previewAttachmentNames(),
                              const SizedBox(height: 8),
                            ],
                            for (final attachment in availableAttachments.where(
                              (attachment) =>
                                  isInlineImage(attachment.fileName),
                            ))
                              inlineAttachmentPreview(attachment, color.bg),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
                    decoration: const BoxDecoration(
                      color: Color(0xffdce8f1),
                      border: Border(top: BorderSide(color: Color(0xff7f8d98))),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Row(
                          children: [
                            if (availableAttachments.isNotEmpty)
                              SpbGradientActionButton(
                                key: const Key(
                                    'cardPreviewSaveAttachmentButton'),
                                icon: Icons.folder_outlined,
                                tooltip: 'Сохранить вложение',
                                colors: const [
                                  Color(0xff555555),
                                  Color(0xff050505),
                                ],
                                onTap: chooseAttachmentToSave,
                              ),
                            const Spacer(),
                            SpbGradientActionButton(
                              key: const Key('cardPreviewEditButton'),
                              icon: Icons.edit,
                              tooltip: 'Редактировать карточку',
                              colors: const [
                                Color(0xff5bc96d),
                                Color(0xff08772f),
                              ],
                              onTap: () => Navigator.pop(
                                  context, CardPreviewAction.edit),
                            ),
                            const SizedBox(width: 6),
                            SpbGradientActionButton(
                              key: const Key('cardPreviewDeleteButton'),
                              icon: Icons.delete_outline,
                              tooltip: 'Удалить карточку',
                              colors: const [
                                Color(0xffffdc58),
                                Color(0xffc58a00),
                              ],
                              onTap: () => Navigator.pop(
                                context,
                                CardPreviewAction.delete,
                              ),
                            ),
                            const SizedBox(width: 6),
                            SpbGradientActionButton(
                              key: const Key('cardPreviewBackButton'),
                              icon: Icons.close,
                              tooltip: 'Выйти из просмотра',
                              colors: const [
                                Color(0xffff5a5f),
                                Color(0xffa90000),
                              ],
                              onTap: () => Navigator.pop(
                                  context, CardPreviewAction.back),
                            ),
                          ],
                        ),
                      ],
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
}
