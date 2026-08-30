part of '../../main.dart';

extension _VaultWorkspaceActionsPanel on _VaultShellState {
  List<SecretItem> frequentItems() {
    final byId = {for (final item in items) item.id: item};
    final result = <SecretItem>[
      for (final id in recentlyOpenedItemIds)
        if (byId[id] != null) byId[id]!,
    ];
    final recentIds = result.map((item) => item.id).toSet();
    final previous = items
        .where((item) => item.hitCount > 0 && !recentIds.contains(item.id))
        .toList()
      ..sort((a, b) {
        final byHits = b.hitCount.compareTo(a.hitCount);
        return byHits == 0 ? a.title.compareTo(b.title) : byHits;
      });
    result.addAll(previous);
    return result;
  }

  CardTemplate? selectedSpbTemplate() {
    if (templates.isEmpty) return null;
    for (final template in templates) {
      if (template.id == selectedTemplateId) return template;
    }
    return templates.first;
  }

  List<(Widget, String, VoidCallback)> spbTasksForCurrentMode() {
    if (mobileTemplatesOpen) {
      return [
        (
          spbResourceIcon('icon_add.png', 40),
          'Создать новый шаблон',
          () => openTemplateDialog(),
        ),
        (
          spbResourceIcon('icon_edit_fun_icon.png', 40),
          'Редактировать',
          editSelectedSpbTemplate,
        ),
        (spbResourceIcon('icon_import.png', 40), 'Импорт', importSpbTemplate),
        (
          spbResourceIcon('icon_share.png', 40),
          'Экспорт',
          exportSelectedSpbTemplate,
        ),
        (
          const Icon(Icons.delete_outline, size: 36, color: Color(0xff33434f)),
          'Удалить',
          deleteSelectedSpbTemplate,
        ),
        (
          spbResourceIcon('icon_save_enable.png', 40),
          spbWritePending ? 'Повторить сохранение' : 'Сохранить базу',
          saveVaultThroughExplorer,
        ),
        (
          const Icon(Icons.logout, size: 36, color: Color(0xff33434f)),
          'Выйти',
          exitToPasswordPrompt,
        ),
      ];
    }
    return [
      if (walletLoadReport.hasIssues)
        (
          const Icon(
            Icons.warning_amber_rounded,
            size: 36,
            color: Color(0xffa65b00),
          ),
          walletLoadReport.issues.length == cardLoadFailures.length
              ? 'Не удалось отобразить ${cardLoadFailures.length} карточек'
              : 'Ошибок загрузки: ${walletLoadReport.issues.length}',
          showCardLoadFailureReport,
        ),
      (
        Image.asset(
          'assets/branding/wallet_android.png',
          key: const Key('spbCreateWalletAppIcon'),
          width: 40,
          height: 40,
          cacheWidth: 128,
          fit: BoxFit.contain,
        ),
        'Создать кошелёк',
        createNewVaultFromLogin,
      ),
      (
        spbResourceIcon('icon_import.png', 40),
        'Открыть кошелёк',
        pickSpbWalletFile,
      ),
      (
        const Icon(Icons.password_outlined, size: 36, color: Color(0xff33434f)),
        'Изменить пароль',
        openChangePasswordDialog,
      ),
      (
        spbResourceIcon('icon_add_card.png', 40),
        'Создать новую карточку',
        () => openItemDialog(initialCategory: selectedCategoryPath),
      ),
      (
        spbResourceIcon('icon_add_folder.png', 40),
        'Создать новую папку',
        () => openCategoryEditorDialog(
              folder: null,
              parentPath: selectedCategoryPath,
            ),
      ),
      (
        spbResourceIcon('icon_backup.png', 40),
        'Сделать архивную копию',
        createDatedArchiveCopy,
      ),
      (
        const Icon(
          Icons.health_and_safety_outlined,
          size: 36,
          color: Color(0xff33434f),
        ),
        'Проверить и восстановить базу',
        repairCurrentWalletCompatibility,
      ),
      (
        spbResourceIcon('icon_save_enable.png', 40),
        spbWritePending ? 'Повторить сохранение' : 'Сохранить базу',
        saveVaultThroughExplorer,
      ),
      (
        const Icon(Icons.logout, size: 36, color: Color(0xff33434f)),
        'Выйти',
        exitToPasswordPrompt,
      ),
    ];
  }

