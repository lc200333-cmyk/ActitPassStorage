import 'dart:io';

import 'package:wallet_aps/spb_wallet/spb_wallet_database.dart';

void main(List<String> arguments) {
  if (arguments.length != 1) {
    stderr.writeln('Usage: dart run tool/create_manual_demo.dart <output.swl>');
    exitCode = 64;
    return;
  }

  final output = File(arguments.single);
  output.parent.createSync(recursive: true);
  if (output.existsSync()) {
    output.deleteSync();
  }

  const password = '2468';
  final wallet = SpbWalletDatabase.create(output.path, password);
  try {
    final passwordTemplateId = SpbWalletDatabase.makeId();
    final loginFieldId = SpbWalletDatabase.makeId();
    final passwordFieldId = SpbWalletDatabase.makeId();
    final urlFieldId = SpbWalletDatabase.makeId();
    wallet.saveTemplate(
      SpbWalletTemplateDraft(
        id: passwordTemplateId,
        name: 'Пароль',
        iconId: '62767D3E1BC8E2C8',
        fields: [
          SpbWalletTemplateFieldRecord(
            id: loginFieldId,
            name: 'Логин',
            templateId: passwordTemplateId,
          ),
          SpbWalletTemplateFieldRecord(
            id: passwordFieldId,
            name: 'Пароль',
            templateId: passwordTemplateId,
            fieldTypeId: 4,
          ),
          SpbWalletTemplateFieldRecord(
            id: urlFieldId,
            name: 'Сайт',
            templateId: passwordTemplateId,
            fieldTypeId: 6,
          ),
        ],
      ),
    );

    final bankTemplateId = SpbWalletDatabase.makeId();
    final cardNumberFieldId = SpbWalletDatabase.makeId();
    final validUntilFieldId = SpbWalletDatabase.makeId();
    final pinFieldId = SpbWalletDatabase.makeId();
    wallet.saveTemplate(
      SpbWalletTemplateDraft(
        id: bankTemplateId,
        name: 'Банковская карта',
        iconId: '54320B4412A08007',
        fields: [
          SpbWalletTemplateFieldRecord(
            id: cardNumberFieldId,
            name: 'Номер карты',
            templateId: bankTemplateId,
          ),
          SpbWalletTemplateFieldRecord(
            id: validUntilFieldId,
            name: 'Срок действия',
            templateId: bankTemplateId,
          ),
          SpbWalletTemplateFieldRecord(
            id: pinFieldId,
            name: 'PIN-код',
            templateId: bankTemplateId,
            fieldTypeId: 4,
          ),
        ],
      ),
    );

    final noteTemplateId = SpbWalletDatabase.makeId();
    final subjectFieldId = SpbWalletDatabase.makeId();
    wallet.saveTemplate(
      SpbWalletTemplateDraft(
        id: noteTemplateId,
        name: 'Защищённая заметка',
        iconId: '4863F2D4E9D399F6',
        fields: [
          SpbWalletTemplateFieldRecord(
            id: subjectFieldId,
            name: 'Тема',
            templateId: noteTemplateId,
          ),
        ],
      ),
    );

    wallet.saveCard(
      SpbWalletCardDraft(
        id: SpbWalletDatabase.makeId(),
        title: 'Почта',
        description: 'Демонстрационная запись для руководства.',
        categoryPath: 'Личное / Учётные записи',
        templateId: passwordTemplateId,
        fieldValues: {
          loginFieldId: 'user@example.com',
          passwordFieldId: 'Demo-Password-2026',
          urlFieldId: 'https://example.com',
        },
      ),
    );
    wallet.saveCard(
      SpbWalletCardDraft(
        id: SpbWalletDatabase.makeId(),
        title: 'Рабочий портал',
        description: 'Пример карточки без настоящих данных.',
        categoryPath: 'Работа',
        templateId: passwordTemplateId,
        fieldValues: {
          loginFieldId: 'demo.user',
          passwordFieldId: 'Sample-Only-123',
          urlFieldId: 'https://portal.example.com',
        },
      ),
    );
    wallet.saveCard(
      SpbWalletCardDraft(
        id: SpbWalletDatabase.makeId(),
        title: 'Основная карта',
        description: 'Номер и PIN приведены только для иллюстрации.',
        categoryPath: 'Финансы',
        templateId: bankTemplateId,
        fieldValues: {
          cardNumberFieldId: '0000 1111 2222 3333',
          validUntilFieldId: '12/30',
          pinFieldId: '0000',
        },
      ),
    );
    wallet.saveCard(
      SpbWalletCardDraft(
        id: SpbWalletDatabase.makeId(),
        title: 'Коды восстановления',
        description: 'Храните резервные коды в защищённой базе.',
        categoryPath: 'Личное',
        templateId: noteTemplateId,
        fieldValues: {subjectFieldId: 'Резервный доступ'},
      ),
    );
  } finally {
    wallet.close();
  }

  stdout.writeln(output.path);
  stdout.writeln('Password: $password');
}
