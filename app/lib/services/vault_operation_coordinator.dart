import 'dart:async';

enum VaultOperationState { idle, saving, locked, failed, closed }

/// Serializes lifecycle and persistence operations for an opened vault.
///
/// Revisions are monotonic. A save only publishes the revision captured when
/// it starts, so a mutation arriving while publication is in progress remains
/// dirty and is never acknowledged by the older save.
class VaultOperationCoordinator {
  Future<void> _tail = Future<void>.value();
  int _dirtyRevision = 0;
  int _publishedRevision = 0;
  VaultOperationState _state = VaultOperationState.idle;
  Object? _lastError;

  int get dirtyRevision => _dirtyRevision;
  int get publishedRevision => _publishedRevision;
  bool get isDirty => _dirtyRevision > _publishedRevision;
  VaultOperationState get state => _state;
  Object? get lastError => _lastError;

  int markDirty() {
    _ensureOpen();
    return ++_dirtyRevision;
  }

  void reset({bool keepRevision = false}) {
    if (!keepRevision) {
      _dirtyRevision = 0;
      _publishedRevision = 0;
    } else {
      _publishedRevision = _dirtyRevision;
    }
    _lastError = null;
    _state = VaultOperationState.idle;
  }

  Future<T> runExclusive<T>(FutureOr<T> Function() operation) {
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<T> mutate<T>(FutureOr<T> Function() operation) {
    return runExclusive(() async {
      _ensureOpen();
      final value = await operation();
      markDirty();
      return value;
    });
  }

  Future<bool> save(
    Future<void> Function(int revision) publish, {
    bool force = false,
  }) {
    return runExclusive(() async {
      _ensureOpen();
      return _saveNow(publish, force: force);
    });
  }

  Future<bool> lock({Future<void> Function(int revision)? publish}) {
    return runExclusive(() async {
      _ensureOpen();
      if (publish != null && isDirty && !await _saveNow(publish)) return false;
      _lastError = null;
      _state = VaultOperationState.locked;
      return true;
    });
  }

  Future<bool> close({Future<void> Function(int revision)? publish}) {
    return runExclusive(() async {
      _ensureOpen();
      if (publish != null && isDirty && !await _saveNow(publish)) return false;
      _lastError = null;
      _state = VaultOperationState.closed;
      return true;
    });
  }

  void reopen() {
    _dirtyRevision = 0;
    _publishedRevision = 0;
    _lastError = null;
    _state = VaultOperationState.idle;
  }

  void dispose() {
    _state = VaultOperationState.closed;
  }

  void _ensureOpen() {
    if (_state == VaultOperationState.closed) {
      throw StateError('Vault operation coordinator is closed.');
    }
  }

  Future<bool> _saveNow(
    Future<void> Function(int revision) publish, {
    bool force = false,
  }) async {
    if (!force && !isDirty) return true;
    final revision = _dirtyRevision;
    _state = VaultOperationState.saving;
    try {
      await publish(revision);
      if (revision > _publishedRevision) _publishedRevision = revision;
      _lastError = null;
      _state = VaultOperationState.idle;
      return true;
    } catch (error) {
      _lastError = error;
      _state = VaultOperationState.failed;
      return false;
    }
  }
}
