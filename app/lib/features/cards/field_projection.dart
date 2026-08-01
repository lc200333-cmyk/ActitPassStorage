List<String> projectVisibleFieldIds({
  required Iterable<String> definedIds,
  required Iterable<String> valueIds,
  required Iterable<String> preferredOrder,
  required Set<String> hiddenIds,
}) {
  final available = {...definedIds, ...valueIds};
  final result = <String>[];
  final added = <String>{};
  void add(String id) {
    if (available.contains(id) && !hiddenIds.contains(id) && added.add(id)) {
      result.add(id);
    }
  }

  preferredOrder.forEach(add);
  definedIds.forEach(add);
  valueIds.forEach(add);
  return result;
}
