# Wallet APS Product Specification

## 1. Product Goal

Wallet APS is a modern cross-platform secure wallet for passwords, private notes, payment data, identity records, license keys, server credentials, and user-defined card types. The product should feel like a modern successor to SPB Wallet: local-first, fast, reliable offline, and simple enough for non-technical users, while still supporting advanced synchronization options.

The application must run on Linux, Windows, macOS, Android, and iOS from one shared product model. Every device stores its own encrypted local copy of the vault. Synchronization is optional and works when network access is available.

## 2. Target Users

- A personal user who needs a private password and notes manager across phone and desktop.
- A technical user who wants to keep the vault under their control using email or self-hosted storage.
- A family or small-team user who may later need shared vaults, but shared vaults are not part of the MVP.

## 3. MVP Scope

The MVP must include:

- Creation and opening of an encrypted local vault.
- One master password for all user vault databases.
- Configurable cards based on templates.
- Built-in templates for passwords, secure notes, payment cards, identity documents, software licenses, servers, and bank accounts.
- User-created templates with configurable fields.
- Secret fields that are hidden by default and can be revealed temporarily.
- Card colors selected from a moderated palette.
- Search by title, category, tags, template, and non-secret metadata.
- Local change log for all write operations.
- Synchronization engine with conflict logging.
- Email-based sync through IMAP/SMTP.
- File-based sync through WebDAV, SFTP, FTP/FTPS, and mounted folders.
- User-visible conflict log.
- Last-write-wins conflict resolution.
- Modern quiet UI with restrained colors.
- Auto-lock on timeout and when the app goes to background.

## 4. Post-MVP Scope

The following features are intentionally outside the first release:

- Browser extensions.
- Automatic browser autofill.
- Shared vaults with multi-user permissions.
- Enterprise administration.
- Cloud service operated by the project.
- Full native SMB/NFS clients. SMB and NFS are supported through mounted-folder sync in the MVP.
- Password breach monitoring through third-party APIs.

## 5. Core User Scenarios

### 5.1 First Launch

1. User launches the app.
2. App offers to create a new vault or open an existing vault.
3. User creates a vault and sets a master password.
4. App creates a local encrypted database and default templates.
5. User enters the main card list.

### 5.2 Add Password Card

1. User taps add.
2. User selects the Password template.
3. User fills title, login, password, URL, notes, tags, and optional color.
4. Secret fields are hidden after saving.
5. A create change is written to the local change log.

### 5.3 Create Custom Template

1. User opens template editor.
2. User creates a template name, icon, color policy, and ordered fields.
3. User selects field types and marks fields as required, searchable, secret, or multiline.
4. App validates that field identifiers are stable and unique.
5. New template becomes available in the add-card flow.

### 5.4 Offline Work

1. User edits cards without network.
2. Changes are saved locally and written to the change log.
3. App marks sync as pending.
4. When network returns, app runs sync automatically or on user request.

### 5.5 Sync Conflict

1. Device A and Device B edit the same card while offline.
2. Both later synchronize with the same remote sync channel.
3. Sync engine detects concurrent changes.
4. The card value with the later `modified_at` wins.
5. A conflict record is written with item id, field changes, winning revision, losing revision, device ids, timestamps, and sync provider.
6. User can review the conflict log later.

## 6. Security Requirements

- The master password is never stored in plaintext.
- Vault data is unreadable without the master password.
- Sensitive payload fields are encrypted before being persisted.
- Cryptographic authentication must detect tampering.
- Key derivation must use Argon2id with per-vault salt.
- Encryption should use XChaCha20-Poly1305 by default, or AES-256-GCM if platform constraints require it.
- Sync payloads must be encrypted independently from the transport.
- Email and storage providers must never receive plaintext card data.
- The app must lock after a configurable idle timeout.
- The app must lock when moved to background, unless the user explicitly enables a short grace period.
- Clipboard copies of secret values must be auto-cleared after a configurable timeout where the platform allows it.
- Logs must not contain secrets.

## 7. Data Ownership and Recovery

- The user owns the vault file and remote sync files/messages.
- The product must not require a vendor account.
- If the user loses the master password, the vault cannot be recovered.
- Recovery codes are not part of MVP unless implemented as an encrypted export protected by the same security model.

## 8. UX Requirements

- Design style: modern, calm, non-flashy, high contrast, and easy to scan.
- Use a restrained palette with neutral backgrounds and moderated accent colors.
- Cards may have user-selected colors, but only from an approved palette to avoid unreadable combinations.
- Secret values are hidden by default and revealed via explicit action.
- Revealed secrets should be easy to hide again.
- The main list must support fast search and filtering.
- Sync status must be visible but not noisy.
- Conflicts must be understandable to a non-technical user.
- Dangerous actions must require confirmation.

## 9. Acceptance Criteria

- A user can create a vault, close the app, reopen the vault with the correct password, and fail to open it with an incorrect password.
- A user can create cards from built-in and custom templates.
- A user can edit and delete cards.
- Password fields are hidden by default.
- The vault file does not contain plaintext secret values.
- Two devices can synchronize through at least one MVP provider.
- Conflicts are resolved by last-write-wins and logged.
- The app runs at least on Linux and Android before expanding to all target platforms.
