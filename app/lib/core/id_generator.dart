import 'dart:math';

String makeId(String prefix) {
  final random = Random.secure();
  final suffix = List.generate(
    12,
    (_) => random.nextInt(16).toRadixString(16),
  ).join();
  return '${prefix}_$suffix';
}
