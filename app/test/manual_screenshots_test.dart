import 'dart:io';

import 'package:wallet_aps/main.dart';
import 'package:wallet_aps/spb_wallet/spb_wallet_database.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final _demoFixture = File('../.tmp/Wallet-APS-demo.swl');
final _skipManualGoldens = !_demoFixture.existsSync();

void main() {
  late SpbWalletSnapshot snapshot;

  setUpAll(() async {
    if (_skipManualGoldens) return;
    TestWidgetsFlutterBinding.ensureInitialized();
    final fontFile = File(r'C:\Windows\Fonts\arial.ttf');
    if (fontFile.existsSync()) {
      final fontBytes = await fontFile.readAsBytes();
      final loader = FontLoader('ManualArial')
        ..addFont(Future.value(ByteData.sublistView(fontBytes)));
      await loader.load();
    }
    await loadSpb64PngIconAssets();
    final wallet = SpbWalletDatabase.open(
      _demoFixture.path,
      '2468',
    );
    try {
      snapshot = wallet.loadSnapshot();
    } finally {
      wallet.close();
    }
  });

  Future<dynamic> pumpShell(
    WidgetTester tester, {
    Size size = const Size(1280, 800),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        builder: (context, child) => child ?? const SizedBox.shrink(),
        theme: ThemeData(
          useMaterial3: true,
          fontFamily: 'ManualArial',
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xff2d6f73),
          ),
          scaffoldBackgroundColor: const Color(0xfff5f7f8),
        ),
        home: const VaultShell(initiallyUnlocked: true),
      ),
    );
    await tester.pumpAndSettle();
    final dynamic state = tester.state(find.byType(VaultShell));
    state.applySpbSnapshot(snapshot);
    state.vaultNameController.text = 'Демонстрационная база';
    state.selectedItemId = state.items.first.id;
    state.setState(() {});
    await tester.pumpAndSettle();
    return state;
  }

  Future<void> golden(WidgetTester tester, String name) async {
    await expectLater(
      find.byType(Overlay).first,
      matchesGoldenFile('goldens/manual/$name.png'),
    );
  }

  testWidgets('desktop cards and menus', (tester) async {
    final dynamic state = await pumpShell(tester);
    await golden(tester, '03-cards');

    state.selectedCategoryPath = 'Личное / Учётные записи';
    state.setState(() {});
    await tester.pumpAndSettle();
    await tester.tap(
      find.text('Почта').last,
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await golden(tester, '04-card-context-menu');

    await tester.tap(find.text('Открыть').last);
    await tester.pumpAndSettle();
    await golden(tester, '05-card-preview');
  }, skip: _skipManualGoldens);

  testWidgets('desktop templates and editor', (tester) async {
    final dynamic state = await pumpShell(tester);
    state.mobileTemplatesOpen = true;
    state.selectedTemplateId = state.templates.first.id;
    state.setState(() {});
    await tester.pumpAndSettle();
    await golden(tester, '06-templates');

    await tester.tap(
      find.byKey(ValueKey('spbCentralTemplate-${state.templates.first.id}')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await golden(tester, '07-template-context-menu');

    await tester.tap(find.byKey(const Key('editTemplateContextAction')));
    await tester.pumpAndSettle();
    await golden(tester, '08-template-editor');
  }, skip: _skipManualGoldens);

  testWidgets('phone cards and templates', (tester) async {
    final dynamic state = await pumpShell(
      tester,
      size: const Size(412, 915),
    );
    await golden(tester, '11-mobile-cards');

    state.mobileTemplatesOpen = true;
    state.selectedTemplateId = state.templates.first.id;
    state.setState(() {});
    await tester.pumpAndSettle();
    await golden(tester, '12-mobile-templates');
  }, skip: _skipManualGoldens);
}
