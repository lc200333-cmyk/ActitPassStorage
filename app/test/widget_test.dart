import 'package:actit_pass_storage/main.dart';
import 'package:actit_pass_storage/spb_wallet/spb_wallet_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('third-party Visual Studio icon bundle is available',
      (tester) async {
    final icons = await loadThirdPartyIconAssets();

    expect(icons, hasLength(1356));
    expect(thirdPartyIconPngs[icons.first], isNotEmpty);
  });

  test('selected template icon survives the stored IconID round trip', () {
    const selected = 'spb://third_party/custom_icon.png';
    final previousAssets = spb64PngIconAssets;
    spb64PngIconAssets = const [selected];
    addTearDown(() => spb64PngIconAssets = previousAssets);
    final storedIconId = syntheticSpbIconIdForUi(selected);
    final loadedIconId = spbTemplateIconForUi(
      SpbWalletTemplateRecord(
        id: 'template',
        name: 'Название не определяет иконку',
        iconId: storedIconId,
        fields: const [],
      ),
    );

    expect(loadedIconId, selected);
  });

  testWidgets('template editor uses SPB layout and supports local undo',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final template = builtInTemplates().first;

    await tester.pumpWidget(
      MaterialApp(home: TemplateEditorDialog(initial: template)),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byKey(const Key('templateEditorSurface'))),
      const Size(360, 800),
    );
    expect(find.byKey(const Key('templateNameField')), findsOneWidget);
    expect(find.byKey(const Key('templateBoundIcon')), findsOneWidget);
    expect(find.text('Выбрать иконку'), findsOneWidget);
    expect(find.byKey(const Key('templateSpbDefaultButton')), findsOneWidget);
    expect(find.byKey(const Key('templatePictogramsButton')), findsOneWidget);
    expect(find.byKey(const Key('templateIconsButton')), findsOneWidget);
    expect(find.byKey(const Key('templateUploadIconButton')), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>)
                .value
                .startsWith('templateColor-'),
      ),
      findsNWidgets(16),
    );
    expect(find.byKey(const Key('templateUndoButton')), findsOneWidget);
    expect(find.byKey(const Key('templateSaveButton')), findsOneWidget);
    expect(find.byKey(const Key('templateCloseButton')), findsOneWidget);
    final externalIcons = tester.widget<InkWell>(
      find.descendant(
        of: find.byKey(const Key('templateIconsButton')),
        matching: find.byType(InkWell),
      ),
    );
    expect(externalIcons.onTap, isNotNull);
    final uploadIcon = tester.widget<InkWell>(
      find.descendant(
        of: find.byKey(const Key('templateUploadIconButton')),
        matching: find.byType(InkWell),
      ),
    );
    expect(uploadIcon.onTap, isNotNull);
    final iconFrame = tester.widget<Container>(
      find.byKey(const Key('templateBoundIcon')),
    );
    final iconDecoration = iconFrame.decoration! as BoxDecoration;
    expect((iconDecoration.border! as Border).top.width, 2);
    expect(iconDecoration.borderRadius, BorderRadius.circular(5));
    expect(iconDecoration.boxShadow, isNotEmpty);

    await tester.tap(
      find.byKey(const ValueKey('templateColor-template_sky')),
    );
    await tester.pump();
    final coloredNameField = tester.widget<TextField>(
      find.byKey(ValueKey('templateFieldName-${template.fields.first.id}')),
    );
    final coloredTypeField = tester.widget<DropdownButtonFormField<String>>(
      find.byKey(ValueKey('templateFieldType-${template.fields.first.id}')),
    );
    expect(
        coloredNameField.decoration!.fillColor, colorById('template_sky').bg);
    expect(coloredTypeField.decoration.fillColor, colorById('template_sky').bg);
    expect(tester.takeException(), isNull);

    final firstField =
        find.byKey(ValueKey('templateField-${template.fields.first.id}'));
    final secondField =
        find.byKey(ValueKey('templateField-${template.fields[1].id}'));
    final firstFieldId = template.fields.first.id;
    final deleteButton =
        find.byKey(ValueKey('templateFieldDelete-$firstFieldId'));
    final upButton = find.byKey(ValueKey('templateFieldUp-$firstFieldId'));
    expect(tester.getSize(deleteButton).width, tester.getSize(upButton).width);
    expect(
      tester
          .getTopRight(
            find.byKey(ValueKey('templateFieldName-$firstFieldId')),
          )
          .dx,
      tester
          .getTopRight(
            find.byKey(ValueKey('templateFieldType-$firstFieldId')),
          )
          .dx,
    );
    expect(
      tester.getTopLeft(firstField).dy,
      lessThan(tester.getTopLeft(secondField).dy),
    );
    await tester.tap(
      find.byKey(ValueKey('templateFieldDown-${template.fields.first.id}')),
    );
    await tester.pump();
    expect(
      tester.getTopLeft(firstField).dy,
      greaterThan(tester.getTopLeft(secondField).dy),
    );
    await tester.tap(find.byKey(const Key('templateUndoButton')));
    await tester.pump();
    expect(
      tester.getTopLeft(firstField).dy,
      lessThan(tester.getTopLeft(secondField).dy),
    );
    final nameField = find.byKey(const Key('templateNameField'));
    await tester.tap(nameField);
    await tester.enterText(nameField, 'Изменённый шаблон');
    await tester.pump();
    await tester.tap(find.byKey(const Key('templateUndoButton')));
    await tester.pump();

    final field = tester.widget<TextField>(nameField);
    expect(field.controller!.text, template.name);
    expect(tester.takeException(), isNull);
  });

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
    final undo = find.byTooltip('Отменить изменения этой сессии');
    final trash = find.byTooltip('Восстановить удалённые');
    final forceClose = find.byKey(const Key('spbForceCloseButton'));
    expect(undo, findsOneWidget);
    expect(trash, findsOneWidget);
    expect(forceClose, findsOneWidget);
    expect(tester.getTopLeft(undo).dx, lessThan(tester.getTopLeft(trash).dx));
    expect(
      tester.getTopRight(trash).dx,
      closeTo(1023, 0.6),
      reason:
          'Правая граница зелёной кнопки должна совпадать с разделителем центрального и правого окон.',
    );
    final undoToTrashGap =
        tester.getTopLeft(trash).dx - tester.getTopRight(undo).dx;
    final trashToCloseGap =
        tester.getTopLeft(forceClose).dx - tester.getTopRight(trash).dx;
    expect(undoToTrashGap, greaterThan(0));
    expect(trashToCloseGap, closeTo(undoToTrashGap, 0.1));
    expect(
      tester.getCenter(forceClose).dy,
      closeTo(tester.getCenter(trash).dy, 0.1),
    );
    await tester.tap(
      find.byKey(const Key('spbCentralWorkspace')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    expect(find.text('Создать карточку'), findsOneWidget);
    expect(find.text('Создать папку'), findsOneWidget);
    await tester.tapAt(const Offset(2, 2));
    await tester.pumpAndSettle();
    final dynamic state = tester.state(find.byType(VaultShell));
    state.mobileTemplatesOpen = true;
    state.selectedTemplateId = state.templates.first.id;
    state.setState(() {});
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        ValueKey('spbCentralTemplate-${state.templates.first.id}'),
      ),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('copyTemplateContextAction')), findsOneWidget);
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
    expect(find.byKey(const Key('spbWalletRoot')), findsNothing);
    expect(find.byKey(const Key('spbClearSearchButton')), findsOneWidget);
    expect(find.byKey(const Key('spbSubmitSearchButton')), findsOneWidget);
    expect(
      find.byTooltip('Отменить изменения этой сессии'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('spbForceCloseButton')), findsOneWidget);
    await tester.tap(find.byKey(const Key('spbMobilePaneHeader')));
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

  testWidgets('vault layout adapts to phones, landscape and tablet',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.setSurfaceSize(null);
    });
    const mobileSizes = [
      Size(320, 640),
      Size(360, 800),
      Size(412, 915),
      Size(640, 360),
    ];
    for (final size in mobileSizes) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(
        const MaterialApp(home: VaultShell(initiallyUnlocked: true)),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('spbMobilePaneHeader')), findsOneWidget,
          reason: 'Размер $size должен использовать мобильную компоновку.');
      expect(find.byKey(const Key('spbMobileWalletTitle')), findsNothing,
          reason: 'Название кошелька не должно занимать место в списке.');
      expect(tester.takeException(), isNull, reason: 'Размер $size');
      await tester.pumpWidget(const SizedBox.shrink());
    }

    await tester.binding.setSurfaceSize(const Size(800, 1280));
    await tester.pumpWidget(
      const MaterialApp(home: VaultShell(initiallyUnlocked: true)),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('spbNavigatorSplitter')), findsOneWidget);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('mobile templates have one header and reachable tasks',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.setSurfaceSize(null);
    });
    await tester.pumpWidget(
      const MaterialApp(home: VaultShell(initiallyUnlocked: true)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Шаблоны'));
    await tester.pumpAndSettle();
    // Заголовок и нижняя кнопка режима, без второго заголовка рабочей области.
    expect(find.text('Шаблоны'), findsNWidgets(2));
    expect(
      find.byKey(const Key('mobileTemplateTasksForward')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('mobileTemplateTasksForward')));
    await tester.pumpAndSettle();
    expect(find.text('Задачи'), findsOneWidget);
    expect(find.text('Удалить'), findsOneWidget);
    expect(find.byKey(const Key('mobilePaneBack')), findsOneWidget);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('password screen remains usable at narrow phone sizes',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.setSurfaceSize(null);
    });
    for (final size in const [Size(320, 640), Size(360, 800), Size(412, 915)]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(const ActitPassApp());
      await tester.pump();
      expect(find.byKey(const Key('passwordInput')), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const Key('keypad1'))).height,
        greaterThanOrEqualTo(60),
        reason: 'Кнопки не должны уменьшаться на экране $size.',
      );
      expect(tester.takeException(), isNull, reason: 'Размер $size');
      await tester.pumpWidget(const SizedBox.shrink());
    }
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

  testWidgets('switching vault clears password and returns to login',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(720, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(home: VaultShell(initiallyUnlocked: true)),
    );
    await tester.pumpAndSettle();

    final dynamic state = tester.state(find.byType(VaultShell));
    state.passwordController.text = 'must-not-remain-in-memory';
    await state.closeCurrentVaultForPasswordPrompt();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('passwordInput')), findsOneWidget);
    final field = tester.widget<TextField>(
      find.byKey(const Key('passwordInput')),
    );
    expect(field.controller!.text, isEmpty);
    expect(tester.takeException(), isNull);
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
