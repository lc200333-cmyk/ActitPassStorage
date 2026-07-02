import 'package:actit_pass_storage/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders vault entry screen', (tester) async {
    await tester.pumpWidget(const ActitPassApp());

    expect(find.text('ActitPassStorage'), findsWidgets);
    expect(find.text('Открыть .swl'), findsOneWidget);
    expect(find.text('Создать .swl'), findsOneWidget);
    expect(find.text('Открыть .swl базу'), findsOneWidget);
    expect(find.text('Пароль .swl базы'), findsOneWidget);
    expect(find.text('Выбрать .swl файл'), findsOneWidget);
  });
}
