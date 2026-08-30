class VaultTreeNode<T> {
  VaultTreeNode(
    this.name, {
    this.path = '',
    this.iconId,
    this.colorId,
    this.id,
  });

  final String name;
  final String path;
  final String? iconId;
  final String? colorId;
  final String? id;
  final Map<String, VaultTreeNode<T>> children = {};
  final List<T> cards = [];

  bool get isEmpty => children.isEmpty && cards.isEmpty;
}

class VaultVisibleTreeEntry<T> {
  const VaultVisibleTreeEntry.root()
      : depth = 0,
        folder = null,
        card = null;

  const VaultVisibleTreeEntry.folder(this.folder, this.depth) : card = null;

  const VaultVisibleTreeEntry.card(this.card, this.depth) : folder = null;

  final int depth;
  final VaultTreeNode<T>? folder;
  final T? card;

  bool get isRoot => folder == null && card == null;
}

/// Owns navigation state and the platform-independent category tree model.
class VaultNavigationController<T> {
  String selectedCategoryPath = '';
  String? selectedCategoryId;
  bool mobileTemplatesOpen = false;
  int mobilePane = 0;
  bool rootTreeExpanded = true;
  final Set<String> expandedCategoryPaths = {};
  final Set<String> expandedCategoryIds = {};

  List<String> categoryParts(String value) {
    return value
        .split(RegExp(r'\s*/\s*'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty && part != 'Без категории')
        .toList(growable: false);
  }

  String parentPath(String path) {
    final parts = categoryParts(path).toList();
    if (parts.isNotEmpty) parts.removeLast();
    return parts.join(' / ');
  }

  void selectCategory(String path, Map<String, String> categoryIdsByPath) {
    selectedCategoryPath = path;
    selectedCategoryId = categoryIdsByPath[path];
  }

  void reconcileCategorySelection({
    required Map<String, String> categoryPathsById,
    required Map<String, String> categoryIdsByPath,
  }) {
    if (selectedCategoryId != null) {
      selectedCategoryPath = categoryPathsById[selectedCategoryId] ?? '';
      if (selectedCategoryPath.isEmpty) selectedCategoryId = null;
    } else if (selectedCategoryPath.isNotEmpty) {
      selectedCategoryId = categoryIdsByPath[selectedCategoryPath];
    }
    expandedCategoryPaths.addAll(
      expandedCategoryIds
          .map((id) => categoryPathsById[id])
          .whereType<String>(),
    );
  }

  bool isFolderExpanded(VaultTreeNode<T> folder) {
    final id = folder.id;
    return (id != null && expandedCategoryIds.contains(id)) ||
        expandedCategoryPaths.contains(folder.path);
  }

  void setFolderExpanded(VaultTreeNode<T> folder, bool expanded) {
    final id = folder.id;
    if (expanded) {
      expandedCategoryPaths.add(folder.path);
      if (id != null) expandedCategoryIds.add(id);
    } else {
      expandedCategoryPaths.remove(folder.path);
      if (id != null) expandedCategoryIds.remove(id);
    }
  }

  void expandCategoryPaths(
    Iterable<String> paths,
    Map<String, String> categoryIdsByPath,
  ) {
    for (final path in paths) {
      expandedCategoryPaths.add(path);
      final id = categoryIdsByPath[path];
      if (id != null) expandedCategoryIds.add(id);
    }
  }

  void showCardsMode() {
    mobileTemplatesOpen = false;
    mobilePane = 0;
  }

  void showTemplatesMode() {
    mobileTemplatesOpen = true;
    mobilePane = 0;
  }

  List<String> existingCategoryPaths({
    required Iterable<String> categoryPaths,
    required Iterable<String> iconPaths,
    required Iterable<String> colorPaths,
    required Iterable<T> items,
    required String Function(T item) categoryPathOf,
  }) {
    final categories = {
      ...categoryPaths,
      ...iconPaths,
      ...colorPaths,
      for (final item in items)
        if (categoryPathOf(item).trim().isNotEmpty) categoryPathOf(item).trim(),
    }.toList();
    categories.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return categories;
  }

  VaultTreeNode<T> buildTree({
    required Iterable<T> source,
    required String Function(T item) categoryPathOf,
    required Iterable<String> categoryPaths,
    required Map<String, String> iconIdsByPath,
    required Map<String, String> colorIdsByPath,
    required Map<String, String> categoryIdsByPath,
    bool includeAllCategories = true,
    Iterable<String> additionalPaths = const [],
    String rootName = 'Мой кошелёк',
  }) {
    final root = VaultTreeNode<T>(rootName);
    final paths = <String>{...additionalPaths};
    if (includeAllCategories) {
      paths.addAll(categoryPaths);
      paths.addAll(iconIdsByPath.keys);
      paths.addAll(colorIdsByPath.keys);
    }
    for (final path in paths) {
      ensureTreeNode(
        root,
        path,
        iconIdsByPath: iconIdsByPath,
        colorIdsByPath: colorIdsByPath,
        categoryIdsByPath: categoryIdsByPath,
      );
    }
    for (final item in source) {
      final node = ensureTreeNode(
        root,
        categoryPathOf(item),
        iconIdsByPath: iconIdsByPath,
        colorIdsByPath: colorIdsByPath,
        categoryIdsByPath: categoryIdsByPath,
      );
      node.cards.add(item);
    }
    return root;
  }

  VaultTreeNode<T> ensureTreeNode(
    VaultTreeNode<T> root,
    String path, {
    required Map<String, String> iconIdsByPath,
    required Map<String, String> colorIdsByPath,
    required Map<String, String> categoryIdsByPath,
  }) {
    var node = root;
    final pathParts = <String>[];
    for (final part in categoryParts(path)) {
      pathParts.add(part);
      final currentPath = pathParts.join(' / ');
      node = node.children.putIfAbsent(
        part,
        () => VaultTreeNode<T>(
          part,
          path: currentPath,
          iconId: iconIdsByPath[currentPath],
          colorId: colorIdsByPath[currentPath],
          id: categoryIdsByPath[currentPath],
        ),
      );
    }
    return node;
  }

  VaultTreeNode<T> nodeAt(VaultTreeNode<T> root, String path) {
    var current = root;
    for (final part in categoryParts(path)) {
      final next = current.children[part];
      if (next == null) return root;
      current = next;
    }
    return current;
  }

  List<VaultVisibleTreeEntry<T>> visibleEntries(
    VaultTreeNode<T> root, {
    required bool showWalletRoot,
    required String Function(T item) sortValueOf,
  }) {
    final result = <VaultVisibleTreeEntry<T>>[];

    void appendChildren(VaultTreeNode<T> node, int depth) {
      final folders = node.children.values.toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      for (final folder in folders) {
        result.add(VaultVisibleTreeEntry<T>.folder(folder, depth));
        if (isFolderExpanded(folder)) {
          appendChildren(folder, depth + 1);
        }
      }
      final cards = [...node.cards]..sort(
          (a, b) => sortValueOf(a)
              .toLowerCase()
              .compareTo(sortValueOf(b).toLowerCase()),
        );
      for (final card in cards) {
        result.add(VaultVisibleTreeEntry<T>.card(card, depth));
      }
    }

    if (showWalletRoot) {
      result.add(VaultVisibleTreeEntry<T>.root());
      if (rootTreeExpanded) appendChildren(root, 0);
    } else {
      appendChildren(root, 0);
    }
    return result;
  }
}
