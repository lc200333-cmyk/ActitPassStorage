# Wallet APS performance optimization results

Control revision: `1bf4596`. Benchmark fixture: 1000 cards, 10 templates,
30 folders. Generated databases and JSON results stay under the ignored
`app/build/performance/` directory and never contain user data.

## Implemented stages

| Area | Result |
| --- | --- |
| Reproducible baseline | `BenchmarkFixtureFactory`, JSON benchmark runner, Windows/Android memory scripts |
| Images | 128x128 PNG normalization in an isolate, SHA-256 processing cache |
| Search and lists | 250 ms debounce, immediate clear/submit, lazy result and icon grids |
| Database loading | Catalog-first opening, on-demand card details and attachments, indexed queries |
| Updates | Point updates after CRUD; full snapshot retained for repair/import/tests |
| Saving | `SaveCoordinator` with dirty/saving/error states, 400 ms coalescing and explicit flush |
| Resources | Third-party ZIP files are indexed first; visible PNG entries alone are decompressed and cached |
| Architecture | Benchmarking, icon processing, persistence coordination and repository APIs extracted from `main.dart` |

The `.swl` format, encryption, package ID, method channels and stored icon IDs
were not changed.

## Measurements on this workstation

The first recorded fixture run produced a 2,052,096-byte database. Loading the
catalog took 86 ms versus 154 ms for the original full snapshot (about 44%
faster). A full snapshot through the compatibility API took 96 ms and loading
one card's details took 1.789 ms. Timings vary between runs and should be
compared using the generated JSON reports on the same hardware.

Release artifacts from the final verification:

| Artifact | Size |
| --- | ---: |
| Android release APK | 94,617,569 bytes |
| Windows `wallet_aps.exe` | 291,840 bytes |

The executable size excludes the adjacent Windows runtime and asset files.
Inno Setup is not installed on this workstation, so the Setup size remains a CI
measurement. A Linux DEB must likewise be measured by the Linux release job.

## Verification

- `flutter analyze`: no issues.
- `flutter test`: 83 passed, 8 platform-dependent tests skipped.
- Windows release build: successful.
- Android release APK build: successful.
- Third-party icon test: all 1388 stable IDs present; index loading caches zero
  decoded PNGs and requesting one icon caches exactly one.

The existing two icon archives remain intact to preserve their stable catalog.
The runtime index now provides the intended memory saving without duplicating
the 25 MB binary payload into generated Git artifacts. Physical archive
chunking can be introduced later as a packaging-only change if startup I/O
measurements show a benefit; it is not required for on-demand decompression.
