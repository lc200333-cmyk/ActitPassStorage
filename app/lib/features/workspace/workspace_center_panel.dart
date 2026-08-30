part of '../../main.dart';

extension _VaultWorkspaceCenterPanel on _VaultShellState {
  Widget buildSpbFolderGrid() {
    final searchQuery = spbSubmittedSearchQuery;
    final showingSearchResults = searchQuery.isNotEmpty;
    final root = buildCategoryTree(
      showingSearchResults ? items : filteredItems(),
    );
    final node = categoryNodeAt(root, selectedCategoryPath);
    final folders = showingSearchResults
        ? [
            for (final path in spbMatchingFolderPaths(searchQuery))
              if (categoryNodeAt(root, path).path == path)
                categoryNodeAt(root, path),
          ]
        : (node.children.values.toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          ));
    final cards = showingSearchResults
        ? spbMatchingCards(searchQuery)
        : ([...node.cards]..sort(
            (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
          ));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        showingSearchResults
            ? spbSectionHeader(
                'Результаты поиска',
                trailing: const Icon(Icons.search, size: 23),
              )
            : selectedCategoryPath.isEmpty
                ? spbSectionHeader(
                    'Мои карточки',
                    trailing: spbResourceIcon('icon_wallets_small.png', 23),
                  )
                : Container(
                    height: 34,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xffb9dcf5), Color(0xfff2f9fe)],
                      ),
                      border: Border(
                        bottom: BorderSide(
                          color: _VaultShellState._spbBorder,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            categoryParts(selectedCategoryPath).last,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xff18364d),
                              fontSize: 18,
                              fontWeight: FontWeight.normal,
                            ),
                          ),
                        ),
                        spbResourceIcon('icon_wallets_small.png', 23),
                      ],
                    ),
                  ),
        Expanded(
          child: ColoredBox(
            color: selectedCategoryPath.isEmpty ||
                    categoryColorsByPath[selectedCategoryPath] == null
                ? Colors.transparent
                : colorById(categoryColorsByPath[selectedCategoryPath]!).bg,
            child: GestureDetector(
              key: const Key('spbCentralWorkspace'),
              behavior: HitTestBehavior.translucent,
              onSecondaryTapDown: (details) =>
                  showSpbCreationMenu(details.globalPosition),
              onLongPressStart: (details) =>
                  showSpbCreationMenu(details.globalPosition),
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 89.04,
                  mainAxisExtent: 83.475,
                  crossAxisSpacing: 3.975,
                  mainAxisSpacing: 6.36,
                ),
                itemCount: folders.length + cards.length,
                itemBuilder: (context, index) {
                  if (index < folders.length) {
                    final folder = folders[index];
                    return buildSpbGridEntry(
                      label: folder.name,
                      icon: spbSizedDataIcon(
                        folder.iconId ??
                            defaultIconForCategoryPath(folder.path),
                        50.25,
                        fallbackColor: categoryPictogramColor(folder.colorId),
                      ),
                      onTap: () => openSpbFolder(folder.path),
                      onContextMenu: (position) =>
                          showSpbFolderMenu(folder, position),
                    );
                  }
                  final item = cards[index - folders.length];
                  final template = templateFor(item.templateId);
                  final cardEntry = buildSpbGridEntry(
                    label: item.title,
                    labelWidth: 73.3125,
                    selected: selectedItemId == item.id,
                    icon: SizedBox(
                      width: 50.25,
                      height: 50.25,
                      child: Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.center,
                        children: [
                          spbSizedDataIcon(
                            itemIconId(item, template),
                            50.25,
                            fallbackColor: itemPictogramColor(item, template),
                          ),
                          if (item.attachments.any(
                            (attachment) => !attachment.deleted,
                          ))
                            Positioned(
                              key: ValueKey('cardAttachmentArrow-${item.id}'),
                              right: 2,
                              bottom: 2,
                              width: 16.33125,
                              height: 14.586,
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  for (final offset in const [
                                    Offset(-2, 0),
                                    Offset(2, 0),
                                    Offset(0, -2),
                                    Offset(0, 2),
                                    Offset(-1.414, -1.414),
                                    Offset(1.414, -1.414),
                                    Offset(-1.414, 1.414),
                                    Offset(1.414, 1.414),
                                  ])
                                    Transform.translate(
                                      offset: offset,
                                      child: Image.asset(
                                        'assets/branding/attachment_arrow.png',
                                        width: 16.33125,
                                        height: 14.586,
                                        fit: BoxFit.fill,
                                        color: Colors.white,
                                        colorBlendMode: BlendMode.srcIn,
                                      ),
                                    ),
                                  ShaderMask(
                                    blendMode: BlendMode.srcIn,
                                    shaderCallback: (bounds) =>
                                        const LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        Color(0xffff4fa3),
                                        Color(0xffe6007e),
                                        Color(0xffa8005b),
                                      ],
                                    ).createShader(bounds),
                                    child: Image.asset(
                                      'assets/branding/attachment_arrow.png',
                                      width: 16.33125,
                                      height: 14.586,
                                      fit: BoxFit.fill,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    onTap: () => openCardPreviewDialog(item),
                    onContextMenu: (position) =>
                        showSpbCardMenu(item, position),
                  );
                  return KeyedSubtree(
                    key: ValueKey('spbCentralCard-${item.id}'),
                    child: Draggable<SecretItem>(
                      data: item,
                      maxSimultaneousDrags: spbWallet == null ? 0 : 1,
                      dragAnchorStrategy: pointerDragAnchorStrategy,
                      feedback: Material(
                        color: Colors.transparent,
                        child: Container(
                          width: 104,
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xffedf7fe),
                            border: Border.all(color: const Color(0xff367ca8)),
                            boxShadow: const [
                              BoxShadow(color: Colors.black26, blurRadius: 6),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              spbSizedDataIcon(
                                itemIconId(item, template),
                                42,
                                fallbackColor:
                                    itemPictogramColor(item, template),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                item.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                      childWhenDragging: Opacity(
                        opacity: 0.35,
                        child: cardEntry,
                      ),
                      child: cardEntry,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> showSpbCreationMenu(Offset globalPosition) async {
    if (spbObjectMenuPointerActive) return;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          value: 'card',
          child: Row(
            children: [
              spbResourceIcon('icon_add_card.png', 24),
              const SizedBox(width: 9),
              const Flexible(child: Text('Создать карточку')),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'folder',
          child: Row(
            children: [
              spbResourceIcon('icon_add_folder.png', 24),
              const SizedBox(width: 9),
              const Flexible(child: Text('Создать папку')),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'import',
          child: Row(
            children: [
              Icon(Icons.file_open_outlined, size: 24),
              SizedBox(width: 9),
              Flexible(child: Text('Импорт')),
            ],
          ),
        ),
      ],
    );
    if (!mounted) return;
    if (selected == 'card') {
      await openItemDialog(initialCategory: selectedCategoryPath);
    } else if (selected == 'folder') {
      await openCategoryEditorDialog(
        folder: null,
        parentPath: selectedCategoryPath,
      );
    } else if (selected == 'import') {
      await importSpbWalletCards();
    }
  }

  Future<void> showSpbFolderMenu(
    CategoryTreeNode folder,
    Offset globalPosition,
  ) async {
    if (spbContextMenuOpen) return;
    spbContextMenuOpen = true;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    String? selected;
    try {
      selected = await showMenu<String>(
        context: context,
        position: RelativeRect.fromRect(
          Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 1, 1),
          Offset.zero & overlay.size,
        ),
        items: const [
          PopupMenuItem(
            key: Key('viewFolderContextAction'),
            value: 'view',
            child: Text('Просмотр'),
          ),
          PopupMenuItem(
            key: Key('createInFolderContextAction'),
            value: 'create',
            child: Text('Создать'),
          ),
          PopupMenuItem(
            key: Key('editFolderContextAction'),
            value: 'edit',
            child: Text('Редактировать'),
          ),
          PopupMenuItem(
            key: Key('moveFolderContextAction'),
            value: 'move',
            child: Text('Переместить'),
          ),
          PopupMenuItem(
            key: Key('exportFolderContextAction'),
            value: 'export',
            child: Text('Экспортировать'),
          ),
          PopupMenuItem(
            key: Key('importFolderContextAction'),
            value: 'import',
            child: Text('Импортировать'),
          ),
        ],
      );
    } finally {
      spbContextMenuOpen = false;
    }
    if (!mounted || selected == null) return;
    switch (selected) {
      case 'view':
        openSpbFolder(folder.path);
        break;
      case 'create':
        await openItemDialog(initialCategory: folder.path);
        break;
      case 'edit':
        await openCategoryEditorDialog(folder: folder);
        break;
      case 'move':
        await moveSpbFolder(folder);
        break;
      case 'export':
        await exportSpbItems(
          items
              .where(
                (item) =>
                    item.category == folder.path ||
                    item.category.startsWith('${folder.path} / '),
              )
              .toList(),
          suggestedName: folder.name,
          categoryPath: folder.path,
        );
        break;
      case 'import':
        await importSpbWalletCards();
        break;
    }
  }

  Future<void> showSpbCardMenu(SecretItem item, Offset globalPosition) async {
    if (spbContextMenuOpen) return;
    spbContextMenuOpen = true;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    String? selected;
    try {
      selected = await showMenu<String>(
        context: context,
        position: RelativeRect.fromRect(
          Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 1, 1),
          Offset.zero & overlay.size,
        ),
        items: const [
          PopupMenuItem(
            key: Key('viewCardContextAction'),
            value: 'view',
            child: Text('Просмотр'),
          ),
          PopupMenuItem(
            key: Key('createCardContextAction'),
            value: 'create',
            child: Text('Создать'),
          ),
          PopupMenuItem(
            key: Key('editCardContextAction'),
            value: 'edit',
            child: Text('Редактировать'),
          ),
          PopupMenuItem(
            key: Key('copyCardContextAction'),
            value: 'copy',
            child: Text('Копировать'),
          ),
          PopupMenuItem(
            key: Key('moveCardContextAction'),
            value: 'move',
            child: Text('Переместить'),
          ),
          PopupMenuItem(
            key: Key('exportObjectContextAction'),
            value: 'export',
            child: Text('Экспортировать'),
          ),
          PopupMenuItem(
            key: Key('importCardContextAction'),
            value: 'import',
            child: Text('Импортировать'),
          ),
          PopupMenuItem(
            key: Key('deleteCardContextAction'),
            value: 'delete',
            child: Text('Удалить'),
          ),
        ],
      );
    } finally {
      spbContextMenuOpen = false;
    }
    if (!mounted || selected == null) return;
    switch (selected) {
      case 'view':
        await openCardPreviewDialog(item);
        break;
      case 'create':
        await openItemDialog(initialCategory: item.category);
        break;
      case 'edit':
        await openItemDialog(item: item);
        break;
      case 'export':
        await exportSpbItems([item], suggestedName: item.title);
        break;
      case 'copy':
        await cloneSpbCard(item);
        break;
      case 'move':
        await moveSpbCard(item);
        break;
      case 'import':
        await importSpbWalletCards();
        break;
      case 'delete':
        await deleteItemWithConfirmation(item);
        break;
    }
  }

  Future<String?> _showMoveTargetDialogImpl({
    required String initialPath,
    Set<String> excludedPaths = const {},
  }) {
    var selectedPath = excludedPaths.contains(initialPath) ? '' : initialPath;
    final targets = <String>[
      '',
      ...categoryPaths.where((path) => !excludedPaths.contains(path)),
    ]..sort((a, b) {
        if (a.isEmpty) return -1;
        if (b.isEmpty) return 1;
        return a.toLowerCase().compareTo(b.toLowerCase());
      });
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final media = MediaQuery.sizeOf(context);
          final compact = Platform.isAndroid ||
              Theme.of(context).platform == TargetPlatform.android ||
              media.width < 700;
          return Dialog(
            insetPadding: compact ? EdgeInsets.zero : const EdgeInsets.all(24),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.zero,
              side: BorderSide(color: Color(0xff7f8d98)),
            ),
            child: SizedBox(
              key: const Key('moveTargetSurface'),
              width: compact ? media.width : min(media.width - 48, 440),
              height: compact ? media.height : min(media.height - 48, 620),
              child: SafeArea(
                child: Column(
                  children: [
                    Container(
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      alignment: Alignment.centerLeft,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xffa9c9e3), Color(0xffe9f1f8)],
                        ),
                        border: Border(
                          bottom: BorderSide(color: Color(0xff7f8d98)),
                        ),
                      ),
                      child: const Text(
                        'Выберите папку',
                        style: TextStyle(fontSize: 19),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        key: const Key('moveTargetFolderList'),
                        itemCount: targets.length,
                        itemBuilder: (context, index) {
                          final path = targets[index];
                          final depth = categoryParts(path).length;
                          final selected = selectedPath == path;
                          return Padding(
                            padding: EdgeInsets.only(left: depth * 14.0),
                            child: ListTile(
                              key: ValueKey('moveTarget-$path'),
                              selected: selected,
                              selectedTileColor: const Color(0xffcfe9fb),
                              leading: path.isEmpty
                                  ? const Icon(Icons.account_balance_wallet)
                                  : categoryFolderIcon(
                                      categoryIconsByPath[path] ??
                                          defaultIconForCategoryPath(path),
                                      categoryColorsByPath[path],
                                    ),
                              title: Text(
                                path.isEmpty
                                    ? 'Мои карточки'
                                    : categoryParts(path).last,
                              ),
                              onTap: () =>
                                  setDialogState(() => selectedPath = path),
                            ),
                          );
                        },
                      ),
                    ),
                    Container(
                      height: 64,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: const BoxDecoration(
                        color: Color(0xffdce8f1),
                        border: Border(
                          top: BorderSide(color: Color(0xff7f8d98)),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          SpbGradientActionButton(
                            key: const Key('cancelMoveButton'),
                            icon: Icons.close,
                            tooltip: 'Отменить перемещение',
                            colors: const [
                              Color(0xffff5a5f),
                              Color(0xffa90000),
                            ],
                            onTap: () => Navigator.pop(dialogContext),
                          ),
                          const SizedBox(width: 6),
                          SpbGradientActionButton(
                            key: const Key('confirmMoveButton'),
                            icon: Icons.check,
                            tooltip: 'Подтвердить перемещение',
                            colors: const [
                              Color(0xff5bc96d),
                              Color(0xff08772f),
                            ],
                            onTap: () =>
                                Navigator.pop(dialogContext, selectedPath),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> moveSpbCard(SecretItem item) async {
    final wallet = spbWallet;
    if (wallet == null || !ensureSpbWalletWritable()) return;
    final target = await showMoveTargetDialog(initialPath: item.category);
    if (target == null || target == item.category || !mounted) return;
    await moveSpbCardTo(item, target);
  }

  Future<void> moveSpbCardTo(SecretItem item, String target) async {
    final wallet = spbWallet;
    if (wallet == null || !ensureSpbWalletWritable()) return;
    if (target == item.category || !mounted) return;
    SessionUndoEntry? undoEntry;
    try {
      undoEntry = await captureSessionUndo(
        'Перемещение карточки: ${item.title}',
        itemIconId(item, templateFor(item.templateId)),
      );
      await mutateVault<void>(() => wallet.moveCard(item.id, target));
      final written = await writeBackSpbWallet();
      _updateShellState(() {
        final moved = SecretItem(
          id: item.id,
          templateId: item.templateId,
          title: item.title,
          category: target,
          colorId: item.colorId,
          values: item.values,
          modifiedAt: DateTime.now().toUtc(),
          attachments: item.attachments,
          hitCount: item.hitCount,
          iconId: item.iconId,
          backgroundImageBase64: item.backgroundImageBase64,
          spbColor: item.spbColor,
          fieldOrder: item.fieldOrder,
          hiddenFieldIds: item.hiddenFieldIds,
        );
        items = [
          for (final entry in items)
            if (entry.id == item.id) moved else entry,
        ];
        itemsById[item.id] = moved;
        selectedCategoryPath = target;
        selectedItemId = item.id;
        if (written) message = null;
      });
      refreshSpbSearchIndex();
      commitSessionUndo(undoEntry);
    } catch (error) {
      discardSessionUndo(undoEntry);
      _updateShellState(
          () => message = 'Не удалось переместить карточку: $error');
    }
  }

  Widget buildSpbCardDropTarget({
    required String categoryPath,
    required Widget child,
  }) {
    return DragTarget<SecretItem>(
      onWillAcceptWithDetails: (details) =>
          details.data.category != categoryPath && spbWallet != null,
      onAcceptWithDetails: (details) {
        unawaited(moveSpbCardTo(details.data, categoryPath));
      },
      builder: (context, candidates, rejected) => AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: candidates.isEmpty
            ? null
            : BoxDecoration(
                color: const Color(0xffd7f4df),
                border: Border.all(color: const Color(0xff16833c), width: 2),
              ),
        child: child,
      ),
    );
  }

  Future<void> moveSpbFolder(CategoryTreeNode folder) async {
    final wallet = spbWallet;
    if (wallet == null || !ensureSpbWalletWritable()) return;
    final parentParts = categoryParts(folder.path);
    if (parentParts.isNotEmpty) parentParts.removeLast();
    final currentParent = parentParts.join(' / ');
    final excluded = categoryPaths
        .where(
          (path) => path == folder.path || path.startsWith('${folder.path} / '),
        )
        .toSet();
    final target = await showMoveTargetDialog(
      initialPath: currentParent,
      excludedPaths: excluded,
    );
    if (target == null || target == currentParent || !mounted) return;
    SessionUndoEntry? undoEntry;
    try {
      undoEntry = await captureSessionUndo(
        'Перемещение папки: ${folder.name}',
        folder.iconId ?? defaultIconForCategoryPath(folder.path),
      );
      await mutateVault<void>(() => wallet.moveCategory(folder.path, target));
      final written = await writeBackSpbWallet();
      final snapshot = wallet.loadSnapshot();
      final newPath = [if (target.isNotEmpty) target, folder.name].join(' / ');
      _updateShellState(() {
        applySpbSnapshot(snapshot);
        selectedCategoryPath = newPath;
        if (written) message = null;
      });
      commitSessionUndo(undoEntry);
    } catch (error) {
      discardSessionUndo(undoEntry);
      _updateShellState(() => message = 'Не удалось переместить папку: $error');
    }
  }

  Widget buildSpbGridEntry({
    required String label,
    required Widget icon,
    required VoidCallback onTap,
    VoidCallback? onDoubleTap,
    required ValueChanged<Offset> onContextMenu,
    bool selected = false,
    double labelWidth = 63.75,
  }) {
    return GestureDetector(
      onSecondaryTapDown: (details) =>
          openSpbObjectContextMenu(onContextMenu, details.globalPosition),
      onLongPressStart: (details) =>
          openSpbObjectContextMenu(onContextMenu, details.globalPosition),
      child: InkWell(
        onTap: onTap,
        onDoubleTap: onDoubleTap,
        child: Container(
          decoration: selected
              ? const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xffb9dcf5), Color(0xffedf7fe)],
                  ),
                )
              : null,
          child: OverflowBox(
            alignment: Alignment.topCenter,
            minWidth: 112,
            maxWidth: 112,
            minHeight: 105,
            maxHeight: 105,
            child: Column(
              children: [
                SizedBox(width: 68, height: 67, child: Center(child: icon)),
                const SizedBox(height: 2),
                SizedBox(
                  width: labelWidth,
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14.3, height: 1.05),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void openSpbObjectContextMenu(
    ValueChanged<Offset> onContextMenu,
    Offset globalPosition,
  ) {
    spbObjectMenuPointerActive = true;
    scheduleMicrotask(() => spbObjectMenuPointerActive = false);
    onContextMenu(globalPosition);
  }

  Future<String?> askSpbExportPassword() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Экспорт в SWL'),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          enableSuggestions: false,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Пароль (необязательно)',
            helperText: 'Оставьте поле пустым для экспорта без пароля',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => Navigator.pop(dialogContext, controller.text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Экспорт'),
          ),
        ],
      ),
    );
    controller.clear();
    controller.dispose();
    return result;
  }

  Future<String?> askSpbImportPassword() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Введите пароль SWL'),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          enableSuggestions: false,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Пароль',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => Navigator.pop(dialogContext, controller.text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Открыть'),
          ),
        ],
      ),
    );
    controller.clear();
    controller.dispose();
    return result;
  }

  String safeSpbFileName(String value) {
    final safe = value.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    return '${safe.isEmpty ? 'Экспорт' : safe}.swl';
  }

  Future<File> _createSpbItemsExportFileImpl(
    List<SecretItem> exportItems, {
    required String password,
    String? categoryPath,
    String? targetPath,
  }) async {
    final file = targetPath == null
        ? File(
            '${(await getTemporaryDirectory()).path}${Platform.pathSeparator}'
            'wallet_aps_export_${DateTime.now().microsecondsSinceEpoch}.swl',
          )
        : File(targetPath);
    final exportWallet = SpbWalletDatabase.create(file.path, password);
    try {
      if (categoryPath != null && categoryPath.trim().isNotEmpty) {
        exportWallet.ensureCategoryPath(categoryPath);
      }
      final templateIds = <String, String>{};
      final fieldIds = <String, Map<String, String>>{};
      for (final item in exportItems) {
        if (templateIds.containsKey(item.templateId)) continue;
        final template = templateFor(item.templateId);
        final exportedTemplateId = SpbWalletDatabase.makeId();
        final exportedFieldIds = <String, String>{
          for (final field in template.fields)
            if (field.id != spbDescriptionFieldId)
              field.id: SpbWalletDatabase.makeId(),
        };
        templateIds[item.templateId] = exportedTemplateId;
        fieldIds[item.templateId] = exportedFieldIds;
        exportWallet.saveTemplate(
          SpbWalletTemplateDraft(
            id: exportedTemplateId,
            name: template.name,
            iconId: spbIconIdForUi(template.iconId, template.iconId),
            fields: [
              for (final field in template.fields)
                if (field.id != spbDescriptionFieldId)
                  SpbWalletTemplateFieldRecord(
                    id: exportedFieldIds[field.id]!,
                    name: field.label,
                    templateId: exportedTemplateId,
                    fieldTypeId: spbFieldTypeId(field),
                  ),
            ],
          ),
        );
      }
      for (final item in exportItems) {
        final template = templateFor(item.templateId);
        final exportedFieldIds = fieldIds[item.templateId]!;
        final cardId = SpbWalletDatabase.makeId();
        exportWallet.saveCard(
          SpbWalletCardDraft(
            id: cardId,
            title: item.title,
            description: item.values[spbDescriptionFieldId] ?? '',
            categoryPath: item.category,
            templateId: templateIds[item.templateId]!,
            fieldValues: {
              for (final field in template.fields)
                if (field.id != spbDescriptionFieldId &&
                    (item.values[field.id]?.isNotEmpty ?? false))
                  exportedFieldIds[field.id]!: item.values[field.id]!,
            },
            iconId: spbIconIdForUi(itemIconId(item, template), template.iconId),
            cardColor: item.spbColor ?? paletteColorToSpb(item.colorId),
            backgroundImageBase64: item.backgroundImageBase64,
          ),
        );
        for (final attachment in item.attachments) {
          if (attachment.deleted) continue;
          final bytes = attachment.pendingBytes ??
              (attachment.id.isEmpty || spbWallet == null
                  ? null
                  : spbWallet!.readAttachmentBytes(attachment.id));
          if (bytes == null) continue;
          exportWallet.saveAttachment(
            cardId: cardId,
            fileName: attachment.fileName,
            bytes: bytes,
          );
        }
      }
    } finally {
      exportWallet.close();
    }
    return file;
  }

  Future<void> exportSpbItems(
    List<SecretItem> exportItems, {
    required String suggestedName,
    String? categoryPath,
  }) async {
    final password = await askSpbExportPassword();
    if (password == null) return;
    File? temporary;
    try {
      temporary = await createSpbItemsExportFile(
        exportItems,
        password: password,
        categoryPath: categoryPath,
      );
      final data = await temporary.readAsBytes();
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Экспорт в SWL',
        fileName: safeSpbFileName(suggestedName),
        type: FileType.custom,
        allowedExtensions: const ['swl'],
        bytes: data,
      );
      if (path == null) return;
      if (!Platform.isAndroid && !Platform.isIOS) {
        final outputPath =
            path.toLowerCase().endsWith('.swl') ? path : '$path.swl';
        final output = File(outputPath);
        if (!output.existsSync() || output.lengthSync() != data.length) {
          await output.writeAsBytes(data, flush: true);
        }
      }
    } catch (error) {
      showSpbOperationMessage('Не удалось экспортировать SWL: $error');
    } finally {
      if (temporary != null && temporary.existsSync()) {
        temporary.deleteSync();
      }
    }
  }

  Future<void> cloneSpbCard(SecretItem item) async {
    final wallet = spbWallet;
    if (wallet == null || !ensureSpbWalletWritable()) return;
    final existingTitles = items.map((entry) => entry.title).toSet();
    var suffix = 1;
    var cloneTitle = '${item.title} ($suffix)';
    while (existingTitles.contains(cloneTitle)) {
      suffix++;
      cloneTitle = '${item.title} ($suffix)';
    }
    final clonedAttachments = <SecretAttachment>[];
    try {
      for (final attachment in item.attachments) {
        final bytes = wallet.readAttachmentBytes(attachment.id);
        clonedAttachments.add(
          SecretAttachment(
            id: '',
            fileName: attachment.fileName,
            size: bytes.length,
            pendingBytes: bytes,
          ),
        );
      }
      final clone = SecretItem(
        id: makeId('item'),
        templateId: item.templateId,
        title: cloneTitle,
        category: item.category,
        colorId: item.colorId,
        values: Map<String, String>.from(item.values),
        modifiedAt: DateTime.now().toUtc(),
        attachments: clonedAttachments,
        iconId: item.iconId,
        backgroundImageBase64: item.backgroundImageBase64,
        spbColor: item.spbColor,
        fieldOrder: item.fieldOrder,
        hiddenFieldIds: item.hiddenFieldIds,
      );
      final savedId = await persistItem(clone);
      if (savedId != null) {
        showSpbOperationMessage('Создана копия карточки «$cloneTitle».');
      }
    } catch (error) {
      showSpbOperationMessage('Не удалось скопировать карточку: $error');
    }
  }

  Future<void> importSpbWalletCards() async {
    final destination = spbWallet;
    if (destination == null) {
      showSpbOperationMessage('Сначала откройте базу, в которую нужен импорт.');
      return;
    }
    if (!ensureSpbWalletWritable()) return;
    File? temporary;
    SpbWalletDatabase? source;
    SessionUndoEntry? undoEntry;
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['swl'],
        withData: true,
      );
      final selected = picked?.files.single;
      if (selected == null) return;
      String sourcePath;
      if (selected.path != null && File(selected.path!).existsSync()) {
        sourcePath = selected.path!;
      } else {
        final bytes = selected.bytes;
        if (bytes == null) {
          throw const FormatException('Не удалось прочитать SWL.');
        }
        final directory = await getTemporaryDirectory();
        temporary = File(
          '${directory.path}${Platform.pathSeparator}'
          'wallet_aps_import_${DateTime.now().microsecondsSinceEpoch}.swl',
        );
        await temporary.writeAsBytes(bytes, flush: true);
        sourcePath = temporary.path;
      }
      try {
        source = SpbWalletDatabase.open(sourcePath, '');
      } catch (_) {
        final password = await askSpbImportPassword();
        if (password == null) return;
        source = SpbWalletDatabase.open(sourcePath, password);
      }
      final snapshot = source.loadSnapshot();
      undoEntry = await captureSessionUndo(
        'Импорт карточек: ${snapshot.cards.length}',
        'folder',
      );
      final templateIds = <String, String>{};
      final fieldIds = <String, Map<String, String>>{};
      if (snapshot.templates.isNotEmpty || snapshot.cards.isNotEmpty) {
        await mutateVault<void>(() => destination.runTransaction<void>(() {
              for (final template in snapshot.templates) {
                final importedTemplateId = SpbWalletDatabase.makeId();
                final importedFieldIds = <String, String>{
                  for (final field in template.fields)
                    field.id: SpbWalletDatabase.makeId(),
                };
                templateIds[template.id] = importedTemplateId;
                fieldIds[template.id] = importedFieldIds;
                destination.saveTemplate(
                  SpbWalletTemplateDraft(
                    id: importedTemplateId,
                    name: template.name,
                    iconId: template.iconId,
                    fields: [
                      for (final field in template.fields)
                        SpbWalletTemplateFieldRecord(
                          id: importedFieldIds[field.id]!,
                          name: field.name,
                          templateId: importedTemplateId,
                          fieldTypeId: field.fieldTypeId,
                        ),
                    ],
                  ),
                );
              }
              for (final card in snapshot.cards) {
                final importedTemplateId = templateIds[card.templateId];
                final importedFieldIds = fieldIds[card.templateId];
                if (importedTemplateId == null || importedFieldIds == null) {
                  continue;
                }
                final cardId = SpbWalletDatabase.makeId();
                destination.saveCard(
                  SpbWalletCardDraft(
                    id: cardId,
                    title: card.title,
                    description: card.description,
                    categoryPath: card.categoryPath,
                    templateId: importedTemplateId,
                    fieldValues: {
                      for (final entry in card.fieldValues.entries)
                        if (importedFieldIds[entry.key] != null)
                          importedFieldIds[entry.key]!: entry.value,
                    },
                    iconId: card.iconId,
                    cardColor: card.cardColor,
                    backgroundImageBase64: card.backgroundImageBase64,
                  ),
                );
                for (final attachment in card.attachments) {
                  destination.saveAttachment(
                    cardId: cardId,
                    fileName: attachment.fileName,
                    bytes: source!.readAttachmentBytes(attachment.id),
                  );
                }
              }
            }));
      }
      final written = await writeBackSpbWallet();
      final updated = destination.loadSnapshot();
      _updateShellState(() => applySpbSnapshot(updated));
      commitSessionUndo(undoEntry);
      showSpbOperationMessage(
        written
            ? 'Импортировано карточек: ${snapshot.cards.length}'
            : 'Карточки импортированы в рабочую копию, но исходный файл '
                'записать не удалось.',
      );
    } catch (error) {
      discardSessionUndo(undoEntry);
      showSpbOperationMessage('Не удалось импортировать SWL: $error');
    } finally {
      source?.close(flush: false);
      if (temporary != null && temporary.existsSync()) {
        temporary.deleteSync();
      }
    }
  }

  void showSpbOperationMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(text), duration: const Duration(seconds: 3)),
      );
  }
}
