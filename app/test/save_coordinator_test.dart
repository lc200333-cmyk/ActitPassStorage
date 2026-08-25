import 'package:actit_pass_storage/services/save_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sequential dirty events are combined into one save', () async {
    var writes = 0;
    final coordinator = SaveCoordinator(
      delay: const Duration(milliseconds: 20),
      writer: ({required force}) async {
        writes++;
        return true;
      },
    );
    coordinator.markDirty();
    coordinator.markDirty();
    coordinator.markDirty();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(writes, 1);
    expect(coordinator.status, SaveStatus.idle);
    coordinator.dispose();
  });

  test('explicit flush waits for confirmation and preserves errors', () async {
    var succeeds = false;
    final coordinator = SaveCoordinator(
      writer: ({required force}) async => succeeds,
    );
    coordinator.markDirty();
    expect(await coordinator.flush(force: true), isFalse);
    expect(coordinator.status, SaveStatus.error);
    succeeds = true;
    expect(await coordinator.flush(force: true), isTrue);
    expect(coordinator.status, SaveStatus.idle);
    coordinator.dispose();
  });
}
