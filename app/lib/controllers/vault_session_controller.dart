import 'dart:async';
import 'dart:math';

/// Owns all timers and mutable state related to vault inactivity.
class VaultSessionController {
  VaultSessionController({
    this.inactivityWarningAfter = const Duration(minutes: 2, seconds: 45),
    this.inactivityLockAfter = const Duration(minutes: 3),
    this.lockedExitAfter = const Duration(minutes: 5),
    this.inactivityCountdownMaximum = 15,
    this.lockedExitCountdownMaximum = 30,
    this.countdownTick = const Duration(seconds: 1),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    lastUserActivityAt = _clock();
  }

  final Duration inactivityWarningAfter;
  final Duration inactivityLockAfter;
  final Duration lockedExitAfter;
  final int inactivityCountdownMaximum;
  final int lockedExitCountdownMaximum;
  final Duration countdownTick;
  final DateTime Function() _clock;

  Timer? _inactivityTimer;
  Timer? _inactivityCountdownTimer;
  Timer? _lockedExitTimer;
  Timer? _lockedExitCountdownTimer;

  late DateTime lastUserActivityAt;
  int inactivitySecondsRemaining = 15;
  bool inactivityWarningVisible = false;
  int lockedExitSecondsRemaining = 30;
  bool lockedExitWarningVisible = false;
  bool closingForInactivity = false;

  Duration get idleDuration => _clock().difference(lastUserActivityAt);
  bool get hasInactivityTimer => _inactivityTimer != null;
  bool get hasLockedExitTimer => _lockedExitTimer != null;

  void markActivity() => lastUserActivityAt = _clock();

  void ensureInactivityTimer(void Function() onWarning) {
    _inactivityTimer ??= Timer(inactivityWarningAfter, onWarning);
  }

  void recordUserActivity(void Function() onWarning) {
    if (closingForInactivity || inactivityWarningVisible) return;
    markActivity();
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(inactivityWarningAfter, onWarning);
  }

  void cancelInactivityTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = null;
  }

  bool beginInactivityWarning() {
    if (inactivityWarningVisible || closingForInactivity) return false;
    cancelInactivityTimer();
    inactivityWarningVisible = true;
    final remaining = inactivityLockAfter - idleDuration;
    inactivitySecondsRemaining = max(
      0,
      min(
        inactivityCountdownMaximum,
        (remaining.inMilliseconds / 1000).ceil(),
      ),
    );
    return inactivitySecondsRemaining > 0;
  }

  void startInactivityCountdown({
    required void Function() onTick,
    required void Function() onExpired,
  }) {
    _inactivityCountdownTimer?.cancel();
    _inactivityCountdownTimer = Timer.periodic(countdownTick, (_) {
      inactivitySecondsRemaining--;
      onTick();
      if (inactivitySecondsRemaining <= 0) {
        _inactivityCountdownTimer?.cancel();
        _inactivityCountdownTimer = null;
        onExpired();
      }
    });
  }

  void finishInactivityWarning() {
    _inactivityCountdownTimer?.cancel();
    _inactivityCountdownTimer = null;
    inactivityWarningVisible = false;
  }

  bool beginClosingForInactivity() {
    if (closingForInactivity) return false;
    closingForInactivity = true;
    cancelInactivityTimer();
    finishInactivityWarning();
    return true;
  }

  void finishClosingForInactivity() {
    closingForInactivity = false;
    markActivity();
  }

  void ensureLockedExitTimer(void Function() onExit) {
    _lockedExitTimer ??= Timer(lockedExitAfter, onExit);
  }

  void recordLockedUserActivity(void Function() onExit) {
    markActivity();
    _lockedExitTimer?.cancel();
    _lockedExitTimer = Timer(lockedExitAfter, onExit);
  }

  void cancelLockedExitTimer() {
    _lockedExitTimer?.cancel();
    _lockedExitTimer = null;
  }

  bool beginLockedExitWarning() {
    if (lockedExitWarningVisible) return false;
    cancelLockedExitTimer();
    lockedExitWarningVisible = true;
    lockedExitSecondsRemaining = lockedExitCountdownMaximum;
    return true;
  }

  void startLockedExitCountdown({
    required void Function() onTick,
    required void Function() onExpired,
  }) {
    _lockedExitCountdownTimer?.cancel();
    _lockedExitCountdownTimer = Timer.periodic(countdownTick, (_) {
      lockedExitSecondsRemaining--;
      onTick();
      if (lockedExitSecondsRemaining <= 0) {
        _lockedExitCountdownTimer?.cancel();
        _lockedExitCountdownTimer = null;
        onExpired();
      }
    });
  }

  void finishLockedExitWarning() {
    _lockedExitCountdownTimer?.cancel();
    _lockedExitCountdownTimer = null;
    lockedExitWarningVisible = false;
  }

  void cancelAll() {
    cancelInactivityTimer();
    finishInactivityWarning();
    cancelLockedExitTimer();
    finishLockedExitWarning();
  }

  void dispose() => cancelAll();
}
