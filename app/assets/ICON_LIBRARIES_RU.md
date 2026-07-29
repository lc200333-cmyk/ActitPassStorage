# Встроенные библиотеки иконок

- `spb_icons.bundle` — единый пакет штатных иконок SPB Wallet.
- `third_party/icons_unique_visual_studio.zip` — единый пакет сторонних иконок
  Visual Studio для раздела «Сторонние».

Оба файла подключены в `pubspec.yaml` как ресурсы приложения и включаются в
сборки Windows, Android и Linux. Размещать распакованные изображения в Android
`mipmap-*` не требуется.

Контрольные суммы SHA-256:

- `spb_icons.bundle`:
  `8DCA9812B16FF8D2319909502C29AD6092C671AA1712BA5CAAC83D2C489744E9`
- `icons_unique_visual_studio.zip`:
  `91211BAAD77F079D1574BED88E264611295BADBFC2B0AEC673F751C919E7999A`
