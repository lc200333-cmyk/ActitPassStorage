# Wallet APS performance baseline

Контрольный коммит: `1bf4596`.

Основной сценарий использует автоматически созданную базу с 1000 карточек,
10 шаблонов и 30 папок. Файл базы и результаты измерений создаются только в
`build/performance/` и не добавляются в Git.

## Команды

```powershell
cd app
dart run tool/performance_benchmark.dart
flutter build windows --profile
..\tools\measure_windows_performance.ps1
```

```bash
cd app
flutter build apk --profile
cd ..
tools/measure_android_performance.sh
```

Перед сравнением фиксируются версия ОС, устройство/процессор, объём памяти,
режим сборки и размеры APK, EXE, Setup и DEB. Результат оптимизации не должен
ухудшать ключевую метрику более чем на 10% относительно измерения на том же
устройстве.
