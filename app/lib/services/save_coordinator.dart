import 'dart:async';

enum SaveStatus { idle, dirty, saving, error }

class SaveCoordinator {
  SaveCoordinator({
    required Future<bool> Function({required bool force}) writer,
    this.delay = const Duration(milliseconds: 400),
    this.onStatusChanged,
  }) : _writer = writer;

  final Future<bool> Function({required bool force}) _writer;
  final Duration delay;
  final void Function(SaveStatus status)? onStatusChanged;
  Timer? _timer;
  Future<bool>? _activeSave;
  SaveStatus _status = SaveStatus.idle;

  SaveStatus get status => _status;

  void markDirty() {
    _setStatus(SaveStatus.dirty);
    _timer?.cancel();
    _timer = Timer(delay, () => unawaited(flush()));
  }

  Future<bool> flush({bool force = false}) async {
    _timer?.cancel();
    if (!force && _status == SaveStatus.idle) return true;
    final active = _activeSave;
    if (active != null) return active;
    final operation = _save(force: force);
    _activeSave = operation;
    try {
      return await operation;
    } finally {
      _activeSave = null;
    }
  }

  Future<bool> _save({required bool force}) async {
    _setStatus(SaveStatus.saving);
    final saved = await _writer(force: force);
    _setStatus(saved ? SaveStatus.idle : SaveStatus.error);
    return saved;
  }

  void reset() {
    _timer?.cancel();
    _setStatus(SaveStatus.idle);
  }

  void dispose() {
    _timer?.cancel();
  }

  void _setStatus(SaveStatus value) {
    if (_status == value) return;
    _status = value;
    onStatusChanged?.call(value);
  }
}
