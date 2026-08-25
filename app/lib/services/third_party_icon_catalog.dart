import 'package:archive/archive.dart';
import 'package:flutter/services.dart';

class ThirdPartyIconArchive {
  const ThirdPartyIconArchive({
    required this.assetName,
    this.requiredPathPrefix,
    this.catalogPrefix = '',
  });

  final String assetName;
  final String? requiredPathPrefix;
  final String catalogPrefix;
}

/// Indexed, on-demand access to the bundled third-party icon archives.
///
/// [ZipDecoder] retains compressed entry streams. Individual PNG files are
/// decompressed only when [loadIcon] is called and remain cached afterwards.
class ThirdPartyIconCatalog {
  ThirdPartyIconCatalog({
    required List<ThirdPartyIconArchive> archives,
    AssetBundle? bundle,
  })  : _archives = List.unmodifiable(archives),
        _bundle = bundle ?? rootBundle;

  final List<ThirdPartyIconArchive> _archives;
  final AssetBundle _bundle;
  final Map<String, ArchiveFile> _entries = {};
  final Map<String, Uint8List> _cache = {};
  final Map<String, Future<Uint8List?>> _pending = {};
  Future<List<String>>? _indexFuture;

  Map<String, Uint8List> get cachedIcons => _cache;

  Future<List<String>> loadIndex() {
    return _indexFuture ??= _buildIndex();
  }

  Future<List<String>> _buildIndex() async {
    for (final source in _archives) {
      final data = await _bundle.load(source.assetName);
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      final archive = ZipDecoder().decodeBytes(bytes);
      for (final file in archive.files) {
        if (!file.isFile) continue;
        final path = file.name.replaceAll('\\', '/');
        if (!path.toLowerCase().endsWith('.png')) continue;
        final requiredPrefix = source.requiredPathPrefix;
        if (requiredPrefix != null && !path.startsWith(requiredPrefix)) {
          continue;
        }
        _entries['third-party://${source.catalogPrefix}$path'] = file;
      }
    }
    final result = _entries.keys.toList(growable: false)
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return result;
  }

  Future<Uint8List?> loadIcon(String iconId) async {
    await loadIndex();
    final cached = _cache[iconId];
    if (cached != null) return cached;
    final pending = _pending[iconId];
    if (pending != null) return pending;
    final operation = Future<Uint8List?>.sync(() {
      final bytes = _entries[iconId]?.readBytes();
      if (bytes != null) _cache[iconId] = bytes;
      return bytes;
    });
    _pending[iconId] = operation;
    try {
      return await operation;
    } finally {
      _pending.remove(iconId);
    }
  }
}
