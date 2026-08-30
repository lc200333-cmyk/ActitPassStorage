import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

class VaultSnapshot {
  const VaultSnapshot({
    required this.path,
    required this.revision,
    required this.length,
    required this.sha256,
    required this.quickCheck,
  });

  final String path;
  final int revision;
  final int length;
  final String sha256;
  final String quickCheck;

  bool get isValid => quickCheck.toLowerCase() == 'ok';

  Future<void> dispose() async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}

class VaultPublishResult {
  const VaultPublishResult({
    required this.length,
    required this.sha256,
    this.etag,
    this.recoveryPath,
  });

  final int length;
  final String sha256;
  final String? etag;
  final String? recoveryPath;
}

abstract interface class VaultPublisher {
  Future<VaultPublishResult> publish(VaultSnapshot snapshot);
}

class VaultPersistenceException implements Exception {
  const VaultPersistenceException(this.message);

  final String message;

  @override
  String toString() => message;
}

Future<String> sha256File(File file) async {
  final digest = await sha256.bind(file.openRead()).first;
  return digest.toString();
}

/// Recoverable desktop publisher. The source database must not be open at the
/// destination path while this operation runs (notably on Windows).
class LocalFileVaultPublisher implements VaultPublisher {
  LocalFileVaultPublisher(
    this.destinationPath, {
    this.expectedExistingLength,
    this.expectedExistingSha256,
  });

  final String destinationPath;
  final int? expectedExistingLength;
  final String? expectedExistingSha256;

  @override
  Future<VaultPublishResult> publish(VaultSnapshot snapshot) async {
    if (!snapshot.isValid) {
      throw VaultPersistenceException(
        'SQLite quick_check failed: ${snapshot.quickCheck}',
      );
    }
    final destination = File(destinationPath);
    await destination.parent.create(recursive: true);
    final staged = File('$destinationPath.walletaps.tmp');
    final backup = File('$destinationPath.walletaps.backup');
    final manifest = File('$destinationPath.walletaps.recovery.json');
    if (await manifest.exists()) {
      throw const VaultPersistenceException(
        'A previous local wallet recovery is still pending.',
      );
    }
    var destinationMoved = false;
    try {
      await _verifyExpectedDestination(destination);
      await File(snapshot.path).copy(staged.path);
      await _verifyFile(staged, snapshot.length, snapshot.sha256);
      int? previousLength;
      String? previousHash;
      if (await destination.exists()) {
        previousLength = await destination.length();
        previousHash = await sha256File(destination);
      }
      await manifest.writeAsString(
        jsonEncode({
          'destinationPath': destination.path,
          'stagedPath': staged.path,
          'backupPath': backup.path,
          'previousLength': previousLength,
          'previousSha256': previousHash,
          'expectedLength': snapshot.length,
          'expectedSha256': snapshot.sha256,
        }),
        flush: true,
      );
      if (await destination.exists()) {
        await destination.rename(backup.path);
        destinationMoved = true;
      }
      await staged.rename(destination.path);
      await _verifyFile(destination, snapshot.length, snapshot.sha256);
      if (await backup.exists()) await backup.delete();
      if (await manifest.exists()) await manifest.delete();
      return VaultPublishResult(
        length: snapshot.length,
        sha256: snapshot.sha256,
      );
    } catch (_) {
      if (destinationMoved && await backup.exists()) {
        if (await destination.exists()) await destination.delete();
        await backup.rename(destination.path);
      }
      if (await manifest.exists()) await manifest.delete();
      rethrow;
    } finally {
      if (await staged.exists()) await staged.delete();
    }
  }

  Future<void> _verifyExpectedDestination(File destination) async {
    final expectedLength = expectedExistingLength;
    final expectedHash = expectedExistingSha256;
    if (expectedLength == null && expectedHash == null) return;
    if (!await destination.exists()) {
      throw const VaultPersistenceException(
        'The destination wallet was removed outside Wallet APS.',
      );
    }
    if (expectedLength != null &&
        await destination.length() != expectedLength) {
      throw const VaultPersistenceException(
        'The destination wallet was changed outside Wallet APS.',
      );
    }
    if (expectedHash != null && await sha256File(destination) != expectedHash) {
      throw const VaultPersistenceException(
        'The destination wallet was changed outside Wallet APS.',
      );
    }
  }

  static Future<LocalVaultRecovery?> pendingRecovery(
    String destinationPath,
  ) async {
    final manifest = File('$destinationPath.walletaps.recovery.json');
    if (!await manifest.exists()) return null;
    try {
      final data = jsonDecode(await manifest.readAsString());
      if (data is! Map) throw const FormatException('Invalid recovery map.');
      return LocalVaultRecovery._(
        manifestPath: manifest.path,
        destinationPath: data['destinationPath']?.toString() ?? destinationPath,
        stagedPath:
            data['stagedPath']?.toString() ?? '$destinationPath.walletaps.tmp',
        backupPath: data['backupPath']?.toString() ??
            '$destinationPath.walletaps.backup',
        previousLength: data['previousLength'] as int?,
        previousSha256: data['previousSha256']?.toString(),
        expectedLength: data['expectedLength'] as int,
        expectedSha256: data['expectedSha256'].toString(),
      );
    } catch (error) {
      throw VaultPersistenceException(
          'Invalid local recovery manifest: $error');
    }
  }
}

class LocalVaultRecovery {
  const LocalVaultRecovery._({
    required this.manifestPath,
    required this.destinationPath,
    required this.stagedPath,
    required this.backupPath,
    required this.previousLength,
    required this.previousSha256,
    required this.expectedLength,
    required this.expectedSha256,
  });

