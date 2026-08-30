import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_aps/features/cards/card_models.dart';
import 'package:wallet_aps/features/templates/swt_template_codec.dart';

void main() {
  const template = CardTemplate(
    id: 'template-id',
    name: 'Сервер доступа',
    iconId: 'server',
    colorId: 'blue',
    categoryPath: 'Работа / Серверы',
    spbColor: 0x00112233,
    fields: [
      FieldDefinition(id: 'login', label: 'Логин', type: 'text'),
      FieldDefinition(
        id: 'password',
        label: 'Пароль',
        type: 'password',
        secret: true,
      ),
    ],
  );

  test('Wallet APS SWT JSON round-trip preserves every template property', () {
    final encoded = encodeSwtTemplate(template);
    final envelope = jsonDecode(utf8.decode(encoded)) as Map<String, dynamic>;
    expect(envelope['format'], 'WalletAPS.SWT');
    expect(envelope['version'], 1);

    final decoded = decodeSwtTemplate(encoded);
    expect(decoded.id, template.id);
    expect(decoded.name, template.name);
    expect(decoded.iconId, template.iconId);
    expect(decoded.colorId, template.colorId);
    expect(decoded.categoryPath, template.categoryPath);
    expect(decoded.spbColor, template.spbColor);
    expect(decoded.fields.map((field) => field.toJson()), [
      for (final field in template.fields) field.toJson(),
    ]);
  });

  test('decoder accepts the legacy Wallet APS JSON without an envelope', () {
    final bytes =
        Uint8List.fromList(utf8.encode(jsonEncode(template.toJson())));
    final decoded = decodeSwtTemplate(bytes);
    expect(decoded.name, template.name);
    expect(decoded.fields, hasLength(2));
  });

  test('decoder rejects empty, truncated and unrelated files safely', () {
    for (final bytes in <Uint8List>[
      Uint8List(0),
      Uint8List.fromList([1, 2, 3, 4]),
      Uint8List.fromList(utf8.encode('not a template')),
    ]) {
      expect(() => decodeSwtTemplate(bytes), throwsFormatException);
    }
  });
}
