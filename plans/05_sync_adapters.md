# Sync Adapters Plan

## 1. Goal

Provide synchronization transports that exchange encrypted sync packages without changing core merge behavior. Providers are adapters around the same sync engine.

## 2. Provider Interface

Each provider implements:

```text
connect(config)
list_remote_packages(cursor)
download_package(remote_id)
upload_package(package)
commit(cursor)
disconnect()
```

Provider code must not decrypt vault payloads. It only moves encrypted packages.

## 3. Sync Package Format

Each package contains:

- Package id.
- Vault id.
- Device id.
- Created timestamp.
- Sequence number.
- Encrypted change records.
- Integrity hash.
- Format version.

Package names must be deterministic enough for sorting and unique enough for concurrent devices.

## 4. Email Sync

Use IMAP/SMTP:

- SMTP uploads sync packages as email attachments or structured message bodies.
- IMAP downloads unread or labeled sync messages.
- Messages should include a recognizable subject prefix such as `Wallet APS Sync`.
- Payload remains encrypted.
- App stores provider cursor to avoid reprocessing old messages.

Configuration:

- Email address.
- IMAP host, port, security mode.
- SMTP host, port, security mode.
- Login.
- Password or app password.
- Folder/label.

OAuth support is post-MVP unless required by a target provider.

## 5. WebDAV

Use WebDAV as a first-class file sync provider:

- Remote directory contains package files and optional cursor metadata.
- Use atomic upload strategy where supported: upload temp file, then rename.
- Handle network interruption and retry.

Configuration:

- Server URL.
- Username.
- Password/token.
- Remote path.
- TLS verification mode.

## 6. SFTP

Use SFTP for self-hosted and NAS scenarios:

- Remote directory contains package files.
- Support password authentication in MVP.
- SSH key auth is recommended post-MVP if not included early.

Configuration:

- Host, port.
- Username.
- Password or key path.
- Remote path.

## 7. FTP/FTPS

Support FTP/FTPS for compatibility:

- Prefer FTPS over plain FTP.
- Show a security warning for plain FTP because payload is encrypted but metadata and credentials may be exposed.

Configuration:

- Host, port.
- Username.
- Password.
- Remote path.
- Security mode: FTP, explicit FTPS, implicit FTPS.

## 8. Mounted Folder Provider

Use this provider for:

- Local directories.
- USB drives.
- Cloud folders managed by another client.
- SMB shares mounted by the operating system.
- NFS mounts.

The adapter reads and writes package files in a selected directory. It should use file locks or atomic temp-file rename where possible.

## 9. Credential Storage

Provider credentials must not be stored in plaintext in the vault database. Store them through platform secure storage where available. If secure storage is unavailable, prompt the user or store encrypted using the vault key with clear UI warnings.

## 10. Tests

- Provider contract test with mounted-folder adapter.
- Upload/download package roundtrip.
- Duplicate remote packages do not duplicate local changes.
- Interrupted upload does not create a corrupt committed package.
- Plain FTP warning is shown in UI plan and provider metadata.

## 11. Acceptance Criteria

- Sync engine can run against a mounted-folder provider.
- Email/WebDAV/SFTP/FTP providers share one adapter interface.
- Provider credentials are handled through the platform integration layer.
