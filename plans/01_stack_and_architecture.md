# Stack and Architecture Plan

## 1. Recommended Stack

- UI: Flutter.
- Core: Rust workspace.
- Flutter/Rust bridge: `flutter_rust_bridge`.
- Local database container: SQLite.
- Rust database access: `sqlx` or `rusqlite`; prefer `sqlx` if async sync flows dominate, otherwise `rusqlite` for simpler embedded control.
- Serialization: `serde`, `serde_json`, and versioned binary envelopes where needed.
- Cryptography:
  - Argon2id for key derivation.
  - XChaCha20-Poly1305 for authenticated encryption.
  - `rand` or OS CSPRNG for salts, nonces, and ids.
- IDs: UUID v7 or ULID for sortable object identifiers.
- Date/time: UTC timestamps only.

## 2. Repository Layout

Create a monorepo:

```text
WalletAPS/
  app/                 # Flutter application
  core/                # Rust workspace
    crates/
      vault_core/      # Domain model, crypto, storage
      sync_core/       # Change log, merge engine, sync providers
      ffi_api/         # flutter_rust_bridge public API
  plans/               # Planning documents
  .github/workflows/   # CI after scaffold
```

## 3. Layer Boundaries

### Flutter App

Flutter owns:

- Screens, routing, navigation, and UI state.
- Form validation feedback and user-facing error messages.
- Platform lifecycle events such as background/foreground.
- Calling Rust APIs for all vault operations.
- Displaying sync state and conflict logs.

Flutter must not own:

- Cryptographic implementation.
- Plain database writes for vault data.
- Merge or conflict resolution rules.
- Secret serialization format.

### Rust Core

Rust owns:

- Vault file format.
- Key derivation and encryption.
- Database schema and migrations.
- Domain types for templates, items, fields, changes, and conflicts.
- Sync state machine.
- Provider adapters.
- Conflict detection and merge policy.

## 4. Public API Shape

Rust exports a stable FFI-facing API:

```text
create_vault(path, master_password)
open_vault(path, master_password)
lock_vault()
list_items(filter, sort)
create_item(template_id, fields)
update_item(item_id, patch)
delete_item(item_id)
list_templates()
create_template(definition)
update_template(template_id, patch)
configure_sync(sync_config)
run_sync()
list_conflicts()
```

The FFI layer should expose DTOs that are friendly to Dart. Internal Rust structs may be richer, but DTO compatibility must be maintained once UI work starts.

## 5. Build Strategy

Stage 1 should only create plans.

Stage 2 should scaffold:

- Flutter app in `app/`.
- Rust workspace in `core/`.
- A minimal Rust function exposed to Flutter through `flutter_rust_bridge`.
- Build scripts documented for Linux and Android first.

Stage 3+ should add real vault behavior behind the existing API.

## 6. CI Strategy

Initial CI should run:

- Rust formatting check.
- Rust clippy.
- Rust tests.
- Flutter analyze.
- Flutter tests.

CI should start with Linux. Android, Windows, macOS, and iOS runners can be added after the app compiles locally for those platforms.

## 7. Dependency Policy

- Prefer mature, audited, actively maintained libraries for cryptography and storage.
- Avoid custom crypto primitives.
- Keep sync providers behind traits so provider dependencies do not leak into core domain code.
- Avoid platform-specific code in Rust core unless isolated behind adapters.

## 8. Acceptance Criteria

- A new contributor can identify where UI, crypto, storage, sync, and FFI code belong.
- Flutter has no direct access to unencrypted persistent vault storage.
- Rust APIs are the single write path for vault data.
- The first scaffold can compile a Flutter app calling a Rust function.
