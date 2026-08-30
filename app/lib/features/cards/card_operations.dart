part of '../../main.dart';

extension _CardOperations on _VaultShellState {
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
                onChanged: updateSpbSearch,
                onSubmitted: submitSpbSearch,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: buildSearchClearButton(
                    const Key('cardsClearSearchButton'),
                  ),
                  suffixIconConstraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  labelText: 'Поиск',
                  border: const OutlineInputBorder(),
                ),
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
                        : itemDetail(selected),
                  ),
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
                    labelText: 'Шаблон',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('Все шаблоны'),
                    ),
                    ...templates.map(
                      (template) => DropdownMenuItem(
                        value: template.id,
                        child: Text(template.name),
                      ),
                    ),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => nextTemplateFilter = value ?? ''),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: nextSortMode,
                  decoration: const InputDecoration(
                    labelText: 'Сортировка',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'modified_desc',
                      child: Text('Сначала новые'),
                    ),
                    DropdownMenuItem(
                      value: 'title_asc',
                      child: Text('По названию'),
                    ),
                    DropdownMenuItem(
                      value: 'template_asc',
                      child: Text('По шаблону'),
                    ),
                  ],
                  onChanged: (value) => setDialogState(
                    () => nextSortMode = value ?? 'modified_desc',
                  ),
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
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Применить'),
            ),
          ],
        ),
      ),
    );
    if (applied != true) return;
    _updateShellState(() {
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
      filtered.sort(
        (a, b) => templateFor(
          a.templateId,
        ).name.compareTo(templateFor(b.templateId).name),
      );
    } else {
      filtered.sort((a, b) {
        final byDate = b.modifiedAt.compareTo(a.modifiedAt);
        if (byDate != 0) return byDate;
        final byTitle = a.title.toLowerCase().compareTo(b.title.toLowerCase());
        return byTitle == 0 ? a.id.compareTo(b.id) : byTitle;
      });
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
            child: const Text(
              'Мои карточки',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
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
                            parentPath: '',
                            folder: null,
                          ),
                        ),
                      ),
                    ],
                  ),
                  children: root.isEmpty
                      ? const [
                          ListTile(
                            dense: true,
                            title: Text('Карточек не найдено'),
                          ),
                        ]
                      : treeChildren(
                          root,
                          0,
                          openCardsInDialog: openCardsInDialog,
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  CategoryTreeNode buildCategoryTree(
    List<SecretItem> source, {
    bool includeAllCategories = true,
    Iterable<String> additionalPaths = const [],
  }) {
    return navigationController.buildTree(
      source: source,
      categoryPathOf: (item) => item.category,
      categoryPaths: categoryPaths,
      iconIdsByPath: categoryIconsByPath,
      colorIdsByPath: categoryColorsByPath,
      categoryIdsByPath: categoryIdsByPath,
      includeAllCategories: includeAllCategories,
      additionalPaths: additionalPaths,
    );
  }

  List<String> categoryParts(String value) {
    return navigationController.categoryParts(value);
  }

  List<String> existingCategories() {
    return navigationController.existingCategoryPaths(
      categoryPaths: categoryPaths,
      iconPaths: categoryIconsByPath.keys,
      colorPaths: categoryColorsByPath.keys,
      items: items,
      categoryPathOf: (item) => item.category,
    );
  }

  List<Widget> treeChildren(
    CategoryTreeNode node,
    int depth, {
    required bool openCardsInDialog,
  }) {
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
              folder.iconId ?? defaultIconForCategoryPath(folder.path),
              folder.colorId,
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    folder.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
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
                      parentPath: folder.path,
                      folder: null,
                    ),
                  ),
                ),
              ],
            ),
            children: treeChildren(
              folder,
              depth + 1,
              openCardsInDialog: openCardsInDialog,
            ),
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
            leading: templateIconWidget(
              itemIconId(item, template),
              color: itemPictogramColor(item, template),
            ),
            title: Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              template.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
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

  Widget categoryFolderIcon(String iconId, String? colorId) {
    return SizedBox(
      width: 38,
      height: 38,
      child: Center(
        child: templateIconWidget(
          iconId.isEmpty ? 'folder' : iconId,
          size: 30,
          color: categoryPictogramColor(colorId),
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
      _updateShellState(
        () =>
            message = 'Откройте или создайте .swl базу перед изменением папок.',
      );
      return;
    }
    if (!ensureSpbWalletWritable()) return;
    final editing = folder != null;
    final saved =
        await showDialog<({String name, String iconId, String colorId})>(
      context: context,
      builder: (context) => CategoryEditorDialog(
        editing: editing,
        initialName: folder?.name ?? '',
        initialIconId: folder?.iconId ?? defaultIconForCategoryPath(parentPath),
        initialColorId: folder?.colorId ?? 'template_gray',
      ),
    );
    if (saved == null) return;
    if (editing && saved.name == '__delete__') {
      await Future<void>.delayed(Duration.zero);
      if (!mounted) return;
      final confirmed = await confirmDeleteCategory(folder);
      if (confirmed != true || !mounted) return;
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      SessionUndoEntry? undoEntry;
      try {
        undoEntry = await captureSessionUndo(
          'Удаление папки: ${folder.name}',
          folder.iconId ?? defaultIconForCategoryPath(folder.path),
        );
        sessionTrashFolderPaths.add(folder.path);
        sessionTrash.add(
          SessionTrashEntry(
            kind: SessionTrashKind.folder,
            id: folder.path,
            title: folder.name,
            iconId: folder.iconId ?? defaultIconForCategoryPath(folder.path),
          ),
        );
        final snapshot = wallet.loadSnapshot();
        _updateShellState(() {
          applySpbSnapshot(snapshot);
          if (selectedItemId != null &&
              !items.any((entry) => entry.id == selectedItemId)) {
            selectedItemId = null;
          }
          message = null;
        });
        commitSessionUndo(undoEntry);
      } catch (error) {
        discardSessionUndo(undoEntry);
        _updateShellState(() => message = 'Не удалось удалить папку: $error');
      }
      return;
    }
    final fullPath = [
      if (!editing && parentPath.trim().isNotEmpty) parentPath.trim(),
      saved.name,
    ].join(' / ');
    if (editing &&
        saved.name == folder.name &&
        saved.iconId ==
            (folder.iconId ?? defaultIconForCategoryPath(folder.path)) &&
        saved.colorId == folder.colorId) {
      return;
    }
    SessionUndoEntry? undoEntry;
    try {
      undoEntry = await captureSessionUndo(
        editing
            ? 'Изменение папки: ${folder.name}'
            : 'Создание папки: ${saved.name}',
        saved.iconId,
      );
      final spbIconId = spbIconIdForUi(saved.iconId, 'folder') ??
          syntheticSpbIconIdForUi(saved.iconId);
      final iconBytes = spbEmbeddedIconPngs[saved.iconId.toUpperCase()];
      await mutateVault<void>(() {
        if (editing) {
          wallet.renameCategory(
            folder.path,
            saved.name,
            spbIconId,
            iconBytes: iconBytes,
            colorId: saved.colorId,
          );
        } else {
          wallet.createCategory(
            fullPath,
            spbIconId,
            iconBytes: iconBytes,
            colorId: saved.colorId,
          );
        }
      });
      final written = await writeBackSpbWallet();
      final snapshot = wallet.loadSnapshot();
      _updateShellState(() {
        applySpbSnapshot(snapshot);
        if (!editing) {
          selectedCategoryPath = fullPath;
          selectedCategoryId = categoryIdsByPath[fullPath];
          mobilePane = 1;
        }
        if (written) message = null;
      });
      commitSessionUndo(undoEntry);
    } catch (error) {
      discardSessionUndo(undoEntry);
      _updateShellState(() => message = 'Не удалось сохранить папку: $error');
    }
  }

  Future<bool?> confirmDeleteCategory(CategoryTreeNode folder) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить папку?'),
        content: Text(
          'Папка ${folder.name}, ее подпапки и все карточки внутри будут удалены.',
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
    final frequent = frequentItems();
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
                  leading: templateIconWidget(
                    itemIconId(item, template),
                    color: itemPictogramColor(item, template),
                  ),
                  title: Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => openFrequentCard(item),
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
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: buildSearchClearButton(
                    const Key('panelClearSearchButton'),
                  ),
                  suffixIconConstraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> selectItem(SecretItem item) async {
    final current = itemById(item.id) ?? item;
    final background = current.backgroundImageBase64 ??
        spbWallet?.loadCardBackgroundBase64(current.id);
    final selected = SecretItem(
      id: current.id,
      templateId: current.templateId,
      title: current.title,
      category: current.category,
      colorId: current.colorId,
      values: current.values,
      modifiedAt: current.modifiedAt,
      attachments: current.attachments,
      hitCount: current.hitCount + 1,
      iconId: current.iconId,
      backgroundImageBase64: background,
      spbColor: current.spbColor,
      fieldOrder: current.fieldOrder,
      hiddenFieldIds: current.hiddenFieldIds,
    );
    _updateShellState(() {
      selectedItemId = selected.id;
      recentlyOpenedItemIds
        ..remove(selected.id)
        ..insert(0, selected.id);
      if (recentlyOpenedItemIds.length > 10) {
        recentlyOpenedItemIds.removeRange(10, recentlyOpenedItemIds.length);
      }
      items = [
        for (final entry in items)
          if (entry.id == selected.id) selected else entry,
      ];
      itemsById[selected.id] = selected;
    });
    if (spbWallet == null) {
      _updateShellState(
        () => message =
            'Откройте или создайте .swl базу перед изменением карточек.',
      );
    }
  }

  Future<void> openCardPreviewDialog(
    SecretItem item, {
    bool preserveSearch = false,
  }) async {
    await selectItem(item);
    if (!mounted) return;
    var previewItem = itemById(item.id) ?? item;
    while (true) {
      if (!mounted) return;
      final action = await showDialog<CardPreviewAction>(
        context: context,
        builder: (context) => CardPreviewDialog(
          item: previewItem,
          template: templateFor(previewItem.templateId),
          loadAttachmentBytes: spbWallet == null
              ? null
              : (attachmentId) async =>
                  spbWallet!.readAttachmentBytes(attachmentId),
          onAddAttachment: spbWallet == null ? null : addAttachmentFromPreview,
        ),
      );
      if (!mounted || !unlocked) return;
      final latestItem = itemById(previewItem.id) ?? previewItem;
      if (action == CardPreviewAction.edit) {
        await openItemDialog(item: latestItem);
        if (!mounted || !unlocked) return;
        previewItem = itemById(latestItem.id) ?? latestItem;
        continue;
      }
      if (action == CardPreviewAction.delete) {
        await deleteItemWithConfirmation(latestItem);
      }
      previewItem = itemById(latestItem.id) ?? latestItem;
      break;
    }
    if (!mounted || !unlocked) return;
    if (!preserveSearch) revealCardFolder(previewItem);
  }

  Future<void> openFrequentCard(SecretItem item) async {
    await openCardPreviewDialog(item);
  }

  void revealCardFolder(SecretItem item) {
    final latestItem = itemById(item.id);
    final categoryPath = latestItem?.category ?? item.category;
    final parts = categoryParts(categoryPath);
    final parentPaths = <String>{};
    for (var index = 1; index <= parts.length; index++) {
      parentPaths.add(parts.take(index).join(' / '));
    }

    searchController.clear();
    _updateShellState(() {
      mobileTemplatesOpen = false;
      mobilePane = 1;
      spbSubmittedSearchQuery = '';
      selectedCategoryPath = categoryPath;
      selectedCategoryId = categoryIdsByPath[categoryPath];
      navigationController.expandCategoryPaths(
        parentPaths,
        categoryIdsByPath,
      );
      selectedItemId = latestItem?.id;
    });
  }

  Future<SecretItem?> addAttachmentFromPreview(SecretItem item) async {
    final picked = await FilePicker.platform.pickFiles(withData: true);
    final file = picked?.files.single;
    if (file == null) return null;
    final bytes = file.bytes ??
        (file.path == null ? null : await File(file.path!).readAsBytes());
    if (bytes == null) return null;
    final updated = SecretItem(
      id: item.id,
      templateId: item.templateId,
      title: item.title,
      category: item.category,
      colorId: item.colorId,
      values: item.values,
      attachments: [
        ...item.attachments,
        SecretAttachment(
          id: '',
          fileName: file.name,
          size: bytes.length,
          pendingBytes: bytes,
        ),
      ],
      modifiedAt: DateTime.now().toUtc(),
      hitCount: item.hitCount,
      iconId: item.iconId,
      backgroundImageBase64: item.backgroundImageBase64,
      spbColor: item.spbColor,
      fieldOrder: item.fieldOrder,
      hiddenFieldIds: item.hiddenFieldIds,
    );
    final savedId = await persistItem(updated);
    return savedId == null ? null : itemById(savedId);
  }

  void updateItemCardState(
    VoidCallback action,
    void Function(VoidCallback action)? onStateChange,
  ) {
    if (onStateChange == null) {
      _updateShellState(action);
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
        modifiedAt: DateTime.now().toUtc(),
        attachments: item.attachments,
        hitCount: item.hitCount,
        iconId: item.iconId,
        backgroundImageBase64: item.backgroundImageBase64,
        spbColor: item.spbColor,
        fieldOrder: item.fieldOrder,
        hiddenFieldIds: item.hiddenFieldIds,
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
            maxLines: null,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Заметка',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (saved == null) return;
    await saveNoteFromDialog(item, fieldId, saved);
  }

  Widget buildFrequentView() {
    final top = frequentItems().take(10).toList();
    if (top.isEmpty) {
      return const Center(
        child: Text(
          'Часто используемые карточки появятся после открытия карточек из дерева.',
        ),
      );
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
            leading: templateIconWidget(
              itemIconId(item, template),
              size: 24,
              color: itemPictogramColor(item, template),
            ),
            title: Text(item.title),
            subtitle: Text('${template.name} · открытий: ${item.hitCount}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => openFrequentCard(item),
          ),
        );
      },
    );
  }

  Widget itemCard(
    SecretItem item, {
    VoidCallback? onClose,
    bool showFooterActions = true,
    bool showNotesAction = true,
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
                        BlendMode.srcOver,
                      ),
                    ),
                  ),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 72),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    templateIconWidget(
                      itemIconId(item, template),
                      size: 28,
                      color: itemPictogramColor(item, template),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: color.fg,
                            ),
                          ),
                          Text(
                            template.name,
                            style: TextStyle(
                              color: color.fg.withValues(alpha: 0.72),
                            ),
                          ),
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
                  child: CardFieldValuesList(
                    key: ValueKey('card-fields-${item.id}'),
                    fields: fieldsForItem(template, item),
                    item: item,
                    foreground: color.fg,
                    revealed: revealed,
                    onToggle: (revealKey, isRevealed) =>
                        updateItemCardState(() {
                      isRevealed
                          ? revealed.remove(revealKey)
                          : revealed.add(revealKey);
                    }, onStateChange),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Категория: ${item.category.isEmpty ? 'Без категории' : item.category}',
                  style: TextStyle(color: color.fg.withValues(alpha: 0.72)),
                ),
                const SizedBox(height: 8),
                if (showFooterActions)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (showNotesAction)
                        CountBadgeButton(
                          key: const Key('cardNotesButton'),
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

  Future<bool> _deleteItemWithConfirmationImpl(SecretItem item) async {
    if (!ensureSpbWalletWritable()) return false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        title: const Text('Удалить карточку'),
        content: Text('Карточка ${item.title} будет удалена из базы.'),
        actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
        actions: [
          SizedBox(
            width: 124,
            child: passwordKey(
              key: const Key('cancelDeleteCardButton'),
              label: 'Отмена',
              height: 40,
              fontSize: 18,
              onPressed: () => Navigator.pop(dialogContext, false),
            ),
          ),
          SizedBox(
            width: 124,
            child: passwordKey(
              key: const Key('confirmDeleteCardButton'),
              label: 'Удалить',
              height: 40,
              fontSize: 18,
              top: const Color(0xffe04b3f),
              bottom: const Color(0xff8f1515),
              onPressed: () => Navigator.pop(dialogContext, true),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;
    final wallet = spbWallet;
    if (wallet == null) {
      _updateShellState(
        () => message =
            'Откройте или создайте .swl базу перед удалением карточек.',
      );
      return false;
    }
    SessionUndoEntry? undoEntry;
    try {
      undoEntry = await captureSessionUndo(
        'Удаление карточки: ${item.title}',
        itemIconId(item, templateFor(item.templateId)),
      );
      sessionTrashCardIds.add(item.id);
      sessionTrash.add(
        SessionTrashEntry(
          kind: SessionTrashKind.card,
          id: item.id,
          title: item.title,
          iconId: itemIconId(item, templateFor(item.templateId)),
        ),
      );
      _updateShellState(() {
        items = items.where((entry) => entry.id != item.id).toList();
        itemsById.remove(item.id);
        if (selectedItemId == item.id) selectedItemId = null;
        recentlyOpenedItemIds.remove(item.id);
        message = null;
      });
      refreshSpbSearchIndex();
      commitSessionUndo(undoEntry);
      return true;
    } catch (error) {
      discardSessionUndo(undoEntry);
      _updateShellState(() => message = 'Не удалось удалить карточку: $error');
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
    String fileName,
    Uint8List bytes,
  ) async {
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
                title: Text(
                  fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
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
    String fileName,
    Uint8List bytes,
  ) async {
    final directory = await getTemporaryDirectory();
    final safeName = fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final temporaryName = Platform.isAndroid
        ? 'wallet_aps_${safeName.hashCode.toUnsigned(32)}.apsblob'
        : 'wallet_aps_$safeName';
    final file = File(
      '${directory.path}${Platform.pathSeparator}$temporaryName',
    );
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

  Future<void> exportReadOnlyAttachment(SecretAttachment attachment) async {
    final wallet = spbWallet;
    if (wallet == null || attachment.id.isEmpty) return;
    try {
      final bytes = Uint8List.fromList(
        wallet.readAttachmentBytes(attachment.id),
      );
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

  SecretItem? itemById(String id) => itemsById[id];

  Future<SecretItem?> openItemDialog({
    SecretItem? item,
    String? initialCategory,
  }) async {
    if (templates.isEmpty) {
      if (mounted) {
        _updateShellState(
          () => message =
              'В базе нет шаблонов. Сначала создайте или импортируйте шаблон.',
        );
      }
      return null;
    }
    final saved = await showDialog<SecretItem>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ItemEditorDialog(
        templates: templates,
        categories: existingCategories(),
        initial: item,
        initialCategory: initialCategory,
        supportsAttachments: spbWallet != null,
        loadAttachmentBytes: spbWallet == null
            ? null
            : (attachmentId) async =>
                spbWallet!.readAttachmentBytes(attachmentId),
      ),
    );
    if (!mounted || !unlocked) return null;
    if (item != null) {
      _updateShellState(() => selectedItemId = item.id);
    }
    if (saved == null) return null;
    final savedId = await persistItem(saved);
    if (savedId == null) return null;
    return itemById(savedId) ?? saved;
  }

  Future<String?> persistItem(SecretItem saved) async {
    if (spbWallet != null) {
      return saveSpbItem(saved);
    }
    _updateShellState(
      () => message =
          'Откройте или создайте .swl базу перед сохранением карточек.',
    );
    return null;
  }

  bool spbItemsHaveSameStoredContent(SecretItem first, SecretItem second) {
    if (first.templateId != second.templateId ||
        first.title != second.title ||
        first.category != second.category ||
        first.colorId != second.colorId ||
        first.iconId != second.iconId ||
        first.backgroundImageBase64 != second.backgroundImageBase64 ||
        first.spbColor != second.spbColor ||
        !mapEquals(first.values, second.values) ||
        !listEquals(first.fieldOrder, second.fieldOrder) ||
        !setEquals(first.hiddenFieldIds, second.hiddenFieldIds) ||
        first.attachments.length != second.attachments.length) {
      return false;
    }
    for (var index = 0; index < first.attachments.length; index++) {
      final original = first.attachments[index];
      final edited = second.attachments[index];
      if (original.id != edited.id ||
          original.fileName != edited.fileName ||
          original.size != edited.size ||
          edited.deleted ||
          edited.pendingBytes != null) {
        return false;
      }
    }
    return true;
  }

  bool spbTemplatesHaveSameStoredContent(
    CardTemplate first,
    CardTemplate second,
  ) {
    if (first.name != second.name ||
        first.iconId != second.iconId ||
        first.colorId != second.colorId ||
        first.spbColor != second.spbColor ||
        first.categoryPath != second.categoryPath ||
        first.fields.length != second.fields.length) {
      return false;
    }
    for (var index = 0; index < first.fields.length; index++) {
      final original = first.fields[index];
      final edited = second.fields[index];
      if (original.id != edited.id ||
          original.label != edited.label ||
          original.type != edited.type ||
          original.required != edited.required ||
          original.secret != edited.secret) {
        return false;
      }
    }
    return true;
  }

  Future<String?> saveSpbItem(SecretItem saved) async {
    final wallet = spbWallet;
    if (wallet == null) return null;
    if (!ensureSpbWalletWritable()) return null;
    final cardId = isSpbHexId(saved.id) ? saved.id : SpbWalletDatabase.makeId();
    final existing = itemById(saved.id);
    if (existing != null && spbItemsHaveSameStoredContent(existing, saved)) {
      return existing.id;
    }
    final hasAttachmentChanges = saved.attachments.any(
      (attachment) => attachment.deleted || attachment.pendingBytes != null,
    );
    final needsCategoryRefresh = saved.category.trim().isNotEmpty &&
        !categoryIdsByPath.containsKey(saved.category);
    final template = templateFor(saved.templateId);
    SessionUndoEntry? undoEntry;
    try {
      undoEntry = await captureSessionUndo(
        existing == null
            ? 'Создание карточки: ${saved.title}'
            : 'Изменение карточки: ${saved.title}',
        itemIconId(saved, template),
      );
      await mutateVault<void>(() => wallet.runTransaction<void>(() {
            if (!wallet.hasTemplate(saved.templateId)) {
              wallet.saveTemplate(
                SpbWalletTemplateDraft(
                  id: template.id,
                  name: template.name == 'Неизвестный шаблон'
                      ? 'Восстановлено: ${saved.title}'
                      : template.name,
                  iconId: spbIconIdForUi(template.iconId, template.iconId),
                  cardColor:
                      template.spbColor ?? paletteColorToSpb(template.colorId),
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
            wallet.saveCard(
              SpbWalletCardDraft(
                id: cardId,
                title: saved.title,
                description: saved.values[spbDescriptionFieldId] ?? '',
                categoryPath: saved.category,
                templateId: saved.templateId,
                fieldValues: {
                  for (final entry in saved.values.entries)
                    if (entry.key != spbDescriptionFieldId)
                      entry.key: entry.value,
                },
                cardColor: saved.spbColor ?? paletteColorToSpb(saved.colorId),
                iconId: spbIconIdForUi(
                    itemIconId(saved, template), template.iconId),
                iconBytes: saved.iconId == null
                    ? null
                    : spbEmbeddedIconPngs[saved.iconId!.toUpperCase()],
                backgroundImageBase64: saved.backgroundImageBase64,
                fieldOrder: saved.fieldOrder,
                hiddenFieldIds: saved.hiddenFieldIds,
                modifiedAt: saved.modifiedAt,
              ),
            );
            for (final attachment in saved.attachments) {
              if (attachment.deleted) {
                if (attachment.id.isNotEmpty) {
                  wallet.deleteAttachment(attachment.id);
                }
                continue;
              }
              if (attachment.pendingBytes != null) {
                wallet.saveAttachment(
                  cardId: cardId,
                  attachmentId: attachment.id.isEmpty ? null : attachment.id,
                  fileName: attachment.fileName,
                  bytes: attachment.pendingBytes!,
                );
              }
            }
          }));
      final written = await writeBackSpbWallet();
      final persistedAttachments = hasAttachmentChanges
          ? wallet
              .loadAttachments(cardId)
              .map(
                (attachment) => SecretAttachment(
                  id: attachment.id,
                  fileName: attachment.fileName,
                  size: attachment.size,
                  decodeError: attachment.decodeError,
                ),
              )
              .toList(growable: false)
          : List<SecretAttachment>.from(saved.attachments);
      final refreshedCategories =
          needsCategoryRefresh ? wallet.loadCategories() : null;
      _updateShellState(() {
        final persisted = SecretItem(
          id: cardId,
          templateId: saved.templateId,
          title: saved.title,
          category: saved.category,
          colorId: saved.colorId,
          values: Map<String, String>.from(saved.values),
          modifiedAt: saved.modifiedAt,
          attachments: persistedAttachments,
          hitCount: existing?.hitCount ?? 0,
          iconId: saved.iconId,
          backgroundImageBase64: saved.backgroundImageBase64,
          spbColor: saved.spbColor,
          fieldOrder: List<String>.from(saved.fieldOrder),
          hiddenFieldIds: Set<String>.from(saved.hiddenFieldIds),
        );
        if (existing == null) {
          items = [...items, persisted];
        } else {
          items = [
            for (final item in items)
              if (item.id == cardId) persisted else item,
          ];
        }
        itemsById[cardId] = persisted;
        if (refreshedCategories != null) {
          categoryIconsByPath = spbCategoryIconsToUi(refreshedCategories);
          categoryColorsByPath = spbCategoryColorsToUi(refreshedCategories);
          categoryIdsByPath = spbCategoryIdsToUi(refreshedCategories);
          categoryPathsById = {
            for (final entry in categoryIdsByPath.entries)
              entry.value: entry.key,
          };
          categoryPaths = spbCategoryPathsToUi(refreshedCategories);
        }
        selectedItemId = cardId;
        if (written) message = null;
      });
      refreshSpbSearchIndex();
      commitSessionUndo(undoEntry);
      return cardId;
    } catch (error) {
      discardSessionUndo(undoEntry);
      _updateShellState(
          () => message = 'Не удалось сохранить .swl базу: $error');
      return null;
    }
  }
}
