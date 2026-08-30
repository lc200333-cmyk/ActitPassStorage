import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../../core/id_generator.dart';
import '../cards/card_models.dart';
import '../cards/field_types.dart';
import 'template_defaults.dart';

int _uint32(Uint8List bytes, int offset) {
  if (offset < 0 || offset + 4 > bytes.length) {
    throw const FormatException('Повреждённый файл шаблона.');
  }
  return ByteData.sublistView(
    bytes,
    offset,
    offset + 4,
  ).getUint32(0, Endian.little);
}

String _utf16(Uint8List bytes, int offset, int length) {
  if (length < 0 || offset < 0 || offset + length * 2 > bytes.length) {
    throw const FormatException('Повреждённая строка шаблона.');
  }
  final data = ByteData.sublistView(bytes, offset, offset + length * 2);
  return String.fromCharCodes([
    for (var index = 0; index < length; index++)
      data.getUint16(index * 2, Endian.little),
  ]);
}

bool _bytesEqual(Uint8List bytes, int offset, Uint8List expected) {
  if (offset < 0 || offset + expected.length > bytes.length) return false;
  for (var index = 0; index < expected.length; index++) {
    if (bytes[offset + index] != expected[index]) return false;
  }
  return true;
}

CardTemplate decodeSwtTemplate(Uint8List bytes) {
  try {
    final decoded = jsonDecode(utf8.decode(bytes));
    final envelope = Map<String, dynamic>.from(decoded as Map);
    final value = envelope['template'] ?? envelope;
    final template = CardTemplate.fromJson(
      Map<String, dynamic>.from(value as Map),
    );
    return CardTemplate(
      id: template.id,
      name: template.name,
      iconId: template.iconId,
      colorId: template.colorId,
      fields: template.fields,
      embeddedIconBase64: template.embeddedIconBase64,
      iconFileName: template.iconFileName,
      spbColor: template.spbColor,
      categoryPath: template.categoryPath,
    );
  } catch (_) {
    return decodeLegacySpbSwtTemplate(bytes);
  }
}

Uint8List encodeSwtTemplate(CardTemplate template) {
  final payload = const JsonEncoder.withIndent('  ').convert({
    'format': 'WalletAPS.SWT',
    'version': 1,
    'template': template.toJson(),
  });
  return Uint8List.fromList(utf8.encode(payload));
}

CardTemplate decodeLegacySpbSwtTemplate(Uint8List bytes) {
  const signature = 'serialization::archive';
  if (bytes.length < 80 ||
      _uint32(bytes, 0) != signature.length ||
      ascii.decode(bytes.sublist(4, 4 + signature.length)) != signature) {
    throw const FormatException('Неподдерживаемый формат SWT.');
  }

  Uint8List? templateId;
  String? templateName;
  var fieldsStart = 0;
  for (var offset = 30; offset + 20 < min(bytes.length, 180); offset++) {
    if (_uint32(bytes, offset) != 8) continue;
    final nameLength = _uint32(bytes, offset + 12);
    if (nameLength < 1 || nameLength > 200) continue;
    final nameEnd = offset + 16 + nameLength * 2;
    if (nameEnd > bytes.length) continue;
    final candidate = _utf16(bytes, offset + 16, nameLength).trim();
    if (candidate.isEmpty || candidate.contains('\u0000')) continue;
    templateId = Uint8List.fromList(bytes.sublist(offset + 4, offset + 12));
    templateName = candidate;
    fieldsStart = nameEnd;
    break;
  }
  if (templateId == null || templateName == null) {
    throw const FormatException('В SWT не найден шаблон.');
  }

  final fieldsByPriority = <int, FieldDefinition>{};
  for (var offset = fieldsStart; offset + 36 <= bytes.length; offset++) {
    if (_uint32(bytes, offset) != 8) continue;
    final nameLength = _uint32(bytes, offset + 12);
    if (nameLength < 1 || nameLength > 200) continue;
    final nameOffset = offset + 16;
    final templateLengthOffset = nameOffset + nameLength * 2;
    if (templateLengthOffset + 24 > bytes.length ||
        _uint32(bytes, templateLengthOffset) != 8 ||
        !_bytesEqual(bytes, templateLengthOffset + 4, templateId)) {
      continue;
    }
    final fieldTypeId = _uint32(bytes, templateLengthOffset + 12);
    final priority = _uint32(bytes, templateLengthOffset + 16);
    if (fieldTypeId < 1 || fieldTypeId > 8 || priority > 500) continue;
    final name = _utf16(bytes, nameOffset, nameLength).trim();
    if (name.isEmpty || name.contains('\u0000')) continue;
    final fieldId = bytes
        .sublist(offset + 4, offset + 12)
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();
    final type = spbFieldTypeToUi(fieldTypeId, name);
    fieldsByPriority.putIfAbsent(
      priority,
      () => FieldDefinition(
        id: fieldId,
        label: name,
        type: type,
        secret: fieldTypeIsSecret(type),
      ),
    );
  }
  final priorities = fieldsByPriority.keys.toList()..sort();
  final fields = [
    for (final priority in priorities) fieldsByPriority[priority]!,
  ];
  if (fields.isEmpty) {
    throw const FormatException('В SWT не найдены поля шаблона.');
  }
  return CardTemplate(
    id: makeId('tpl'),
    name: templateName,
    iconId: defaultIconForTemplateName(
      templateName,
      fields.map((field) => field.label),
    ),
    colorId: 'neutral',
    fields: fields,
  );
}
