part of '../../main.dart';

extension _VaultWorkspaceNavigationPanel on _VaultShellState {
  Widget buildSpbDesktopShell() {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            const rightDividerWidth = 1.0;
            const minimumNavigatorWidth = 416.0;
            const minimumCenterWidth = 160.0;
            const minimumRightPanelWidth = 180.0;
            const splitterHitWidth = 9.0;
            final defaultRightPanelWidth = constraints.maxWidth * 0.20;
            final maximumRightPanelWidth = max(
              minimumRightPanelWidth,
              constraints.maxWidth -
                  rightDividerWidth * 2 -
                  minimumNavigatorWidth -
                  minimumCenterWidth,
            );
            final rightPanelWidth =
                (spbActionsPanelWidth ?? defaultRightPanelWidth)
                    .clamp(minimumRightPanelWidth, maximumRightPanelWidth)
                    .toDouble();
            final maximumNavigatorWidth = max(
              minimumNavigatorWidth,
              constraints.maxWidth -
                  rightDividerWidth * 2 -
                  rightPanelWidth -
                  minimumCenterWidth,
            );
            final defaultNavigatorWidth = constraints.maxWidth * 0.30;
            final navigatorWidth = (spbNavigatorWidth ?? defaultNavigatorWidth)
                .clamp(minimumNavigatorWidth, maximumNavigatorWidth)
                .toDouble();
            return Column(
              children: [
                buildSpbSearchBar(
                  desktopNavigatorWidth: navigatorWidth,
                  desktopActionsPanelWidth: rightPanelWidth,
                ),
                Expanded(
                  child: Stack(
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: navigatorWidth,
                            child:
                                spbWorkspaceScrollbarTheme(buildSpbNavigator()),
                          ),
                          const VerticalDivider(width: 1, thickness: 1),
                          Expanded(
                            child: spbWorkspaceScrollbarTheme(
                              mobileTemplatesOpen
                                  ? buildSpbTemplateWorkspace()
                                  : buildSpbFolderGrid(),
                            ),
                          ),
                          const VerticalDivider(width: 1, thickness: 1),
                          SizedBox(
                            width: rightPanelWidth,
                            child: spbWorkspaceScrollbarTheme(
                              buildSpbActionsPanel(desktop: true),
                            ),
                          ),
                        ],
                      ),
                      Positioned(
                        left: navigatorWidth - (splitterHitWidth - 1) / 2,
                        top: 0,
                        bottom: 0,
                        width: splitterHitWidth,
                        child: MouseRegion(
                          cursor: SystemMouseCursors.resizeColumn,
                          child: GestureDetector(
                            key: const Key('spbNavigatorSplitter'),
                            behavior: HitTestBehavior.opaque,
                            onHorizontalDragUpdate: (details) {
                              _updateShellState(() {
                                spbNavigatorWidth =
                                    (navigatorWidth + details.delta.dx)
                                        .clamp(
                                          minimumNavigatorWidth,
                                          maximumNavigatorWidth,
                                        )
                                        .toDouble();
                              });
                            },
                          ),
                        ),
                      ),
                      Positioned(
                        left: constraints.maxWidth -
                            rightPanelWidth -
                            rightDividerWidth -
                            (splitterHitWidth - 1) / 2,
                        top: 0,
                        bottom: 0,
                        width: splitterHitWidth,
                        child: MouseRegion(
                          cursor: SystemMouseCursors.resizeColumn,
                          child: GestureDetector(
                            key: const Key('spbActionsPanelSplitter'),
                            behavior: HitTestBehavior.opaque,
                            onHorizontalDragUpdate: (details) {
                              _updateShellState(() {
                                spbActionsPanelWidth =
                                    (rightPanelWidth - details.delta.dx)
                                        .clamp(
                                          minimumRightPanelWidth,
                                          maximumRightPanelWidth,
                                        )
                                        .toDouble();
                              });
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget buildSpbMobileShell() {
    final paneTitle = mobileTemplatesOpen
        ? switch (mobilePane) {
            2 => 'Задачи',
            _ => 'Шаблоны',
          }
        : switch (mobilePane) {
            1 => selectedCategoryPath.isEmpty
                ? selectedVaultTitle
                : categoryParts(selectedCategoryPath).last,
            2 => 'Задачи',
            _ => 'Мои карточки',
          };
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              height: 54,
              color: const Color(0xff7d7d7d),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  Image.asset(
                    'assets/branding/wallet_android.png',
                    key: const Key('spbMobileAppIcon'),
                    width: 40,
                    height: 40,
                    cacheWidth: 128,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      selectedVaultTitle,
                      key: const Key('spbMobileWalletTitle'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            buildSpbSearchBar(mobile: true),
            if (mobilePane == 0)
              GestureDetector(
                key: const Key('spbMobilePaneHeader'),
                behavior: HitTestBehavior.opaque,
                onTap: mobileTemplatesOpen
                    ? null
                    : () => _updateShellState(() {
                          selectedCategoryPath = '';
                          selectedCategoryId = null;
                          mobilePane = 1;
                        }),
                child: spbSectionHeader(paneTitle, height: 42),
              ),
            Expanded(
              child: spbWorkspaceScrollbarTheme(
                mobileTemplatesOpen
                    ? switch (mobilePane) {
                        1 => buildSpbTemplateWorkspace(showHeader: false),
                        2 => buildSpbActionsPanel(),
                        _ => buildSpbTemplateTree(),
                      }
                    : switch (mobilePane) {
                        1 => buildSpbFolderGrid(),
                        2 => buildSpbActionsPanel(),
                        _ => buildSpbTreeBody(showWalletRoot: false),
                      },
              ),
            ),
            if (mobilePane == 0) ...[
              buildSpbModeButton(
                label: 'Мои карточки',
                iconFile: 'icon_wallets.png',
                selected: !mobileTemplatesOpen,
                onTap: showSpbCardsMode,
              ),
              buildSpbModeButton(
                label: 'Шаблоны',
                iconFile: 'icon_templates.png',
                selected: mobileTemplatesOpen,
                onTap: showSpbTemplatesMode,
              ),
            ],
            buildSpbMobileArrows(
              allowBack: mobilePane > 0,
              allowForward: mobilePane < 2,
            ),
          ],
        ),
      ),
    );
  }

  Widget buildSpbMobileArrows({
    required bool allowBack,
    required bool allowForward,
  }) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: const BoxDecoration(
        color: Color(0xfff4f4f4),
        border: Border(
          top: BorderSide(color: _VaultShellState._spbBorder),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _Spb3dArrowButton(
            key: const Key('mobilePaneBack'),
            icon: Icons.arrow_left,
            onPressed:
                allowBack ? () => _updateShellState(() => mobilePane--) : null,
          ),
          _Spb3dArrowButton(
            key: const Key('mobileFolderUp'),
            icon: Icons.arrow_drop_up,
            onPressed: !mobileTemplatesOpen &&
                    mobilePane == 1 &&
                    selectedCategoryPath.isNotEmpty
                ? openParentSpbFolder
                : null,
          ),
          _Spb3dArrowButton(
            key: const Key('mobilePaneForward'),
            icon: Icons.arrow_right,
            onPressed: allowForward
                ? () => _updateShellState(() => mobilePane++)
                : null,
          ),
        ],
      ),
    );
  }

  void openParentSpbFolder() {
    openSpbFolder(navigationController.parentPath(selectedCategoryPath));
  }

  void openSpbFolder(String path) {
    final size = MediaQuery.sizeOf(context);
    final mobile = defaultTargetPlatform == TargetPlatform.android
        ? size.height >= size.width
        : size.width < 700;
    _updateShellState(() {
      navigationController.selectCategory(path, categoryIdsByPath);
      if (mobile) mobilePane = 1;
    });
  }

  void showSpbCardsMode() {
    _updateShellState(navigationController.showCardsMode);
  }

  void showSpbTemplatesMode() {
    searchController.clear();
    _updateShellState(() {
      navigationController.showTemplatesMode();
      spbSubmittedSearchQuery = '';
      if (templates.isNotEmpty &&
          !templates.any((template) => template.id == selectedTemplateId)) {
        selectedTemplateId = templates.first.id;
      }
    });
  }

  Widget buildSpbNavigator() {
    return Material(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            key: const Key('spbVaultTitle'),
            onTap: () {
              searchController.clear();
              _updateShellState(() {
                spbSubmittedSearchQuery = '';
                selectedCategoryPath = '';
                selectedCategoryId = null;
              });
            },
            child: spbSectionHeader(
              selectedVaultTitle,
              leading: Image.asset(
                'assets/branding/wallet_android.png',
                key: const Key('spbDesktopAppIcon'),
                width: 28,
                height: 28,
                cacheWidth: 96,
                fit: BoxFit.contain,
              ),
              bold: true,
            ),
          ),
          Expanded(
            child: mobileTemplatesOpen
                ? buildSpbTemplateTree(compactRows: true)
                : buildSpbTreeBody(compactRows: true, showWalletRoot: false),
          ),
          buildSpbModeButton(
            label: 'Мои карточки',
            iconFile: 'icon_wallets.png',
            selected: !mobileTemplatesOpen,
            onTap: showSpbCardsMode,
          ),
          buildSpbModeButton(
            label: 'Шаблоны',
            iconFile: 'icon_templates.png',
            selected: mobileTemplatesOpen,
            onTap: showSpbTemplatesMode,
          ),
        ],
      ),
    );
  }

  Widget buildSpbModeButton({
    required String label,
    required String iconFile,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected ? const Color(0xffdbeaf5) : const Color(0xfff5f5f5),
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: const BoxDecoration(
            border: Border(
              top: BorderSide(color: _VaultShellState._spbBorder),
            ),
          ),
          child: Row(
            children: [
              spbResourceIcon(iconFile, 40),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 17),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget spbExpansionMark(bool expanded) {
    return Container(
      width: 15,
      height: 15,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xfff5f5f5),
        border: Border.all(color: const Color(0xff8d9aa3)),
      ),
      child: expanded
          ? const Text(
              '−',
              style: TextStyle(
                color: Color(0xff526b7d),
                fontSize: 15,
                height: 0.9,
                fontWeight: FontWeight.w700,
              ),
            )
          : const Icon(
              Icons.add,
              color: Color(0xff526b7d),
              size: 13,
              weight: 700,
            ),
    );
  }

  Widget buildSpbTreeBody({
    bool compactRows = false,
    bool showWalletRoot = true,
  }) {
    final query = searchController.text.trim();
    final root = buildCategoryTree(
      filteredItems(),
      includeAllCategories: query.isEmpty,
      additionalPaths: query.isEmpty ? const [] : spbMatchingFolderPaths(query),
    );
    final visibleEntries = buildSpbVisibleTreeEntries(
      root,
      showWalletRoot: showWalletRoot,
    );
    return ListView.builder(
      key: const Key('spbCategoryTreeList'),
      padding: const EdgeInsets.fromLTRB(5, 10, 5, 12),
      itemCount: visibleEntries.length,
      itemBuilder: (context, index) => buildSpbVisibleTreeEntry(
        visibleEntries[index],
        compactRows: compactRows,
      ),
    );
  }

  List<SpbVisibleTreeEntry> _buildSpbVisibleTreeEntriesImpl(
    CategoryTreeNode root, {
    required bool showWalletRoot,
  }) {
    return navigationController.visibleEntries(
      root,
      showWalletRoot: showWalletRoot,
      sortValueOf: (item) => item.title,
    );
  }

  Widget buildSpbVisibleTreeEntry(
    SpbVisibleTreeEntry entry, {
    required bool compactRows,
  }) {
    if (entry.isRoot) {
      return ListTile(
        dense: true,
        minTileHeight: 48,
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        leading: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () =>
              _updateShellState(() => rootTreeExpanded = !rootTreeExpanded),
          child: SizedBox(
            width: 48,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [spbResourceIcon('icon_wallets_small.png', 40)],
            ),
          ),
        ),
        title: buildSpbCardDropTarget(
          categoryPath: '',
          child: GestureDetector(
            key: const Key('spbWalletRoot'),
            behavior: HitTestBehavior.opaque,
            onTap: () => openSpbFolder(''),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
              decoration: selectedCategoryPath.isEmpty
                  ? const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xffc9e5f8), Color(0xffeef8ff)],
                      ),
                    )
                  : null,
              child: Text(
                selectedVaultTitle,
                style: const TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w700,
                  fontStyle: FontStyle.italic,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
        ),
      );
    }

    final folder = entry.folder;
    if (folder != null) {
      final expanded = navigationController.isFolderExpanded(folder);
      return Padding(
        padding: EdgeInsets.only(left: entry.depth * 15.0),
        child: GestureDetector(
          onSecondaryTapDown: (details) =>
              showSpbFolderMenu(folder, details.globalPosition),
          onLongPressStart: (details) =>
              showSpbFolderMenu(folder, details.globalPosition),
          child: ListTile(
            dense: true,
            visualDensity: const VisualDensity(vertical: -3.25),
            minTileHeight: compactRows ? 16.2 : 30,
            contentPadding: const EdgeInsets.only(left: 6, right: 2),
            leading: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _updateShellState(() {
                navigationController.setFolderExpanded(folder, !expanded);
                if (!expanded) {
                  selectedCategoryPath = folder.path;
                  selectedCategoryId = folder.id;
                }
              }),
              child: SizedBox(
                width: 60,
                height: compactRows ? 18 : 30,
                child: OverflowBox(
                  minWidth: 60,
                  maxWidth: 60,
                  minHeight: 40,
                  maxHeight: 40,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      spbExpansionMark(expanded),
                      const SizedBox(width: 3.75),
                      spbSizedDataIcon(
                        folder.iconId ??
                            defaultIconForCategoryPath(folder.path),
                        40,
                        fallbackColor: categoryPictogramColor(folder.colorId),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            title: buildSpbCardDropTarget(
              categoryPath: folder.path,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => openSpbFolder(folder.path),
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: compactRows ? 0 : 3,
                  ),
                  decoration: selectedCategoryPath == folder.path
                      ? const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xffb9dcf5), Color(0xffedf7fe)],
                          ),
                        )
                      : null,
                  child: Text(
                    folder.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 18.8,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    final item = entry.card!;
    final template = templateFor(item.templateId);
    return Padding(
      padding: EdgeInsets.only(left: 25.5 + entry.depth * 15.0),
      child: GestureDetector(
        key: ValueKey('spbTreeCard-${item.id}'),
        onSecondaryTapDown: (details) =>
            showSpbCardMenu(item, details.globalPosition),
        onLongPressStart: (details) =>
            showSpbCardMenu(item, details.globalPosition),
        child: ListTile(
          selected: selectedItemId == item.id,
          selectedTileColor: const Color(0xffcfe9fb),
          dense: true,
          visualDensity: const VisualDensity(vertical: -3.25),
          minTileHeight: compactRows ? 20.25 : 30,
          contentPadding: const EdgeInsets.symmetric(horizontal: 5),
          leading: SizedBox(
            width: 40,
            height: compactRows ? 20.25 : 30,
            child: OverflowBox(
              minWidth: 40,
              maxWidth: 40,
              minHeight: 40,
              maxHeight: 40,
              child: spbSizedDataIcon(
                itemIconId(item, template),
                40,
                fallbackColor: itemPictogramColor(item, template),
              ),
            ),
          ),
          title: Text(
            item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 17),
          ),
          onTap: () => openCardPreviewDialog(item),
        ),
      ),
    );
  }

  Widget buildSpbTemplateTree({bool compactRows = false}) {
    final query = searchController.text.trim().toLowerCase();
    final visible = templates
        .where(
          (entry) => query.isEmpty || entry.name.toLowerCase().contains(query),
        )
        .toList()
      ..sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: visible.length,
      itemBuilder: (context, index) {
        final template = visible[index];
        return GestureDetector(
          key: ValueKey('spbTemplate-${template.id}'),
          onDoubleTap: () => openTemplatePreview(template),
          onSecondaryTapDown: (details) =>
              showSpbTemplateMenu(template, details.globalPosition),
          onLongPressStart: (details) =>
              showSpbTemplateMenu(template, details.globalPosition),
          child: ListTile(
            dense: true,
            minTileHeight: compactRows ? 36 : null,
            selected: selectedTemplateId == template.id,
            selectedTileColor: const Color(0xffdbeaf5),
            leading: spbSizedDataIcon(
              template.iconId,
              40,
              fallbackColor: templateDisplayPictogramColor(template),
            ),
            title: Text(
              template.name,
              style: const TextStyle(fontSize: 15),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () =>
                _updateShellState(() => selectedTemplateId = template.id),
          ),
        );
      },
    );
  }

  Future<void> showSpbTemplateMenu(
    CardTemplate template,
    Offset globalPosition,
  ) async {
    _updateShellState(() => selectedTemplateId = template.id);
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 1, 1),
        Offset.zero & overlay.size,
      ),
      items: const [
        PopupMenuItem(
          key: Key('createTemplateFromIconContextAction'),
          value: 'create',
          child: Text('Создать'),
        ),
        PopupMenuItem(
          key: Key('viewTemplateContextAction'),
          value: 'view',
          child: Text('Просмотр'),
        ),
        PopupMenuItem(
          key: Key('editTemplateContextAction'),
          value: 'edit',
          child: Text('Редактировать'),
        ),
        PopupMenuItem(
          key: Key('copyTemplateContextAction'),
          value: 'copy',
          child: Text('Копировать'),
        ),
        PopupMenuItem(
          key: Key('exportTemplateContextAction'),
          value: 'export',
          child: Text('Экспортировать'),
        ),
        PopupMenuItem(
          key: Key('importTemplateFromIconContextAction'),
          value: 'import',
          child: Text('Импортировать'),
        ),
        PopupMenuItem(
          key: Key('deleteTemplateContextAction'),
          value: 'delete',
          child: Text('Удалить'),
        ),
      ],
    );
    if (!mounted || selected == null) return;
    if (selected == 'create') {
      await openTemplateDialog();
    } else if (selected == 'view') {
      await openTemplatePreview(template);
    } else if (selected == 'edit') {
      await openTemplateDialog(template: template);
    } else if (selected == 'copy') {
      await cloneSpbTemplate(template);
    } else if (selected == 'export') {
      await exportSelectedSpbTemplate();
    } else if (selected == 'import') {
      await importSpbTemplate();
    } else if (selected == 'delete') {
      await deleteTemplateWithConfirmation(template);
    }
  }

  Future<void> cloneSpbTemplate(CardTemplate template) async {
    final existingNames = templates.map((entry) => entry.name).toSet();
    var suffix = 1;
    var cloneName = '${template.name} ($suffix)';
    while (existingNames.contains(cloneName)) {
      suffix++;
      cloneName = '${template.name} ($suffix)';
    }
    final clone = CardTemplate(
      id: makeId('tpl'),
      name: cloneName,
      iconId: template.iconId,
      colorId: template.colorId,
      spbColor: template.spbColor,
      categoryPath: template.categoryPath,
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
    final saved = await saveSpbTemplateDefinition(clone, isNew: true);
    if (saved) {
      showTemplateActionMessage('Создана копия шаблона «$cloneName».');
    }
  }

  Widget buildSpbTemplateWorkspace({bool showHeader = true}) {
    final query = searchController.text.trim().toLowerCase();
    final visible = templates
        .where(
          (template) =>
              query.isEmpty || template.name.toLowerCase().contains(query),
        )
        .toList()
      ..sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHeader)
          spbSectionHeader(
            'Шаблоны',
            trailing: spbResourceIcon('icon_templates.png', 23),
          ),
        Expanded(
          child: GestureDetector(
            key: const Key('spbTemplateWorkspace'),
            behavior: HitTestBehavior.translucent,
            onSecondaryTapDown: (details) =>
                showSpbTemplateImportMenu(details.globalPosition),
            onLongPressStart: (details) =>
                showSpbTemplateImportMenu(details.globalPosition),
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 89.04,
                mainAxisExtent: 83.475,
                crossAxisSpacing: 3.975,
                mainAxisSpacing: 6.36,
              ),
              itemCount: visible.length,
              itemBuilder: (context, index) {
                final template = visible[index];
                return KeyedSubtree(
                  key: ValueKey('spbCentralTemplate-${template.id}'),
                  child: buildSpbGridEntry(
                    label: template.name,
                    icon: spbSizedDataIcon(
                      template.iconId,
                      50.25,
                      fallbackColor: templateDisplayPictogramColor(template),
                    ),
                    onTap: () => _updateShellState(
                        () => selectedTemplateId = template.id),
                    onDoubleTap: () => openTemplatePreview(template),
                    onContextMenu: (position) =>
                        showSpbTemplateMenu(template, position),
                    selected: selectedTemplateId == template.id,
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Future<void> showSpbTemplateImportMenu(Offset globalPosition) async {
    if (spbObjectMenuPointerActive) return;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 1, 1),
        Offset.zero & overlay.size,
      ),
      items: const [
        PopupMenuItem(
          key: Key('createTemplateContextAction'),
          value: 'create',
          child: Text('Создать'),
        ),
        PopupMenuItem(
          key: Key('importTemplateContextAction'),
          value: 'import',
          child: Text('Импортировать'),
        ),
      ],
    );
    if (!mounted) return;
    if (selected == 'create') {
      await openTemplateDialog();
    } else if (selected == 'import') {
      await importSpbTemplate();
    }
  }

  Future<bool> deleteTemplateWithConfirmation(CardTemplate template) async {
    if (!ensureSpbWalletWritable()) return false;
    final linkedCards =
        items.where((item) => item.templateId == template.id).length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xffececec),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        title: const Text('Удалить шаблон'),
        content: Text(
          linkedCards == 0
              ? 'Шаблон "${template.name}" будет перемещён во внутреннюю корзину.'
              : 'Шаблон "${template.name}" и связанные с ним карточки '
                  '($linkedCards) будут перемещены во внутреннюю корзину.',
        ),
        actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
        actions: [
          SizedBox(
            width: 124,
            child: passwordKey(
              key: const Key('cancelDeleteTemplateButton'),
              label: 'Отмена',
              height: 40,
              fontSize: 18,
              onPressed: () => Navigator.pop(dialogContext, false),
            ),
          ),
          SizedBox(
            width: 124,
            child: passwordKey(
              key: const Key('confirmDeleteTemplateButton'),
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
    if (confirmed != true || !mounted) return false;
    final wallet = spbWallet;
    if (wallet == null) {
      showTemplateActionMessage(
        'Откройте или создайте .swl базу перед удалением шаблонов.',
      );
      return false;
    }
    SessionUndoEntry? undoEntry;
    try {
      undoEntry = await captureSessionUndo(
        'Удаление шаблона: ${template.name}',
        template.iconId,
      );
      sessionTrashTemplateIds.add(template.id);
      sessionTrash.add(
        SessionTrashEntry(
          kind: SessionTrashKind.template,
          id: template.id,
          title: template.name,
          iconId: template.iconId,
        ),
      );
      _updateShellState(() {
        templates = templates
            .where((entry) => entry.id != template.id)
            .toList(growable: false);
        templatesById.remove(template.id);
        final removedCardIds = items
            .where((item) => item.templateId == template.id)
            .map((item) => item.id)
            .toSet();
        items = items
            .where((item) => item.templateId != template.id)
            .toList(growable: false);
        itemsById.removeWhere((id, _) => removedCardIds.contains(id));
        if (selectedTemplateId == template.id) {
          selectedTemplateId = templates.isEmpty ? null : templates.first.id;
        }
        if (selectedItemId != null && !itemsById.containsKey(selectedItemId)) {
          selectedItemId = null;
        }
        message = null;
      });
      commitSessionUndo(undoEntry);
      return true;
    } catch (error) {
      discardSessionUndo(undoEntry);
      sessionTrashTemplateIds.remove(template.id);
      sessionTrash.removeWhere(
        (entry) =>
            entry.kind == SessionTrashKind.template && entry.id == template.id,
      );
      showTemplateActionMessage('Не удалось удалить шаблон: $error');
      return false;
    }
  }

  CategoryTreeNode categoryNodeAt(CategoryTreeNode root, String path) {
    return navigationController.nodeAt(root, path);
  }
}
