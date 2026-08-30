import 'card_models.dart';

const spbDescriptionFieldId = '__spb_description';

bool isNotesLabel(String label) {
  final normalized = label.trim().toLowerCase();
  return normalized == 'note' ||
      normalized == 'notes' ||
      normalized == 'заметка' ||
      normalized == 'заметки' ||
      normalized.contains('замет');
}

bool isRealNotesField(FieldDefinition field) {
  if (field.id == spbDescriptionFieldId) return false;
  final normalizedId = field.id.trim().toLowerCase();
  return normalizedId == 'note' ||
      normalizedId == 'notes' ||
      isNotesLabel(field.label);
}

bool fieldTypeIsSecret(String type) =>
    type == 'password' || type == 'custom_secret';

bool fieldDefinitionIsSecret(FieldDefinition field) =>
    field.secret || fieldTypeIsSecret(field.type);

bool spbFieldIsSecret(int fieldTypeId, String fieldName) {
  if (fieldTypeId == 4) return true;
  final normalized = fieldName.toLowerCase();
  return normalized.contains('password') ||
      normalized.contains('pass') ||
      normalized.contains('парол') ||
      normalized.contains('pin') ||
      normalized.contains('пин') ||
      normalized.contains('cvv') ||
      normalized.contains('код');
}

String secretFieldTypeForName(String fieldName) {
  final normalized = fieldName.trim().toLowerCase();
  if (normalized.contains('парол') ||
      normalized.contains('password') ||
      normalized.contains('pass')) {
    return 'password';
  }
  return 'custom_secret';
}

String spbFieldTypeToUi(int fieldTypeId, [String fieldName = '']) {
  if (spbFieldIsSecret(fieldTypeId, fieldName)) {
    return secretFieldTypeForName(fieldName);
  }
  switch (fieldTypeId) {
    case 2:
      return 'number';
    case 6:
      return 'url';
    case 7:
      return 'email';
    case 8:
      return 'phone';
    default:
      return 'text';
  }
}

String fieldDisplayValue(
  FieldDefinition field,
  String value, {
  required bool revealed,
}) =>
    fieldDefinitionIsSecret(field) && !revealed ? '••••••••' : value;

String noteFieldIdForTemplate(CardTemplate template) {
  for (final field in template.fields) {
    if (field.id == spbDescriptionFieldId) return spbDescriptionFieldId;
  }
  for (final field in template.fields) {
    if (isRealNotesField(field)) return field.id;
  }
  return spbDescriptionFieldId;
}

int spbFieldTypeId(FieldDefinition field) {
  if (fieldTypeIsSecret(field.type)) return 4;
  switch (field.type) {
    case 'multiline_note':
      return 1;
    case 'url':
      return 6;
    case 'email':
      return 7;
    case 'date':
      return 1;
    case 'phone':
      return 8;
    case 'number':
      return 2;
    default:
      return 1;
  }
}
