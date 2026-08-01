Map<String, String> buildCategoryPathsById<T>(
  Iterable<T> categories, {
  required String Function(T category) idOf,
  required String Function(T category) parentIdOf,
  required String Function(T category) nameOf,
}) {
  final byId = {for (final category in categories) idOf(category): category};
  final result = <String, String>{};
  for (final category in categories) {
    final names = <String>[];
    var current = category;
    final visited = <String>{};
    while (visited.add(idOf(current))) {
      final name = nameOf(current).trim();
      if (name.isNotEmpty) names.add(name);
      final parent = byId[parentIdOf(current)];
      if (parent == null) break;
      current = parent;
    }
    result[idOf(category)] = names.reversed.join(' / ');
  }
  return result;
}
