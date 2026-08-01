int compareNamedEntities(
  String firstName,
  String firstId,
  String secondName,
  String secondId,
) {
  final byName = firstName.toLowerCase().compareTo(secondName.toLowerCase());
  return byName == 0 ? firstId.compareTo(secondId) : byName;
}
