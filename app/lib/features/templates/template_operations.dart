part of '../../main.dart';

extension _TemplateOperations on _VaultShellState {
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
          onChanged: (value) =>
              _updateShellState(() => templateSearchQuery = value),
        ),
        const SizedBox(height: 12),
        if (visibleTemplates.isEmpty)
          const Center(child: Text('Шаблоны не найдены'))
        else
          ...visibleTemplates.map((template) {
            final backgroundColor = templateDisplayBackground(template);
            final pictogramColor = templateDisplayPictogramColor(template);
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                elevation: 0,
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: backgroundColor,
                    foregroundColor: pictogramColor,
                    child: templateIconWidget(
                      template.iconId,
                      color: pictogramColor,
                    ),
                  ),
                  title: Text(template.name),
                  subtitle: Text(
                    template.fields
                        .map(
                          (field) =>
                              '${field.label}${fieldDefinitionIsSecret(field) ? ' (скрыто)' : ''}',
                        )
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
      spbColor: template.spbColor,
      categoryPath: template.categoryPath,
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

  Future<void> editSelectedSpbTemplate() async {
    final template = selectedSpbTemplate();
    if (template == null) {
      showTemplateActionMessage('Выберите шаблон для редактирования.');
      return;
    }
    await openTemplateDialog(template: template);
  }

  Future<void> deleteSelectedSpbTemplate() async {
    final template = selectedSpbTemplate();
    if (template == null) {
      showTemplateActionMessage('Выберите шаблон для удаления.');
      return;
    }
    await deleteTemplateWithConfirmation(template);
  }

  Future<void> importSpbTemplate() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['swt'],
        withData: true,
      );
      final file = picked?.files.single;
      if (file == null) return;
      final data = file.bytes ??
          (file.path == null ? null : await File(file.path!).readAsBytes());
      if (data == null || data.isEmpty) {
        throw const FormatException('Файл шаблона пуст.');
      }
      final imported = decodeSwtTemplate(Uint8List.fromList(data));
      final saved = await saveSpbTemplateDefinition(imported, isNew: true);
      if (saved) {
        showTemplateActionMessage('Шаблон «${imported.name}» импортирован.');
      }
    } catch (error) {
      showTemplateActionMessage('Не удалось импортировать SWT: $error');
    }
  }

  Future<void> exportSelectedSpbTemplate() async {
    final template = selectedSpbTemplate();
    if (template == null) {
      showTemplateActionMessage('Выберите шаблон для экспорта.');
      return;
    }
    try {
      final data = encodeSwtTemplate(template);
      final safeName =
          template.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Экспорт шаблона',
        fileName: '${safeName.isEmpty ? 'Шаблон' : safeName}.swt',
        type: FileType.custom,
        allowedExtensions: const ['swt'],
        bytes: data,
      );
      if (path == null) return;
      if (!Platform.isAndroid && !Platform.isIOS) {
        final outputPath =
            path.toLowerCase().endsWith('.swt') ? path : '$path.swt';
        final output = File(outputPath);
        if (!output.existsSync() || output.lengthSync() != data.length) {
          await output.writeAsBytes(data, flush: true);
        }
      }
      showTemplateActionMessage('Шаблон «${template.name}» экспортирован.');
    } catch (error) {
      showTemplateActionMessage('Не удалось экспортировать SWT: $error');
    }
  }

  void showTemplateActionMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(text), duration: const Duration(seconds: 3)),
      );
  }

  Future<void> openTemplateDialog({
    CardTemplate? template,
    CardTemplate? draft,
  }) async {
    final saved = await showDialog<CardTemplate>(
      context: context,
      builder: (context) => TemplateEditorDialog(initial: draft ?? template),
    );
    if (saved == null) return;
    await saveSpbTemplateDefinition(saved, isNew: template == null);
  }

  Future<void> openTemplatePreview(CardTemplate template) async {
    _updateShellState(() => selectedTemplateId = template.id);
    await showDialog<void>(
      context: context,
      builder: (context) => TemplatePreviewDialog(template: template),
    );
  }

  Future<bool> saveSpbTemplateDefinition(
    CardTemplate saved, {
    required bool isNew,
  }) async {
    if (spbWallet != null) {
      if (!ensureSpbWalletWritable()) return false;
      if (!isNew) {
        final existing = templatesById[saved.id];
        if (existing != null &&
            spbTemplatesHaveSameStoredContent(existing, saved)) {
          return true;
        }
      }
      final prepared = prepareSpbTemplate(saved, isNew);
      SessionUndoEntry? undoEntry;
      try {
        undoEntry = await captureSessionUndo(
          isNew
              ? 'Создание шаблона: ${saved.name}'
              : 'Изменение шаблона: ${saved.name}',
          saved.iconId,
        );
        await mutateVault<void>(
          () => spbWallet!.saveTemplate(
            SpbWalletTemplateDraft(
              id: prepared.id,
              name: prepared.name,
              iconId: spbIconIdForUi(prepared.iconId, prepared.iconId),
              cardColor:
                  prepared.spbColor ?? paletteColorToSpb(prepared.colorId),
              categoryPath: prepared.categoryPath,
              iconBytes: prepared.embeddedIconBase64 == null
                  ? null
                  : base64Decode(prepared.embeddedIconBase64!),
              iconFileName: prepared.iconFileName,
              fields: prepared.fields
                  .where((field) => field.id != spbDescriptionFieldId)
                  .map(
                    (field) => SpbWalletTemplateFieldRecord(
                      id: field.id,
                      name: field.label,
                      templateId: prepared.id,
                      fieldTypeId: spbFieldTypeId(field),
                    ),
                  )
                  .toList(),
            ),
          ),
        );
        final written = await writeBackSpbWallet();
        final updated = spbWallet!.loadSnapshot();
        _updateShellState(() {
          applySpbSnapshot(updated);
          selectedTemplateId = prepared.id;
          if (written) message = null;
        });
        commitSessionUndo(undoEntry);
        return true;
      } catch (error) {
        discardSessionUndo(undoEntry);
        _updateShellState(
          () => message = 'Не удалось сохранить шаблон .swl базы: $error',
        );
        return false;
      }
    }
    _updateShellState(
      () => message =
          'Откройте или создайте .swl базу перед сохранением шаблонов.',
    );
    return false;
  }

  CardTemplate prepareSpbTemplate(CardTemplate template, bool isNew) {
    final id = isNew ? SpbWalletDatabase.makeId() : template.id;
    return CardTemplate(
      id: id,
      name: template.name,
      iconId: template.iconId,
      colorId: template.colorId,
      embeddedIconBase64: template.embeddedIconBase64,
      iconFileName: template.iconFileName,
      spbColor: template.spbColor,
      categoryPath: template.categoryPath,
      fields: template.fields
          .where((field) => field.id != spbDescriptionFieldId)
          .map(
            (field) => FieldDefinition(
              id: spbTemplateFieldId(field.id, isNew),
              label: field.label,
              type: field.type,
              required: field.required,
              secret: fieldTypeIsSecret(field.type),
            ),
          )
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
}