  final String manifestPath;
  final String destinationPath;
  final String stagedPath;
  final String backupPath;
  final int? previousLength;
  final String? previousSha256;
  final int expectedLength;
  final String expectedSha256;

  bool get canRestorePrevious =>
      previousLength != null &&
      previousSha256 != null &&
      (File(backupPath).existsSync() || File(destinationPath).existsSync());

  Future<void> restorePrevious() async {
    final backup = File(backupPath);
    final destination = File(destinationPath);
    final length = previousLength;
    final hash = previousSha256;
    if (length == null || hash == null) {
      throw const VaultPersistenceException(
        'The previous local wallet backup is unavailable.',
      );
    }
    if (!await backup.exists()) {
      await _verifyFile(destination, length, hash);
      await _clearMetadata();
      return;
    }
    await _verifyFile(backup, length, hash);
    if (await destination.exists()) await destination.delete();
    await backup.rename(destination.path);
    await _verifyFile(destination, length, hash);
    await _clearMetadata();
  }

  Future<void> keepPublished() async {
    final destination = File(destinationPath);
    await _verifyFile(destination, expectedLength, expectedSha256);
    final backup = File(backupPath);
    if (await backup.exists()) await backup.delete();
    await _clearMetadata();
  }

  Future<void> _clearMetadata() async {
    final staged = File(stagedPath);
    if (await staged.exists()) await staged.delete();
    final manifest = File(manifestPath);
    if (await manifest.exists()) await manifest.delete();
  }
}

class WebDavVaultPublisher implements VaultPublisher {
  WebDavVaultPublisher({
    required this.destination,
    required this.username,
    required this.password,
    this.expectedEtag,
  });

  final Uri destination;
  final String username;
  final String password;
  final String? expectedEtag;

  @override
  Future<VaultPublishResult> publish(VaultSnapshot snapshot) async {
    if (!snapshot.isValid) {
      throw VaultPersistenceException(
        'SQLite quick_check failed: ${snapshot.quickCheck}',
      );
    }
    final temporary = destination.replace(
      path:
          '${destination.path}.walletaps-${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    final client = HttpClient();
    var moved = false;
    try {
      final put = await client.putUrl(temporary);
      _authorize(put);
      put.headers.contentType = ContentType.binary;
      put.contentLength = snapshot.length;
      await put.addStream(File(snapshot.path).openRead());
      final putResponse = await put.close();
      if (putResponse.statusCode < 200 || putResponse.statusCode >= 300) {
        await putResponse.drain<void>();
        throw VaultPersistenceException(
          'WebDAV temporary PUT returned HTTP ${putResponse.statusCode}.',
        );
      }
      await putResponse.drain<void>();

      final move = await client.openUrl('MOVE', temporary);
      _authorize(move);
      move.headers.set('Destination', destination.toString());
      move.headers.set('Overwrite', 'T');
      final etag = expectedEtag;
      if (etag != null && etag.isNotEmpty) {
        move.headers.set(HttpHeaders.ifMatchHeader, etag);
      }
      final moveResponse = await move.close();
      if (moveResponse.statusCode == HttpStatus.preconditionFailed ||
          moveResponse.statusCode == HttpStatus.conflict) {
        await moveResponse.drain<void>();
        throw const VaultPersistenceException(
          'WebDAV file changed remotely; publication was not applied.',
        );
      }
      if (moveResponse.statusCode < 200 || moveResponse.statusCode >= 300) {
        await moveResponse.drain<void>();
        throw VaultPersistenceException(
          'WebDAV MOVE returned HTTP ${moveResponse.statusCode}.',
        );
      }
      moved = true;
      var publishedEtag = moveResponse.headers.value(HttpHeaders.etagHeader);
      await moveResponse.drain<void>();
      publishedEtag ??= await _readEtag(client, destination);
      return VaultPublishResult(
        length: snapshot.length,
        sha256: snapshot.sha256,
        etag: publishedEtag,
      );
    } catch (_) {
      if (!moved) await _deleteTemporary(client, temporary);
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  void _authorize(HttpClientRequest request) {
    if (username.isEmpty && password.isEmpty) return;
    request.headers.set(
      HttpHeaders.authorizationHeader,
      'Basic ${base64Encode(utf8.encode('$username:$password'))}',
    );
  }

  Future<String?> _readEtag(HttpClient client, Uri uri) async {
    final request = await client.headUrl(uri);
    _authorize(request);
    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await response.drain<void>();
      return null;
    }
    final etag = response.headers.value(HttpHeaders.etagHeader);
    await response.drain<void>();
    return etag;
  }

  Future<void> _deleteTemporary(HttpClient client, Uri uri) async {
    try {
      final request = await client.deleteUrl(uri);
      _authorize(request);
      final response = await request.close();
      await response.drain<void>();
    } catch (_) {
      // Best effort only. A failed publication must preserve the original
      // WebDAV error instead of replacing it with temporary-object cleanup.
    }
  }
}

Future<void> _verifyFile(
  File file,
  int expectedLength,
  String expectedHash,
) async {
  final length = await file.length();
  if (length != expectedLength) {
    throw VaultPersistenceException(
      'Published file size mismatch: expected $expectedLength, got $length.',
    );
  }
  final hash = await sha256File(file);
  if (hash != expectedHash) {
    throw const VaultPersistenceException('Published file SHA-256 mismatch.');
  }
}
