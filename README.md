# ActitPassStorage

Современный локальный менеджер секретов в духе SPB Wallet.

В текущем состоянии репозитория есть:

- `plans/` - подробные планы продукта и реализации.
- `tests/` - тесты Node для сборочных скриптов и Docker-окружения.
- `app/` - Flutter-приложение для production-сборок.
- `core/` - Rust workspace с доменными типами vault/sync и FFI-точкой входа.

## Проверка

```bash
npm test
```

## Docker-сборки APK/deb/setup.exe

Основной способ сборки APK и deb не требует установки Flutter, Android SDK или Rust на хост: нужен только Docker и `docker-compose`.

Подробная инструкция: [docs/builds.md](docs/builds.md).

Собрать Docker-образ с окружением:

```bash
npm run docker:build-image
```

Собрать Android APK:

```bash
npm run docker:apk
```

Собрать Linux deb:

```bash
npm run docker:deb

sudo apt install --reinstall ./dist/actit-pass-storage_0.1.0_amd64.deb
```

`docker:deb` собирает пакет в Ubuntu 20.04 контейнере, чтобы избежать ошибки `GLIBC_2.34 not found` на старых Linux.

Собрать APK и deb подряд:

```bash
npm run docker:release
```

Проверить проект внутри контейнера:

```bash
npm run docker:test
```

Все результаты складываются в `dist/`, которая подключена в контейнер как volume:

```text
dist/ActitPassStorage-android-debug.apk
dist/actit-pass-storage_0.1.0_amd64.deb
```

Контейнерное окружение описано в:

```text
docker/build-env/Dockerfile
docker/linux-deb/Dockerfile
docker-compose.yml
```

Windows `setup.exe` собирается на Windows runner через GitHub Actions, потому что Flutter Windows desktop требует Windows SDK/MSVC и не кросс-собирается в Linux Docker:

```text
.github/workflows/windows_setup.yml
```

Ожидаемый артефакт workflow:

```text
ActitPassStorage-Setup-0.1.0.exe
```

## Локальные сборки без Docker

Проверить наличие локальных инструментов:

```bash
npm run check:release-tools
```

Android APK:

```bash
npm run build:apk
```

Ожидаемый артефакт:

```text
dist/ActitPassStorage-android-debug.apk
```

Linux deb:

```bash
npm run build:deb
```

Ожидаемый артефакт:

```text
dist/actit-pass-storage_0.1.0_amd64.deb
```

Важно: Flutter Windows desktop собирается на Windows-хосте. На Linux-хосте локально собираются APK и deb после установки Flutter, Android SDK, Rust и Linux desktop dependencies.

## Целевая промышленная версия

Промышленная цель - Flutter + Rust:

- Flutter UI в `app/`.
- Rust ядро vault/sync в `core/`.
- `flutter_rust_bridge` как мост между приложением и ядром.
