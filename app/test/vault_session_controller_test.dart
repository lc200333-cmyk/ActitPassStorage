import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_aps/controllers/vault_session_controller.dart';

void main() {
  testWidgets('activity restarts the locked and unlocked timers',
      (tester) async {
    final controller = VaultSessionController(
      inactivityWarningAfter: const Duration(milliseconds: 30),
      lockedExitAfter: const Duration(milliseconds: 30),
    );
    addTearDown(controller.dispose);
    var warnings = 0;
    var exits = 0;

    controller.ensureInactivityTimer(() => warnings++);
    controller.ensureInactivityTimer(() => warnings++);
    await tester.pump(const Duration(milliseconds: 20));
    controller.recordUserActivity(() => warnings++);
    await tester.pump(const Duration(milliseconds: 20));
    expect(warnings, 0);
    await tester.pump(const Duration(milliseconds: 15));
    expect(warnings, 1);

    controller.ensureLockedExitTimer(() => exits++);
    await tester.pump(const Duration(milliseconds: 20));
    controller.recordLockedUserActivity(() => exits++);
    await tester.pump(const Duration(milliseconds: 20));
    expect(exits, 0);
    await tester.pump(const Duration(milliseconds: 15));
    expect(exits, 1);
  });

  testWidgets('inactivity warning counts down and closes only once',
      (tester) async {
    var now = DateTime.utc(2026);
    final controller = VaultSessionController(
      inactivityLockAfter: const Duration(seconds: 3),
      countdownTick: const Duration(milliseconds: 10),
      clock: () => now,
    );
    addTearDown(controller.dispose);
    controller.markActivity();
    now = now.add(const Duration(seconds: 1));

    expect(controller.beginInactivityWarning(), isTrue);
    expect(controller.inactivityWarningVisible, isTrue);
    expect(controller.inactivitySecondsRemaining, 2);
    var ticks = 0;
    var expirations = 0;
    controller.startInactivityCountdown(
      onTick: () => ticks++,
      onExpired: () => expirations++,
    );
    await tester.pump(const Duration(milliseconds: 10));
    expect(controller.inactivitySecondsRemaining, 1);
    await tester.pump(const Duration(milliseconds: 10));
    expect(ticks, 2);
    expect(expirations, 1);

    controller.finishInactivityWarning();
    expect(controller.inactivityWarningVisible, isFalse);
    expect(controller.beginClosingForInactivity(), isTrue);
    expect(controller.beginClosingForInactivity(), isFalse);
    controller.finishClosingForInactivity();
    expect(controller.closingForInactivity, isFalse);
  });

  testWidgets('locked warning countdown is owned and cancelled by session',
      (tester) async {
    final controller = VaultSessionController(
      lockedExitCountdownMaximum: 2,
      countdownTick: const Duration(milliseconds: 10),
    );
    addTearDown(controller.dispose);

    expect(controller.beginLockedExitWarning(), isTrue);
    expect(controller.beginLockedExitWarning(), isFalse);
    var expired = false;
    controller.startLockedExitCountdown(
      onTick: () {},
      onExpired: () => expired = true,
    );
    await tester.pump(const Duration(milliseconds: 20));
    expect(expired, isTrue);
    expect(controller.lockedExitSecondsRemaining, 0);
    controller.finishLockedExitWarning();
    expect(controller.lockedExitWarningVisible, isFalse);
  });
}
