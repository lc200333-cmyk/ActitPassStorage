import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_aps/features/navigation/vault_navigation_controller.dart';

class _Card {
  const _Card(this.id, this.title, this.category);

  final String id;
  final String title;
  final String category;
}

void main() {
  test('builds an ID-backed category tree with metadata', () {
    final controller = VaultNavigationController<_Card>();
    final root = controller.buildTree(
      source: const [
        _Card('one', 'Zulu', 'Работа / Серверы'),
        _Card('two', 'Alpha', 'Работа / Серверы'),
      ],
      categoryPathOf: (card) => card.category,
      categoryPaths: const ['Личное'],
      iconIdsByPath: const {'Работа': 'briefcase'},
      colorIdsByPath: const {'Работа': 'blue'},
      categoryIdsByPath: const {
        'Работа': 'folder-work',
        'Работа / Серверы': 'folder-servers',
      },
    );

    final work = root.children['Работа']!;
    expect(work.id, 'folder-work');
    expect(work.iconId, 'briefcase');
    expect(work.colorId, 'blue');
    expect(work.children['Серверы']!.id, 'folder-servers');
    expect(root.children, contains('Личное'));
    expect(
      controller.nodeAt(root, 'Работа / Серверы').cards.map((card) => card.id),
      ['one', 'two'],
    );
  });

  test('visible list contains only expanded branches and sorted cards', () {
    final controller = VaultNavigationController<_Card>();
    final root = controller.buildTree(
      source: const [
        _Card('z', 'Zulu', 'Работа'),
        _Card('a', 'Alpha', 'Работа'),
        _Card('nested', 'Nested', 'Работа / Серверы'),
      ],
      categoryPathOf: (card) => card.category,
      categoryPaths: const [],
      iconIdsByPath: const {},
      colorIdsByPath: const {},
      categoryIdsByPath: const {},
    );

    var entries = controller.visibleEntries(
      root,
      showWalletRoot: true,
      sortValueOf: (card) => card.title,
    );
    expect(entries, hasLength(2));
    expect(entries.first.isRoot, isTrue);

    controller.expandedCategoryPaths.add('Работа');
    entries = controller.visibleEntries(
      root,
      showWalletRoot: true,
      sortValueOf: (card) => card.title,
    );
    expect(entries.map((entry) => entry.card?.id).whereType<String>(), [
      'a',
      'z',
    ]);
    expect(entries.any((entry) => entry.card?.id == 'nested'), isFalse);

    controller.expandedCategoryPaths.add('Работа / Серверы');
    entries = controller.visibleEntries(
      root,
      showWalletRoot: true,
      sortValueOf: (card) => card.title,
    );
    expect(entries.any((entry) => entry.card?.id == 'nested'), isTrue);
  });

  test('keeps folder selection stable when its path changes', () {
    final controller = VaultNavigationController<_Card>()
      ..selectedCategoryPath = 'Старое имя'
      ..selectedCategoryId = 'folder-id';

    controller.reconcileCategorySelection(
      categoryPathsById: const {'folder-id': 'Новое имя'},
      categoryIdsByPath: const {'Новое имя': 'folder-id'},
    );
    expect(controller.selectedCategoryPath, 'Новое имя');
    expect(controller.selectedCategoryId, 'folder-id');
    expect(controller.parentPath('Работа / Серверы'), 'Работа');

    final oldFolder = VaultTreeNode<_Card>(
      'Старое имя',
      path: 'Старое имя',
      id: 'folder-id',
    );
    controller.setFolderExpanded(oldFolder, true);
    controller.reconcileCategorySelection(
      categoryPathsById: const {'folder-id': 'Новое имя'},
      categoryIdsByPath: const {'Новое имя': 'folder-id'},
    );
    final renamedFolder = VaultTreeNode<_Card>(
      'Новое имя',
      path: 'Новое имя',
      id: 'folder-id',
    );
    expect(controller.isFolderExpanded(renamedFolder), isTrue);

    controller.showTemplatesMode();
    expect(controller.mobileTemplatesOpen, isTrue);
    expect(controller.mobilePane, 0);
    controller.showCardsMode();
    expect(controller.mobileTemplatesOpen, isFalse);
  });
}
