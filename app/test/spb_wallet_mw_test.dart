import 'dart:io';
import 'package:actit_pass_storage/main.dart';
import 'package:actit_pass_storage/spb_wallet/spb_wallet_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _mwPassword = '7161';

final _fixture = File('../docs/MW.swl');
final _fixtureSkip = !_fixture.existsSync();

Future<T> _withWalletCopy<T>(
  Future<T> Function(SpbWalletDatabase wallet, File copy) action,
) async {
  final originalBytes = _fixture.readAsBytesSync();
  final directory = await Directory.systemTemp.createTemp('actit_mw_test_');
  final copy = File('${directory.path}${Platform.pathSeparator}MW.swl');
  copy.writeAsBytesSync(originalBytes, flush: true);
  final wallet = SpbWalletDatabase.open(copy.path, _mwPassword);
  try {
    return await action(wallet, copy);
  } finally {
    wallet.close();
    expect(_fixture.readAsBytesSync(), orderedEquals(originalBytes),
        reason: 'Тесты не должны изменять docs/MW.swl.');
    directory.deleteSync(recursive: true);
  }
}

CardTemplate _templateForTest(SpbWalletTemplateRecord source) {
  final fields = source.fields
      .map(
        (field) => FieldDefinition(
          id: field.id,
          label: field.name,
          type: spbFieldTypeToUi(field.fieldTypeId, field.name),
          secret: spbFieldIsSecret(field.fieldTypeId, field.name),
        ),
      )
      .toList();
  if (!fields.any((field) => field.id == spbDescriptionFieldId)) {
    fields.add(const FieldDefinition(
      id: spbDescriptionFieldId,
      label: 'Заметки',
      type: 'multiline_note',
    ));
  }
  return CardTemplate(
    id: source.id,
    name: source.name,
    iconId: source.iconId,
    colorId: 'neutral',
    fields: fields,
  );
}

