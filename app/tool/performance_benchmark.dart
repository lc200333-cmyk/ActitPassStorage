import 'dart:convert';
import 'dart:io';

import 'package:actit_pass_storage/performance/benchmark_fixture_factory.dart';
import 'package:actit_pass_storage/spb_wallet/spb_wallet_database.dart';

Future<void> main(List<String> arguments) async {
  final outputDirectory = Directory('build/performance')
    ..createSync(recursive: true);
  final databaseFile = File('${outputDirectory.path}/wallet-aps-1000.swl');
  final fixtureWatch = Stopwatch()..start();
  const factory = BenchmarkFixtureFactory();
  final fixture = factory.create(path: databaseFile.path);
  fixtureWatch.stop();

  final openWatch = Stopwatch()..start();
  final database = SpbWalletDatabase.open(fixture.path, fixture.password);
  final snapshot = database.loadSnapshot();
  openWatch.stop();

  final firstSearchWatch = Stopwatch()..start();
  final firstSearch = snapshot.cards
      .where((card) => card.title.toLowerCase().contains('карточка 0999'))
      .length;
  firstSearchWatch.stop();

  final repeatedSearchWatch = Stopwatch()..start();
  var repeatedMatches = 0;
  for (var index = 0; index < 25; index++) {
    repeatedMatches += snapshot.cards.where((card) {
      final query = 'user${index * 10}@example.com';
      return card.fieldValues.values.any(
        (value) => value.toLowerCase().contains(query),
      );
    }).length;
  }
  repeatedSearchWatch.stop();

  final card = snapshot.cards.last;
  final saveWatch = Stopwatch()..start();
  database.saveCard(
    SpbWalletCardDraft(
      id: card.id,
      title: '${card.title} изменена',
      description: card.description,
      categoryPath: card.categoryPath,
      templateId: card.templateId,
      fieldValues: card.fieldValues,
      iconId: card.iconId,
      cardColor: card.cardColor,
      fieldOrder: card.fieldOrder,
      hiddenFieldIds: card.hiddenFieldIds,
      modifiedAt: DateTime.now().toUtc(),
    ),
  );
  database.flushToDisk();
  saveWatch.stop();
  database.close();

  final report = <String, Object?>{
    'baselineCommit': '1bf4596',
    'timestampUtc': DateTime.now().toUtc().toIso8601String(),
    'platform': Platform.operatingSystem,
    'operatingSystemVersion': Platform.operatingSystemVersion,
    'fixture': {
      'cards': fixture.cardCount,
      'templates': fixture.templateCount,
      'folders': fixture.folderCount,
      'bytes': databaseFile.lengthSync(),
    },
    'milliseconds': {
      'fixtureGeneration': fixtureWatch.elapsedMilliseconds,
      'openAndLoadSnapshot': openWatch.elapsedMilliseconds,
      'firstSearch': firstSearchWatch.elapsedMicroseconds / 1000,
      'repeatedSearch25': repeatedSearchWatch.elapsedMicroseconds / 1000,
      'saveOneCardAndFlush': saveWatch.elapsedMilliseconds,
    },
    'validation': {
      'loadedCards': snapshot.cards.length,
      'firstSearchMatches': firstSearch,
      'repeatedSearchMatches': repeatedMatches,
    },
    'artifactBytes': _artifactSizes(),
  };
  final json = const JsonEncoder.withIndent('  ').convert(report);
  File('${outputDirectory.path}/database-baseline.json')
      .writeAsStringSync(json);
  stdout.writeln(json);
}

Map<String, int?> _artifactSizes() {
  final candidates = <String, String>{
    'windowsExe': 'build/windows/x64/runner/Release/wallet_aps.exe',
    'androidApk': 'build/app/outputs/flutter-apk/app-release.apk',
    'windowsSetup': '../dist/Wallet-APS-Setup.exe',
    'linuxDeb': '../dist/Wallet-APS-linux-amd64.deb',
  };
  return {
    for (final entry in candidates.entries)
      entry.key: File(entry.value).existsSync()
          ? File(entry.value).lengthSync()
          : null,
  };
}
