nom

# ActitPassStorage

Современный локальный менеджер секретов в духе SPB Wallet.

## Скачать

Актуальные сборки публикуются в GitHub Releases:

- [Windows setup.exe](releases/latest/download/ActitPassStorage-Setup.exe)
- [Android APK](releases/latest/download/ActitPassStorage-android.apk)
- [Linux deb amd64](releases/latest/download/ActitPassStorage-linux-amd64.deb)

Если ссылки не открываются, смотри страницу [последнего релиза](releases/latest).

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

`docker:deb` собирает пакет в Ubuntu 20.04 контейнере, чтобы избежать ошибок на старых Linux.

Собрать APK и deb подряд:

```bash
npm run docker:release
```

Эта команда собирает release APK и deb. Для быстрых повторных сборок без пересборки Docker image:

```bash
npm run docker:apk:fast
npm run docker:deb:fast
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
ActitPassStorage-Setup-<version>.exe
```

## Релизы

На каждый push в `master` workflow `.github/workflows/release.yml`:

1. увеличивает patch-версию;
2. коммитит обновленные версии с пометкой `[skip release]`;
3. создает тег `vX.Y.Z`;
4. собирает Windows setup, Android release APK и Linux deb;
5. публикует файлы в GitHub Release.

Версию можно поднять вручную:

```bash
npm run version:bump
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
