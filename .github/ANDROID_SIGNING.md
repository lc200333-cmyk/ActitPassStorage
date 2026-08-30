# Постоянная подпись Android

Release APK Wallet APS никогда не подписывается debug-ключом. Для job `android`
в GitHub Actions должны быть заданы следующие repository secrets:

- `ANDROID_KEYSTORE_BASE64` — release keystore целиком в Base64 без переносов;
- `ANDROID_KEY_ALIAS` — alias ключа;
- `ANDROID_KEY_PASSWORD` — пароль ключа;
- `ANDROID_STORE_PASSWORD` — пароль keystore;
- `ANDROID_CERT_SHA256` — SHA-256 сертификата (двоеточия необязательны).

Пример подготовки значений локально:

```bash
base64 -w 0 wallet-aps-release.jks
keytool -list -v -keystore wallet-aps-release.jks -alias wallet-aps
```

Keystore нельзя добавлять в Git. Workflow восстанавливает его только на время
сборки, сверяет сертификат с `ANDROID_CERT_SHA256` и удаляет файл в шаге с
`if: always()`.

`applicationId` намеренно остаётся прежним: Android связывает обновление с
пакетом и сертификатом. Сертификат должен совпадать с сертификатом ранее
выпущенного APK. Если прежний закрытый ключ утрачен или старый релиз был
подписан другим ключом, Android по правилам платформы не позволит обновить его
поверх установленной версии. Проверка обновления в Release Actions специально
завершит job ошибкой в такой ситуации, чтобы не публиковать несовместимый APK.
