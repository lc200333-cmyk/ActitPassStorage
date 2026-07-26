import 'dart:io';
import 'dart:typed_data';

import 'package:actit_pass_storage/main.dart';
import 'package:actit_pass_storage/spb_wallet/spb_wallet_database.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('imports the supplied legacy SPB Wallet SWT template', () {
    final bytes = Uint8List.fromList(
      File('../docs/Компьютеры- Сеть.swt').readAsBytesSync(),
    );
    final template = decodeSwtTemplate(bytes);

    expect(template.name, 'Компьютеры: Сеть');
    expect(template.fields, hasLength(14));
    expect(template.fields.first.label, 'Сеть');
    expect(template.fields.last.label, 'Пароль админ.');
    expect(template.fields.last.type, 'password');
  });

  test('permanently deleting a template removes its dependent cards', () {
    final directory =
        Directory.systemTemp.createTempSync('actitpass_template_delete_');
    addTearDown(() => directory.deleteSync(recursive: true));
    final database = SpbWalletDatabase.create(
      '${directory.path}${Platform.pathSeparator}template-delete.swl',
      '',
    );
    addTearDown(database.close);
    final templateId = SpbWalletDatabase.makeId();
    final fieldId = SpbWalletDatabase.makeId();
    database.saveTemplate(
      SpbWalletTemplateDraft(
        id: templateId,
        name: 'Удаляемый шаблон',
        fields: [
          SpbWalletTemplateFieldRecord(
            id: fieldId,
            name: 'Поле',
            templateId: templateId,
            fieldTypeId: 1,
          ),
        ],
      ),
    );
    database.saveCard(
      SpbWalletCardDraft(
        id: SpbWalletDatabase.makeId(),
        title: 'Связанная карточка',
        description: '',
        categoryPath: '',
        templateId: templateId,
        fieldValues: {fieldId: 'Значение'},
      ),
    );

    database.deleteTemplate(templateId);

    final snapshot = database.loadSnapshot();
    expect(
        snapshot.templates.where((entry) => entry.id == templateId), isEmpty);
    expect(snapshot.cards.where((entry) => entry.templateId == templateId),
        isEmpty);
  });

  testWidgets('template workspace opens edit, export and delete menu',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(home: VaultShell(initiallyUnlocked: true)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Шаблоны'));
    await tester.pumpAndSettle();
    expect(find.text('Удалить'), findsOneWidget);
    expect(find.byKey(const Key('spbTemplateWorkspace')), findsOneWidget);
    expect(
      find.byKey(const Key('spbCentralTemplate-tpl_password')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const Key('spbCentralTemplate-tpl_password')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('editTemplateContextAction')), findsOneWidget);
    expect(
      find.byKey(const Key('exportTemplateContextAction')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('deleteTemplateContextAction')),
      findsOneWidget,
    );
  });

  testWidgets('template empty workspace opens import menu', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(home: VaultShell(initiallyUnlocked: true)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Шаблоны'));
    await tester.pumpAndSettle();
    final workspace = find.byKey(const Key('spbTemplateWorkspace'));
    final emptyPoint = tester.getBottomRight(workspace) - const Offset(20, 20);
    await tester.tapAt(emptyPoint, buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();

    expect(
        find.byKey(const Key('importTemplateContextAction')), findsOneWidget);
  });

  testWidgets('card export creates password protected and passwordless SWL',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1010));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(home: VaultShell(initiallyUnlocked: true)),
    );
    await tester.pumpAndSettle();
    final dynamic state = tester.state(find.byType(VaultShell));
    final item = SecretItem(
      id: 'test-card',
      templateId: 'tpl_password',
      title: 'Экспортируемая карточка',
      category: 'Тест',
      colorId: 'blue',
      values: const {
        'username': 'tester',
        'password': 'secret-value',
        'notes': 'Примечание',
      },
      modifiedAt: DateTime(2026),
    );
    final directory = Directory.systemTemp.createTempSync('actitpass_export_');
    addTearDown(() => directory.deleteSync(recursive: true));

    final protectedPath = '${directory.path}${Platform.pathSeparator}card.swl';
    await state.createSpbItemsExportFile(
      [item],
      password: 'export-password',
      targetPath: protectedPath,
    );
    expect(
      () => SpbWalletDatabase.open(protectedPath, ''),
      throwsA(isA<SpbWalletOpenException>()),
    );
    final protected = SpbWalletDatabase.open(protectedPath, 'export-password');
    final protectedSnapshot = protected.loadSnapshot();
    protected.close();
    expect(protectedSnapshot.cards.single.title, item.title);
    expect(
      protectedSnapshot.cards.single.fieldValues.values,
      containsAll(['tester', 'secret-value', 'Примечание']),
    );

    final openPath = '${directory.path}${Platform.pathSeparator}open.swl';
    await state.createSpbItemsExportFile(
      [item],
      password: '',
      targetPath: openPath,
    );
    final passwordless = SpbWalletDatabase.open(openPath, '');
    expect(passwordless.loadSnapshot().cards.single.title, item.title);
    passwordless.close();
  });

  testWidgets('object menus do not open the empty workspace menu',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1010));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(home: VaultShell(initiallyUnlocked: true)),
    );
    await tester.pumpAndSettle();
    final dynamic state = tester.state(find.byType(VaultShell));
    state.items = [
      SecretItem(
        id: 'menu-card',
        templateId: 'tpl_password',
        title: 'Карточка меню',
        category: 'Папка меню',
        colorId: 'blue',
        values: const {'username': 'tester'},
        modifiedAt: DateTime(2026),
      ),
    ];
    state.selectedCategoryPath = 'Папка меню';
    state.setState(() {});
    await tester.pumpAndSettle();

    await tester.tap(
      find.text('Карточка меню').last,
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('exportObjectContextAction')), findsOneWidget);
    expect(find.byKey(const Key('copyCardContextAction')), findsOneWidget);
    expect(find.text('Создать карточку'), findsNothing);
    expect(find.text('Создать папку'), findsNothing);

    await tester.tapAt(const Offset(2, 2));
    await tester.pumpAndSettle();
    final workspace = find.byKey(const Key('spbCentralWorkspace'));
    final emptyPoint = tester.getBottomRight(workspace) - const Offset(20, 20);
    await tester.tapAt(emptyPoint, buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(find.text('Создать карточку'), findsOneWidget);
    expect(find.text('Создать папку'), findsOneWidget);
    expect(find.text('Импорт'), findsOneWidget);
  });
}
