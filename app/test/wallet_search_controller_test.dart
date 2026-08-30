import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_aps/features/search/wallet_search_controller.dart';

void main() {
  WalletSearchDocument card(
    String id,
    String title, {
    List<String> values = const [],
  }) {
    return WalletSearchDocument(
      id: id,
      sortValue: title,
      searchableText: [title, ...values].join(' '),
      exactValues: [title, ...values],
    );
  }

  test('matches layout swaps, transliteration and similar spelling', () {
    expect(WalletSearchController.matches('Привет мир', 'ghbdtn'), isTrue);
    expect(WalletSearchController.matches('Привет мир', 'privet'), isTrue);
    expect(WalletSearchController.matches('Привет мир', 'превет'), isTrue);
    expect(WalletSearchController.matches('Привет мир', 'account'), isFalse);
  });

  test('returns sorted shared folder and card identifiers', () async {
    final controller = WalletSearchController();
    controller.replaceIndex(
      revision: 7,
      folders: const [
        WalletSearchDocument(
          id: 'Работа / Серверы',
          sortValue: 'Работа / Серверы',
          searchableText: 'Работа / Серверы',
          exactValues: ['Работа / Серверы', 'Серверы'],
        ),
      ],
      cards: [
        card('second', 'Zulu account', values: ['server']),
        card('first', 'Alpha account', values: ['server']),
      ],
    );

    final result = await controller.search('server');
    expect(result.revision, 7);
    expect(result.folderPaths, ['Работа / Серверы']);
    expect(result.cardIds, ['first', 'second']);
    expect(result.count, 3);
    expect(identical(result, await controller.search('server')), isTrue);
  });

  test('exact search only accepts a complete indexed value', () async {
    final controller = WalletSearchController();
    controller.replaceIndex(
      revision: 1,
      folders: const [],
      cards: [
        card('card', 'Alpha account', values: ['secret value'])
      ],
    );

    expect((await controller.search('Alpha', exact: true)).cardIds, isEmpty);
    expect(
      (await controller.search('Alpha account', exact: true)).cardIds,
      ['card'],
    );
  });

  test('large indexes are searched in a worker isolate', () async {
    final controller = WalletSearchController(isolateThreshold: 2);
    controller.replaceIndex(
      revision: 2,
      folders: const [],
      cards: [
        card('one', 'First record'),
        card('two', 'Worker isolate target'),
      ],
    );

    final result = await controller.search('isolate target');
    expect(result.cardIds, ['two']);
  });

  test('query cache stays bounded while the user keeps typing', () async {
    final controller = WalletSearchController(maxCachedQueries: 3);
    controller.replaceIndex(
      revision: 3,
      folders: const [],
      cards: [card('card', 'Alpha account')],
    );

    for (final query in ['a', 'al', 'alp', 'alph', 'alpha']) {
      await controller.search(query);
    }

    expect(controller.cachedQueryCount, 3);
  });
}
