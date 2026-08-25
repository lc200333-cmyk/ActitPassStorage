import 'dart:io';

import 'package:actit_pass_storage/performance/benchmark_fixture_factory.dart';
import 'package:actit_pass_storage/spb_wallet/spb_wallet_database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('benchmark fixture is deterministic in shape and can be reopened',
      () async {
    final directory = Directory.systemTemp.createTempSync('wallet_aps_perf_');
    final path = '${directory.path}${Platform.pathSeparator}fixture.swl';
    try {
      const factory = BenchmarkFixtureFactory();
      final result = factory.create(
        path: path,
        cardCount: 40,
        templateCount: 4,
        folderCount: 6,
      );
      final database = SpbWalletDatabase.open(path, result.password);
      final catalog = database.loadCatalog();
      expect(catalog.detailsIncluded, isFalse);
      expect(catalog.cards, hasLength(40));
      expect(catalog.cards.every((card) => card.fieldValues.isEmpty), isTrue);
      expect(catalog.cards.every((card) => card.attachments.isEmpty), isTrue);
      final firstCard = catalog.cards.singleWhere(
        (card) => card.title == 'Карточка 0000',
      );
      final details = database.loadCardDetails(firstCard.id);
      expect(details.fieldValues, hasLength(5));
      expect(details.description, contains('Заметка производительности'));
      expect(details.attachments, hasLength(1));
      final plans = database.explainPerformanceQueries();
      expect(plans, hasLength(4));
      expect(
        plans.values.expand((entries) => entries).join(' '),
        isNot(contains('SCAN spbwlt_CardFieldValue')),
      );
      final snapshot = database.loadSnapshot();
      expect(snapshot.detailsIncluded, isTrue);
      expect(snapshot.cards, hasLength(40));
      expect(snapshot.templates, hasLength(4));
      expect(snapshot.categories, isNotEmpty);
      expect(snapshot.cards.first.fieldValues, hasLength(5));
      expect(
        snapshot.cards.where((card) => card.attachments.isNotEmpty),
        hasLength(1),
      );
      database.close();
    } finally {
      for (var attempt = 0; attempt < 5 && directory.existsSync(); attempt++) {
        try {
          directory.deleteSync(recursive: true);
        } on FileSystemException {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
    }
  });
}