  Future<void> showCardLoadFailureReport() async {
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Ошибок загрузки: ${walletLoadReport.issues.length}'),
        content: SizedBox(
          width: min(MediaQuery.sizeOf(context).width - 48, 620),
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: walletLoadReport.issues.length,
            separatorBuilder: (_, __) => const Divider(),
            itemBuilder: (context, index) {
              final failure = walletLoadReport.issues[index];
              return ListTile(
                dense: true,
                leading: const Icon(Icons.error_outline),
                title: Text(
                  '${walletLoadIssueLabel(failure.kind)} ${failure.entityId}',
                ),
                subtitle: Text(
                  failure.reason,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'backup'),
            child: const Text('Сохранить исходную базу'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'export'),
            child: const Text('Экспортировать исправные'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'repair'),
            child: const Text('Проверить и восстановить'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (action == 'export') {
      await exportSpbItems(items, suggestedName: 'readable-cards');
    } else if (action == 'backup') {
      await createDatedArchiveCopy();
    } else if (action == 'repair') {
      await repairCurrentWalletCompatibility();
    }
  }

  String walletLoadIssueLabel(WalletLoadIssueKind kind) => switch (kind) {
        WalletLoadIssueKind.card => 'Карточка',
        WalletLoadIssueKind.field => 'Поле',
        WalletLoadIssueKind.attachment => 'Вложение',
        WalletLoadIssueKind.category => 'Категория',
        WalletLoadIssueKind.template => 'Шаблон',
        WalletLoadIssueKind.icon => 'Иконка',
      };

  Widget buildSpbActionsPanel({bool desktop = false}) {
    final frequent = frequentItems();
    final query = spbSubmittedSearchQuery;
    final matchingFolders = spbMatchingFolderPaths(query);
    final matchingCards = spbMatchingCards(query);
    final foundCount = matchingFolders.length + matchingCards.length;
    final maximizeFound = spbFrequentExpanded == false && spbFoundExpanded;
    if (desktop) {
      return wrapSpbTemplateRightContextMenu(
        Material(
          color: Colors.white,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              buildSpbActionGroup(
                'Задачи',
                spbTasksForCurrentMode(),
                shellStyle: true,
                sectionExpanded: spbTasksExpanded,
                onExpand: () =>
                    _updateShellState(() => spbTasksExpanded = true),
                onCollapse: () =>
                    _updateShellState(() => spbTasksExpanded = false),
              ),
              buildSpbCollapsibleHeader(
                'Найдено',
                expanded: spbFoundExpanded,
                onExpand: () =>
                    _updateShellState(() => spbFoundExpanded = true),
                onCollapse: () =>
                    _updateShellState(() => spbFoundExpanded = false),
                shellStyle: true,
                trailing: Text(
                  '$foundCount',
                  key: const Key('spbFoundCount'),
                  style: const TextStyle(fontSize: 17),
                ),
              ),
              if (maximizeFound)
                Expanded(
                  child: query.isEmpty
                      ? const SizedBox.expand()
                      : buildSpbSearchResults(
                          matchingFolders,
                          matchingCards,
                          controller: spbFoundScrollController,
                        ),
                )
              else if (spbFoundExpanded && query.isNotEmpty)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 240),
                  child: buildSpbSearchResults(
                    matchingFolders,
                    matchingCards,
                    controller: spbFoundScrollController,
                  ),
                ),
              if (spbFrequentExpanded)
                Expanded(
                  child: buildSpbActionGroup(
                    'Часто используемые',
                    [
                      for (final item in frequent.take(10))
                        (
                          spbSizedDataIcon(
                            itemIconId(item, templateFor(item.templateId)),
                            40,
                            fallbackColor: itemPictogramColor(
                              item,
                              templateFor(item.templateId),
                            ),
                          ),
                          item.title,
                          () => openFrequentCard(item),
                        ),
                    ],
                    expand: true,
                    shellStyle: true,
                    sectionExpanded: true,
                    onExpand: () =>
                        _updateShellState(() => spbFrequentExpanded = true),
                    onCollapse: () =>
                        _updateShellState(() => spbFrequentExpanded = false),
                    scrollController: spbFrequentScrollController,
                  ),
                )
              else
                buildSpbActionGroup(
                  'Часто используемые',
                  const [],
                  shellStyle: true,
                  sectionExpanded: false,
                  onExpand: () =>
                      _updateShellState(() => spbFrequentExpanded = true),
                  onCollapse: () =>
                      _updateShellState(() => spbFrequentExpanded = false),
                ),
            ],
          ),
        ),
      );
    }
    return wrapSpbTemplateRightContextMenu(
      Scrollbar(
        key: const Key('spbMobileActionsScrollbar'),
        controller: spbMobileActionsScrollController,
        thumbVisibility: true,
        trackVisibility: true,
        child: SingleChildScrollView(
          controller: spbMobileActionsScrollController,
          child: Container(
            color: _VaultShellState._spbRightPanel,
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                buildSpbActionGroup(
                  'Задачи',
                  spbTasksForCurrentMode(),
                  sectionExpanded: spbTasksExpanded,
                  onExpand: () =>
                      _updateShellState(() => spbTasksExpanded = true),
                  onCollapse: () =>
                      _updateShellState(() => spbTasksExpanded = false),
                ),
                buildSpbCollapsibleHeader(
                  'Найдено',
                  expanded: spbFoundExpanded,
                  onExpand: () =>
                      _updateShellState(() => spbFoundExpanded = true),
                  onCollapse: () =>
                      _updateShellState(() => spbFoundExpanded = false),
                  trailing: Text(
                    '$foundCount',
                    key: const Key('spbFoundCount'),
                    style: const TextStyle(fontSize: 17),
                  ),
                ),
                if (spbFoundExpanded && query.isNotEmpty)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 180),
                    child: buildSpbSearchResults(
                      matchingFolders,
                      matchingCards,
                      controller: spbFoundScrollController,
                    ),
                  ),
                if (spbFrequentExpanded)
                  buildSpbActionGroup(
                    'Часто используемые',
                    [
                      for (final item in frequent.take(10))
                        (
                          spbSizedDataIcon(
                            itemIconId(item, templateFor(item.templateId)),
                            40,
                            fallbackColor: itemPictogramColor(
                              item,
                              templateFor(item.templateId),
                            ),
                          ),
                          item.title,
                          () => openFrequentCard(item),
                        ),
                    ],
                    sectionExpanded: true,
                    onExpand: () =>
                        _updateShellState(() => spbFrequentExpanded = true),
                    onCollapse: () =>
                        _updateShellState(() => spbFrequentExpanded = false),
                  )
                else
                  buildSpbActionGroup(
                    'Часто используемые',
                    const [],
                    sectionExpanded: false,
                    onExpand: () =>
                        _updateShellState(() => spbFrequentExpanded = true),
                    onCollapse: () =>
                        _updateShellState(() => spbFrequentExpanded = false),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget wrapSpbTemplateRightContextMenu(Widget child) {
    if (!mobileTemplatesOpen) return child;
    return GestureDetector(
      key: const Key('spbTemplateRightWorkspace'),
      behavior: HitTestBehavior.translucent,
      onSecondaryTapDown: (details) =>
          showSpbTemplateRightMenu(details.globalPosition),
      onLongPressStart: (details) =>
          showSpbTemplateRightMenu(details.globalPosition),
      child: child,
    );
  }

  Future<void> showSpbTemplateRightMenu(Offset globalPosition) async {
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
          key: Key('createTemplateRightContextAction'),
          value: 'create',
          child: Text('Создать'),
        ),
        PopupMenuItem(
          key: Key('importTemplateRightContextAction'),
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

  Widget buildSpbSearchResults(
    List<String> matchingFolders,
    List<SecretItem> matchingCards, {
    ScrollController? controller,
  }) {
    if (matchingFolders.isEmpty && matchingCards.isEmpty) {
      return const SizedBox(
        height: 48,
        child: Center(
          child: Text(
            'Совпадений нет',
            key: Key('spbNoSearchResults'),
            style: TextStyle(fontSize: 15),
          ),
        ),
      );
    }
    final results = ListView(
      key: const Key('spbSearchResults'),
      controller: controller,
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      children: [
        for (final path in matchingFolders)
          buildSpbSearchResultRow(
            icon: spbSizedDataIcon(
              categoryIconsByPath[path] ?? defaultIconForCategoryPath(path),
              36,
              fallbackColor: categoryPictogramColor(categoryColorsByPath[path]),
            ),
            title: categoryParts(path).last,
            subtitle: 'Папка',
            onTap: () => openSpbFolder(path),
          ),
        for (final item in matchingCards)
          buildSpbSearchResultRow(
            icon: spbSizedDataIcon(
              itemIconId(item, templateFor(item.templateId)),
              36,
              fallbackColor: itemPictogramColor(
                item,
                templateFor(item.templateId),
              ),
            ),
            title: item.title,
            subtitle: item.category.trim().isEmpty
                ? 'Карточка'
                : 'Карточка • ${item.category}',
            onTap: () => openCardPreviewDialog(item, preserveSearch: true),
          ),
      ],
    );
    if (controller == null) return results;
    return Scrollbar(
      controller: controller,
      thumbVisibility: true,
      child: results,
    );
  }

  Widget buildSpbSearchResultRow({
    required Widget icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 4.5, 6, 3.75),
        child: Row(
          children: [
            SizedBox(
              width: 36,
              height: 27,
              child: OverflowBox(
                minWidth: 36,
                maxWidth: 36,
                minHeight: 36,
                maxHeight: 36,
                child: Center(
                  child: Transform.scale(scale: 0.9, child: icon),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xff5f5f5f),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildSpbCollapsibleHeader(
    String title, {
    required bool expanded,
    required VoidCallback onExpand,
    required VoidCallback onCollapse,
    bool shellStyle = false,
    Widget? trailing,
  }) {
    return Container(
      height: 34,
      padding: const EdgeInsets.only(left: 4, right: 10),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xffa9c9e3), Color(0xffe9f1f8)],
        ),
        border: shellStyle
            ? const Border(
                bottom: BorderSide(color: _VaultShellState._spbBorder),
              )
            : null,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            height: 32,
            child: Tooltip(
              message: expanded ? 'Свернуть' : 'Развернуть',
              child: InkWell(
                key: ValueKey(
                  expanded ? 'spbCollapse$title' : 'spbExpand$title',
                ),
                onTap: expanded ? onCollapse : onExpand,
                child: Center(
                  child: Icon(
                    expanded ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                    size: 29,
                    color: const Color(0xff168bd2),
                    shadows: const [
                      Shadow(
                        color: Color(0xb3ffffff),
                        offset: Offset(0, -1),
                        blurRadius: 0.5,
                      ),
                      Shadow(
                        color: Color(0xff075582),
                        offset: Offset(0, 1.5),
                        blurRadius: 1,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 17),
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget buildSpbActionGroup(
    String title,
    List<(Widget, String, VoidCallback)> actions, {
    bool expand = false,
    bool shellStyle = false,
    bool? sectionExpanded,
    VoidCallback? onExpand,
    VoidCallback? onCollapse,
    ScrollController? scrollController,
  }) {
    final header = sectionExpanded == null
        ? Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xffa9c9e3), Color(0xffe9f1f8)],
              ),
              border: shellStyle
                  ? const Border(
                      bottom: BorderSide(color: _VaultShellState._spbBorder),
                    )
                  : null,
            ),
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 17),
            ),
          )
        : buildSpbCollapsibleHeader(
            title,
            expanded: sectionExpanded,
            onExpand: onExpand!,
            onCollapse: onCollapse!,
            shellStyle: shellStyle,
          );
    if (sectionExpanded == false) return header;
    final actionTiles = [
      for (final action in actions)
        InkWell(
          onTap: action.$3,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 5.25, 6, 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 40,
                  height: 30,
                  child: OverflowBox(
                    minWidth: 40,
                    maxWidth: 40,
                    minHeight: 40,
                    maxHeight: 40,
                    child: Center(
                      child: Transform.scale(scale: 0.9, child: action.$1),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    action.$2,
                    style: const TextStyle(fontSize: 16, height: 1.12),
                  ),
                ),
              ],
            ),
          ),
        ),
    ];
    if (expand) {
      final scrollable = SingleChildScrollView(
        key: const Key('frequentCardsScroll'),
        controller: scrollController,
        child: Container(
          color: Colors.white,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: actionTiles,
          ),
        ),
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          Expanded(
            child: scrollController == null
                ? scrollable
                : Scrollbar(
                    controller: scrollController,
                    thumbVisibility: true,
                    child: scrollable,
                  ),
          ),
        ],
      );
    }
    final content = Container(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [header, ...actionTiles],
      ),
    );
    return IntrinsicHeight(child: content);
  }
}
