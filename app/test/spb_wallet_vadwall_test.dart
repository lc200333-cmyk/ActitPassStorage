import 'dart:io';

import 'package:wallet_aps/main.dart';
import 'package:wallet_aps/spb_wallet/spb_wallet_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _password = '2222';
final _source = File('../docs/VadWall.swl');
final _skip = !_source.existsSync();

CardTemplate _uiTemplate(SpbWalletTemplateRecord source) {
  final fields = source.fields
      .map(
        (field) => FieldDefinition(
          id: field.id,
          label: field.name,
          type: spbFieldTypeToUi(field.fieldTypeId, field.name),
          secret: spbFieldIsSecret(field.fieldTypeId, field.name),
        ),
      )
      .toList()
    ..add(const FieldDefinition(
      id: spbDescriptionFieldId,
      label: 'Заметки',
      type: 'multiline_note',
    ));
  return CardTemplate(
    id: source.id,
    name: source.name,
    iconId: source.iconId,
    colorId: 'neutral',
    fields: fields,
  );
}

Future<T> _withCopy<T>(
  Future<T> Function(SpbWalletDatabase wallet) action,
) async {
  final original = _source.readAsBytesSync();
  final directory = await Directory.systemTemp.createTemp('vadwall_test_');
  final copy = File('${directory.path}${Platform.pathSeparator}VadWall.swl')
    ..writeAsBytesSync(original, flush: true);
  final wallet = SpbWalletDatabase.open(copy.path, _password);
  try {
    return await action(wallet);
  } finally {
    wallet.close();
    expect(_source.readAsBytesSync(), orderedEquals(original));
    directory.deleteSync(recursive: true);
  }
}

