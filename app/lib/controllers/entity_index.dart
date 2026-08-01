Map<String, T> indexEntitiesById<T>(
  Iterable<T> entities,
  String Function(T entity) idOf,
) =>
    {for (final entity in entities) idOf(entity): entity};