void main() {
  late SpbWalletSnapshot responsiveSnapshot;

  setUpAll(() async {
    if (_fixtureSkip) return;
    responsiveSnapshot = await _withWalletCopy(
      (wallet, _) async => wallet.loadSnapshot(),
    );
  });

  testWidgets(
    'MW data renders at all supported phone and tablet sizes',
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

      for (final size in const [
        Size(320, 640),
        Size(360, 800),
        Size(412, 915),
        Size(640, 360),
        Size(800, 1280),
      ]) {
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
    skip: _fixtureSkip,
  );

  test('built-in IconID values use explicit matching assets', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadSpb64PngIconAssets();
    const expected = <String, String>{
      'A74FE6691728757D': 'icons_010.png', // Visa
      '4428DBE8E0FDBEF5': 'icons_011.png', // MasterCard
      '289B3CF7980A951E': 'icons_041.png', // Automobile
      'F7F133A9EDA8AD3E': 'icons_019.png', // Passport
      'EDE2A1A2E3B172D5': 'icons_066.png', // Warranty
      '38A06822A088D80F': 'icons_067.png', // Training
      '867CA874B9508C95': 'icons_021.png', // Email
      '30E614ECB34BA668': 'icons_048.png', // Travel visa
      '54320B4412A08007': 'icons_003.png', // Credit cards folder
      'E864A803F91DA5C4': 'icons_005.png', // Finance folder
      '4863F2D4E9D399F6': 'icons_006.png', // Personal folder
      '96DAFC9A4C1F55F6': 'icons_004.png', // Family folder
      '5D595FE47887E6C9': 'icons_008.png', // Work folder
      '6E4AAD6B4F39E378': 'icons_002.png', // Computers folder
      '0C1E037B56E9E59B': 'icons_001.png', // Leisure folder
    };

    for (final entry in expected.entries) {
      final asset = spbOriginalIconAsset(entry.key);
      expect(asset, endsWith(entry.value), reason: 'IconID ${entry.key}');
    }
    for (final asset in spbOriginalIconAssets.values) {
      expect(spbPackedIconBytes(asset), isNotNull, reason: asset);
    }
    expect(spbOriginalIconAsset('7F0C2A5120A13A94'), isNull);
  });

  test(
    'MW loads all templates, cards, notes and embedded icons',
    () async {
      await _withWalletCopy((wallet, _) async {
        final snapshot = wallet.loadSnapshot();
        expect(snapshot.templates, hasLength(60));
        expect(snapshot.cards, hasLength(245));
        expect(
          snapshot.cards.where((card) => card.description.trim().isNotEmpty),
          hasLength(215),
        );

        final templates = {
          for (final source in snapshot.templates)
            source.id: _templateForTest(source),
        };
        var accessibleNotes = 0;
        for (final card in snapshot.cards) {
          if (card.description.trim().isEmpty) continue;
          final template = templates[card.templateId]!;
          final values = spbCardValuesForUi(template, card);
          expect(
            values[noteFieldIdForTemplate(template)]?.trim(),
            isNotEmpty,
            reason: 'Заметка карточки должна быть доступна в UI-модели.',
          );
          accessibleNotes++;
        }
        expect(accessibleNotes, 215);

        expect(snapshot.embeddedIconPngs, hasLength(4));
        for (final bytes in snapshot.embeddedIconPngs.values) {
          expect(
            bytes.take(8),
            orderedEquals(const [137, 80, 78, 71, 13, 10, 26, 10]),
          );
        }
        for (final template in snapshot.templates) {
          expect(
            spbOriginalIconAsset(template.iconId) != null ||
                snapshot.embeddedIconPngs.containsKey(template.iconId),
            isTrue,
            reason:
                'Иконка ${template.iconId} должна иметь asset или встроенные данные.',
          );
        }
      });
    },
    skip: _fixtureSkip,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'MW field types hide secrets and do not treat names as dates',
    () async {
      await _withWalletCopy((wallet, _) async {
        final snapshot = wallet.loadSnapshot();
        final typeFourFields = snapshot.templates
            .expand((template) => template.fields)
            .where((field) => field.fieldTypeId == 4)
            .toList();
        expect(typeFourFields, isNotEmpty);
        for (final field in typeFourFields) {
          expect(spbFieldIsSecret(field.fieldTypeId, field.name), isTrue);
          final definition = FieldDefinition(
            id: field.id,
            label: field.name,
            type: spbFieldTypeToUi(field.fieldTypeId, field.name),
            secret: spbFieldIsSecret(field.fieldTypeId, field.name),
          );
          expect(fieldDefinitionIsSecret(definition), isTrue);
          expect(
            fieldDisplayValue(definition, 'sensitive', revealed: false),
            '••••••••',
          );
        }

        final typeThreeFields = snapshot.templates
            .expand((template) => template.fields)
            .where((field) => field.fieldTypeId == 3)
            .toList();
        expect(typeThreeFields, isNotEmpty);
        for (final field in typeThreeFields) {
          expect(
              spbFieldTypeToUi(field.fieldTypeId, field.name), isNot('date'));
        }
      });
    },
    skip: _fixtureSkip,
  );

  test(
    'MW card round-trip preserves every field value and unknown values',
    () async {
      await _withWalletCopy((wallet, _) async {
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
              fieldValues: card.fieldValues,
              iconId: card.iconId,
              cardColor: card.cardColor,
              backgroundImageBase64: card.backgroundImageBase64,
            ),
          );
        }

        final cardWithSeveralValues = before.cards.firstWhere(
          (card) => card.fieldValues.length >= 2,
        );
        final omittedEntry = cardWithSeveralValues.fieldValues.entries.first;
        wallet.saveCard(
          SpbWalletCardDraft(
            id: cardWithSeveralValues.id,
            title: cardWithSeveralValues.title,
            description: cardWithSeveralValues.description,
            categoryPath: cardWithSeveralValues.categoryPath,
            templateId: cardWithSeveralValues.templateId,
            fieldValues: Map<String, String>.from(
              cardWithSeveralValues.fieldValues,
            )..remove(omittedEntry.key),
            iconId: cardWithSeveralValues.iconId,
            cardColor: cardWithSeveralValues.cardColor,
          ),
        );

        final after = wallet.loadSnapshot();
        expect(after.templates, hasLength(60));
        expect(after.cards, hasLength(245));
        for (final card in after.cards) {
          expect(
            card.fieldValues,
            beforeById[card.id]!.fieldValues,
            reason: 'Значения карточки ${card.id} изменились после сохранения.',
          );
        }
      });
    },
    skip: _fixtureSkip,
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'embedded ICO is rendered from decoded PNG bytes',
    () async {
      await _withWalletCopy((wallet, _) async {
        final snapshot = wallet.loadSnapshot();
        final entry = snapshot.embeddedIconPngs.entries.first;
        spbEmbeddedIconPngs = {entry.key: Uint8List.fromList(entry.value)};
        addTearDown(() => spbEmbeddedIconPngs = {});

        final image = templateIconWidget(entry.key, size: 48) as Image;
        expect(image.image, isA<MemoryImage>());
        expect(image.width, 48);
        expect(image.height, 48);

        // Embedded ICO must win even when the same ID has a library PNG.
        spbEmbeddedIconPngs = {
          'A74FE6691728757D': Uint8List.fromList(entry.value),
        };
        final overridden =
            templateIconWidget('A74FE6691728757D', size: 48) as Image;
        expect(overridden.image, isA<MemoryImage>());
      });
    },
    skip: _fixtureSkip,
  );

  testWidgets('card field list has a persistent scrollbar', (tester) async {
    final template = CardTemplate(
      id: 'template',
      name: 'Template',
      iconId: 'key',
      colorId: 'neutral',
      fields: List.generate(
        8,
        (index) => FieldDefinition(
          id: 'field-$index',
          label: 'Поле $index',
          type: 'text',
        ),
      ),
    );
    final item = SecretItem(
      id: 'item',
      templateId: template.id,
      title: 'Карточка',
      category: '',
      colorId: 'neutral',
      values: {
        for (final field in template.fields) field.id: 'Значение ${field.id}',
      },
      modifiedAt: DateTime(2026),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          height: 180,
          child: CardFieldValuesList(
            fields: template.fields,
            item: item,
            foreground: Colors.black,
            revealed: const {},
            onToggle: (_, __) {},
          ),
        ),
      ),
    );
    await tester.pump();

    final scrollbar =
        tester.widget<Scrollbar>(find.byKey(const Key('cardFieldsScrollbar')));
    expect(scrollbar.thumbVisibility, isTrue);
    expect(tester.takeException(), isNull);
  });
}