void main() {
  late SpbWalletSnapshot responsiveSnapshot;

  setUpAll(() async {
    if (_skip) return;
    responsiveSnapshot = await _withCopy(
      (wallet) async => wallet.loadSnapshot(),
    );
  });

  testWidgets(
    'VadWall data renders in phone and tablet layouts',
    (tester) async {
      final templateIds =
          responsiveSnapshot.templates.take(8).map((entry) => entry.id).toSet();
      final uiSnapshot = SpbWalletSnapshot(
        templates: responsiveSnapshot.templates
            .where((entry) => templateIds.contains(entry.id))
            .toList(),
        cards: responsiveSnapshot.cards
            .where((entry) => templateIds.contains(entry.templateId))
            .take(20)
            .toList(),
        categories: responsiveSnapshot.categories,
        embeddedIconPngs: responsiveSnapshot.embeddedIconPngs,
      );
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
        tester.binding.setSurfaceSize(null);
      });
      for (final size in const [Size(360, 800), Size(800, 1280)]) {
        await tester.binding.setSurfaceSize(size);
        await tester.pumpWidget(
          const MaterialApp(home: VaultShell(initiallyUnlocked: true)),
        );
        await tester.pumpAndSettle();
        final dynamic state = tester.state(find.byType(VaultShell));
        state.applySpbSnapshot(uiSnapshot);
        state.setState(() {});
        await tester.pump();

        expect(state.items, hasLength(uiSnapshot.cards.length),
            reason: 'Размер $size');
        expect(state.templates, hasLength(uiSnapshot.templates.length),
            reason: 'Размер $size');
        expect(tester.takeException(), isNull, reason: 'Размер $size');
        await tester.pumpWidget(const SizedBox.shrink());
      }
      debugDefaultTargetPlatformOverride = null;
      await tester.binding.setSurfaceSize(null);
    },
    skip: _skip,
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'VadWall loads every card, template, folder, value and note',
    () async {
      await _withCopy((wallet) async {
        final snapshot = wallet.loadSnapshot();
        expect(snapshot.cards, hasLength(58));
        expect(snapshot.templates, hasLength(60));
        expect(snapshot.categories, hasLength(10));
        expect(snapshot.embeddedIconPngs, hasLength(4));
        expect(
          snapshot.cards.fold<int>(
            0,
            (total, card) => total + card.fieldValues.length,
          ),
          219,
        );

        final templates = {
          for (final source in snapshot.templates)
            source.id: _uiTemplate(source),
        };
        final cardsWithNotes = snapshot.cards
            .where((card) => card.description.trim().isNotEmpty)
            .toList();
        expect(cardsWithNotes, hasLength(44));
        for (final card in cardsWithNotes) {
          final template = templates[card.templateId]!;
          expect(noteFieldIdForTemplate(template), spbDescriptionFieldId);
          expect(
            spbCardValuesForUi(template, card)[spbDescriptionFieldId],
            card.description,
          );
        }
      });
    },
    skip: _skip,
  );

  test(
    'VadWall round-trip preserves all live values and descriptions',
    () async {
      await _withCopy((wallet) async {
        final before = wallet.loadSnapshot();
        final beforeById = {for (final card in before.cards) card.id: card};
        for (final card in before.cards) {
          wallet.saveCard(
            SpbWalletCardDraft(
              id: card.id,
              title: card.title,
              description: card.description,
              categoryPath: card.categoryPath,
              templateId: card.templateId,
              fieldValues: Map<String, String>.from(card.fieldValues),
              iconId: card.iconId,
              cardColor: card.cardColor,
              backgroundImageBase64: card.backgroundImageBase64,
            ),
          );
        }

        final after = wallet.loadSnapshot();
        expect(after.cards, hasLength(58));
        expect(after.templates, hasLength(60));
        expect(after.categories, hasLength(10));
        expect(
          after.cards.fold<int>(
            0,
            (total, card) => total + card.fieldValues.length,
          ),
          219,
        );
        for (final card in after.cards) {
          final original = beforeById[card.id]!;
          expect(card.fieldValues, original.fieldValues, reason: card.id);
          expect(card.description, original.description, reason: card.id);
        }
      });
    },
    skip: _skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'VadWall uses embedded, template, folder and card icon priorities',
    () async {
      await _withCopy((wallet) async {
        final snapshot = wallet.loadSnapshot();
        spbEmbeddedIconPngs =
            Map<String, Uint8List>.from(snapshot.embeddedIconPngs);
        addTearDown(() => spbEmbeddedIconPngs = {});

        final embeddedTemplate = snapshot.templates.singleWhere(
          (template) => template.name.toLowerCase() == 'hlam',
        );
        expect(
          spbTemplateIconForUi(embeddedTemplate),
          embeddedTemplate.iconId,
        );
        final embeddedWidget =
            templateIconWidget(embeddedTemplate.iconId, size: 48) as Image;
        expect(embeddedWidget.image, isA<MemoryImage>());

        final passwordTemplate = snapshot.templates.singleWhere(
          (template) => template.name.toLowerCase().contains('пароль'),
        );
        expect(
          spbTemplateIconForUi(passwordTemplate),
          endsWith('icons_030.png'),
        );
        final recordsTemplate = snapshot.templates.singleWhere(
          (template) => template.name.toLowerCase().contains('записи, файлы'),
        );
        expect(
          spbOriginalIconAsset(recordsTemplate.iconId),
          endsWith('icons_061.png'),
        );

        const expectedFolders = <String, String>{
          'Air': 'icons_007.png',
          'Auto': 'icons_009.png',
          'Bank': 'icons_005.png',
          'Семейные': 'icons_004.png',
          'Финансовые': 'icons_005.png',
          '1234': 'icons_001.png',
          'Hlam': 'icons_001.png',
          'PASS': 'icons_001.png',
          'test': 'icons_001.png',
          'УРА': 'icons_001.png',
        };
        for (final category in snapshot.categories) {
          final rendered = spbFolderIconAsset(category.name, category.iconId);
          final synthetic = uiIconIdFromSyntheticSpbIcon(category.iconId);
          if (snapshot.embeddedIconPngs.containsKey(category.iconId)) {
            expect(rendered, category.iconId, reason: category.name);
            continue;
          }
          if (synthetic != null) {
            expect(rendered, synthetic, reason: category.name);
            continue;
          }
          final original = spbOriginalIconAsset(category.iconId);
          if (original != null) {
            expect(rendered, original, reason: category.name);
            continue;
          }
          expect(
            rendered,
            endsWith(expectedFolders[category.name]!),
            reason: category.name,
          );
        }

        final templatesById = {
          for (final template in snapshot.templates)
            template.id: spbTemplateIconForUi(template),
        };
        final nonLibraryCardIcons = snapshot.cards.where(
          (card) =>
              !snapshot.embeddedIconPngs.containsKey(card.iconId) &&
              spbOriginalIconAsset(card.iconId) == null,
        );
        expect(nonLibraryCardIcons, hasLength(2));
        for (final card in nonLibraryCardIcons) {
          final synthetic = uiIconIdFromSyntheticSpbIcon(card.iconId);
          expect(
            spbCardIconForUi(card.iconId, templatesById[card.templateId]!),
            synthetic ?? templatesById[card.templateId],
          );
        }
        expect(
          spbCardIconForUi(
            'FFFFFFFFFFFFFFFF',
            templatesById.values.first,
          ),
          templatesById.values.first,
        );
      });
    },
    skip: _skip,
  );

  testWidgets('field list resets on card change and hides Description',
      (tester) async {
    final fields = [
      ...List.generate(
        20,
        (index) => FieldDefinition(
          id: 'field-$index',
          label: 'Field $index',
          type: 'text',
        ),
      ),
      const FieldDefinition(
        id: spbDescriptionFieldId,
        label: 'Заметки',
        type: 'multiline_note',
      ),
    ];
    SecretItem item(String id, int count) => SecretItem(
          id: id,
          templateId: 'template',
          title: id,
          category: '',
          colorId: 'neutral',
          values: {
            for (var index = 0; index < count; index++)
              'field-$index': 'value-$index',
            spbDescriptionFieldId: 'description-$id',
          },
          modifiedAt: DateTime(2026),
        );
    Widget list(SecretItem value) => MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 220,
              child: CardFieldValuesList(
                fields: fields,
                item: value,
                foreground: Colors.black,
                revealed: const {},
                onToggle: (_, __) {},
              ),
            ),
          ),
        );

    await tester.pumpWidget(list(item('first', 20)));
    await tester.drag(
      find.byKey(const Key('cardFieldsScrollbar')),
      const Offset(0, -900),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .pixels,
      greaterThan(0),
    );

    await tester.pumpWidget(list(item('second', 14)));
    await tester.pumpAndSettle();
    expect(
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .pixels,
      0,
    );
    expect(find.byKey(const ValueKey('second:field-0')), findsOneWidget);
    expect(find.text('description-second'), findsNothing);
  });
}
