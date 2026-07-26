import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/main.dart';
import '../lib/spb_wallet/spb_wallet_database.dart';

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

  testWidgets('template right click opens edit and export menu',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(home: VaultShell(initiallyUnlocked: true)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Шаблоны'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('spbTemplate-tpl_password')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('editTemplateContextAction')), findsOneWidget);
    expect(
      find.byKey(const Key('exportTemplateContextAction')),
      findsOneWidget,
    );
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
