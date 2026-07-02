import 'package:actit_pass_storage/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders vault entry screen', (tester) async {
    await tester.pumpWidget(const ActitPassApp());

    expect(find.text('ActitPassStorage'), findsWidgets);
    expect(find.text('Открыть'), findsOneWidget);
    expect(find.text('Создать'), findsOneWidget);
    expect(find.text('Открыть базу'), findsOneWidget);
    expect(find.text('Мастер-пароль'), findsOneWidget);
  });
}
