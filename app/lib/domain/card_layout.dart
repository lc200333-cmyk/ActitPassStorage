import 'dart:convert';

class CardLayoutState {
  const CardLayoutState({
    this.fieldOrder = const [],
    this.hiddenFieldIds = const {},
    this.modifiedAt,
  });

  final List<String> fieldOrder;
  final Set<String> hiddenFieldIds;
  final DateTime? modifiedAt;

  String encodeLayout() => jsonEncode({
        'order': fieldOrder,
        'hidden': hiddenFieldIds.toList()..sort(),
      });

  static CardLayoutState decodeLayout(String value, CardLayoutState previous) {
    try {
      final decoded = Map<String, dynamic>.from(jsonDecode(value) as Map);
      return CardLayoutState(
        fieldOrder: List<String>.from(decoded['order'] as List? ?? const []),
        hiddenFieldIds:
            Set<String>.from(decoded['hidden'] as List? ?? const []),
        modifiedAt: previous.modifiedAt,
      );
    } catch (_) {
      return previous;
    }
  }
}
