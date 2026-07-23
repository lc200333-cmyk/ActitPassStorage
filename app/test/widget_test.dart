import 'package:actit_pass_storage/main.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('card editor offers original SPB icons before pictograms',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(720, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: ItemEditorDialog(
          templates: builtInTemplates(),
          categories: const [],
        ),
      ),
    );
    await tester.pumpAndSettle();

    final original = find.byKey(const Key('spbCardIconPicker'));
    final pictogram = find.byKey(const Key('cardPictogramPicker'));
    expect(original, findsOneWidget);
    expect(pictogram, findsOneWidget);
    expect(tester.getTopLeft(original).dx,
        lessThan(tester.getTopLeft(pictogram).dx));

    await tester.tap(original);
    await tester.pumpAndSettle();
    expect(find.text('Иконки SPB Wallet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop vault uses the W1 three-column layout', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await tester.binding.setSurfaceSize(const Size(1280, 1010));
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      const MaterialApp(home: VaultShell(initiallyUnlocked: true)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Мои карточки'), findsNWidgets(2));
    expect(find.text('Задачи'), findsOneWidget);
    expect(find.text('Создать кошелёк'), findsOneWidget);
    expect(find.text('Создать новую папку'), findsOneWidget);
    expect(find.text('Сделать архивную копию'), findsOneWidget);
    await tester.tap(
      find.byKey(const Key('spbCentralWorkspace')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    expect(find.text('Создать карточку'), findsOneWidget);
    expect(find.text('Создать папку'), findsOneWidget);
    await tester.tapAt(const Offset(2, 2));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('mobile vault initially shows only the A1 tree', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.binding.setSurfaceSize(const Size(576, 1024));
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      const MaterialApp(home: VaultShell(initiallyUnlocked: true)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Мои карточки'), findsNWidgets(2));
    expect(find.text('Шаблоны'), findsOneWidget);
    expect(find.text('Задачи'), findsNothing);
    expect(find.text('−'), findsNothing);
    await tester.tap(find.byKey(const Key('spbWalletRoot')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('mobilePaneBack')), findsOneWidget);
    expect(find.byKey(const Key('mobilePaneForward')), findsOneWidget);
    await tester.tap(find.byKey(const Key('mobilePaneForward')));
    await tester.pumpAndSettle();
    expect(find.text('Задачи'), findsOneWidget);
    expect(find.byKey(const Key('mobilePaneBack')), findsOneWidget);
    expect(find.byKey(const Key('mobilePaneForward')), findsNothing);
    await tester.tap(find.byKey(const Key('mobilePaneBack')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('mobilePaneBack')));
    await tester.pumpAndSettle();
    expect(find.text('Мои карточки'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('renders vault entry screen', (tester) async {
    await tester.pumpWidget(const ActitPassApp());
    await tester.pump();

    expect(find.text('Пароль'), findsOneWidget);
    expect(find.byKey(const Key('passwordPrompt')), findsOneWidget);
    expect(find.byKey(const Key('passwordInput')), findsOneWidget);
    expect(find.text('CLR'), findsOneWidget);
    expect(find.text('<-'), findsOneWidget);
    expect(find.text('OK'), findsOneWidget);
    expect(find.text('Отмена'), findsOneWidget);
    expect(find.byKey(const Key('createVault')), findsOneWidget);
    expect(find.text('ABC'), findsOneWidget);
    expect(find.text('abc'), findsOneWidget);
    expect(find.text('123'), findsOneWidget);
    expect(find.text('#!?'), findsOneWidget);
  });

  testWidgets('touch keypad edits the focused password', (tester) async {
    await tester.pumpWidget(const ActitPassApp());
    await tester.pump();

    final field = tester.widget<TextField>(
      find.byKey(const Key('passwordInput')),
    );
    expect(field.focusNode!.hasFocus, isTrue);

    await tester.tap(find.byKey(const Key('keypad1')));
    field.controller!.selection = TextSelection(
      baseOffset: 0,
      extentOffset: field.controller!.text.length,
    );
    await tester.tap(find.byKey(const Key('keypad2')));
    expect(field.controller!.text, '12');

    await tester.tap(find.byKey(const Key('keypadBackspace')));
    expect(field.controller!.text, '1');

    await tester.tap(find.byKey(const Key('keypadClear')));
    expect(field.controller!.text, isEmpty);
    expect(field.focusNode!.hasFocus, isTrue);
  });

  testWidgets('physical keyboard input is accepted', (tester) async {
    await tester.pumpWidget(const ActitPassApp());
    await tester.pump();

    await tester.enterText(
      find.byKey(const Key('passwordInput')),
      'Key!9',
    );

    final field = tester.widget<TextField>(
      find.byKey(const Key('passwordInput')),
    );
    expect(field.controller!.text, 'Key!9');
  });

  testWidgets('ABC mode enters uppercase letters and returns to digits',
      (tester) async {
    await tester.pumpWidget(const ActitPassApp());
    await tester.pump();

    await tester.tap(find.byKey(const Key('keypadModeUppercase')));
    await tester.pump();

    expect(find.byKey(const Key('keypadLetterQ')), findsOneWidget);
    expect(find.byKey(const Key('keypadLetterP')), findsOneWidget);
    expect(find.byKey(const Key('keypad1')), findsNothing);

    await tester.tap(find.byKey(const Key('keypadLetterQ')));
    await tester.tap(find.byKey(const Key('keypadLetterW')));
    final field = tester.widget<TextField>(
      find.byKey(const Key('passwordInput')),
    );
    expect(field.controller!.text, 'QW');

    await tester.tap(find.byKey(const Key('keypadBackspace')));
    expect(field.controller!.text, 'Q');
    await tester.tap(find.byKey(const Key('keypadClear')));
    expect(field.controller!.text, isEmpty);

    await tester.tap(find.byKey(const Key('keypadModeNumeric')));
    await tester.pump();
    expect(find.byKey(const Key('keypad1')), findsOneWidget);
  });

  testWidgets('abc mode enters lowercase letters', (tester) async {
    await tester.pumpWidget(const ActitPassApp());
    await tester.pump();

    await tester.tap(find.byKey(const Key('keypadModeLowercase')));
    await tester.pump();

    expect(find.byKey(const Key('keypadLetterq')), findsOneWidget);
    expect(find.byKey(const Key('keypadLetterp')), findsOneWidget);
    expect(find.byKey(const Key('keypad1')), findsNothing);

    await tester.tap(find.byKey(const Key('keypadLetterq')));
    await tester.tap(find.byKey(const Key('keypadLetterw')));
    final field = tester.widget<TextField>(
      find.byKey(const Key('passwordInput')),
    );
    expect(field.controller!.text, 'qw');

    await tester.tap(find.byKey(const Key('keypadBackspace')));
    expect(field.controller!.text, 'q');
    await tester.tap(find.byKey(const Key('keypadClear')));
    expect(field.controller!.text, isEmpty);
  });

  testWidgets('symbol mode enters special characters and returns to digits',
      (tester) async {
    await tester.pumpWidget(const ActitPassApp());
    await tester.pump();

    await tester.tap(find.byKey(const Key('keypadModeSymbols')));
    await tester.pump();

    expect(find.byKey(const Key('keypadSymbol+')), findsOneWidget);
    expect(find.byKey(const Key('keypadSymbol?')), findsOneWidget);
    expect(find.byKey(const Key('keypad1')), findsNothing);

    await tester.tap(find.byKey(const Key('keypadSymbol!')));
    await tester.tap(find.byKey(const Key('keypadSymbol@')));
    await tester.tap(find.byKey(const Key('keypadSymbol#')));
    final field = tester.widget<TextField>(
      find.byKey(const Key('passwordInput')),
    );
    expect(field.controller!.text, '!@#');

    await tester.tap(find.byKey(const Key('keypadBackspace')));
    expect(field.controller!.text, '!@');

    await tester.tap(find.byKey(const Key('keypadModeNumeric')));
    await tester.pump();
    expect(find.byKey(const Key('keypad1')), findsOneWidget);
  });

  testWidgets('file button opens its menu', (tester) async {
    await tester.pumpWidget(const ActitPassApp());
    await tester.pump();

    await tester.tap(find.byKey(const Key('fileMenu')));
    await tester.pumpAndSettle();

    expect(find.text('Открыть файл…'), findsOneWidget);
  });

  testWidgets('new vault dialog never reuses the current password',
      (tester) async {
    await tester.pumpWidget(const ActitPassApp());
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('passwordInput')),
      'old-password',
    );

    await tester.tap(find.byKey(const Key('createVault')));
    await tester.pumpAndSettle();

    expect(find.text('Создание новой базы'), findsOneWidget);
    expect(find.byKey(const Key('newVaultDialogDragHandle')), findsOneWidget);
    expect(find.byKey(const Key('newVaultPath')), findsOneWidget);
    expect(find.byKey(const Key('browseNewVaultPath')), findsOneWidget);
    expect(find.byKey(const Key('newVaultName')), findsOneWidget);
    final confirmButton = find.byKey(const Key('confirmCreateVault'));
    final cancelButton = find.byKey(const Key('cancelCreateVault'));
    expect(
      find.descendant(of: confirmButton, matching: find.text('OK')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: cancelButton, matching: find.text('Отмена')),
      findsOneWidget,
    );
    expect(tester.getSize(confirmButton), const Size(110, 40));
    expect(tester.getSize(cancelButton), const Size(124, 40));
    final newPassword = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('newVaultPassword')),
        matching: find.byType(TextField),
      ),
    );
    final repeatedPassword = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('newVaultPasswordRepeat')),
        matching: find.byType(TextField),
      ),
    );
    expect(newPassword.controller!.text, isEmpty);
    expect(repeatedPassword.controller!.text, isEmpty);
  });

  testWidgets('login error is shown below all action buttons', (tester) async {
    await tester.pumpWidget(const ActitPassApp());
    await tester.pump();

    await tester.tap(find.byKey(const Key('loginOk')));
    await tester.pumpAndSettle();

    final message = find.byKey(const Key('loginMessage'));
    expect(message, findsOneWidget);
    expect(
      tester.getTopLeft(message).dy,
      greaterThan(
          tester.getBottomRight(find.byKey(const Key('loginCancel'))).dy),
    );
  });
}
