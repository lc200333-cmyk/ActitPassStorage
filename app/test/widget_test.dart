import 'package:actit_pass_storage/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders vault entry screen', (tester) async {
    await tester.pumpWidget(const ActitPassApp());

    expect(find.text('ActitPassStorage'), findsWidgets);
    expect(find.text('Открыть ActitPass'), findsOneWidget);
    expect(find.text('Создать ActitPass'), findsOneWidget);
    expect(find.text('Открыть SPB Wallet'), findsOneWidget);
    expect(find.text('Открыть базу'), findsOneWidget);
    expect(find.text('Мастер-пароль'), findsOneWidget);
  });
}
