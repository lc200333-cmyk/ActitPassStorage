import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as image;

import '../spb_wallet/spb_wallet_database.dart';

class BenchmarkFixtureResult {
  const BenchmarkFixtureResult({
    required this.path,
    required this.password,
    required this.cardCount,
    required this.templateCount,
    required this.folderCount,
  });

  final String path;
  final String password;
  final int cardCount;
  final int templateCount;
  final int folderCount;
}

class BenchmarkFixtureFactory {
  const BenchmarkFixtureFactory();

  static const password = 'wallet-aps-performance';

  BenchmarkFixtureResult create({
    required String path,
    int cardCount = 1000,
    int templateCount = 10,
    int folderCount = 30,
  }) {
    final file = File(path);
    if (file.existsSync()) file.deleteSync();
    final database = SpbWalletDatabase.create(path, password);
    final templates = <({String id, List<String> fields})>[];
    try {
      for (var templateIndex = 0;
          templateIndex < templateCount;
          templateIndex++) {
        final templateId = SpbWalletDatabase.makeId();
        final fields = List.generate(5, (_) => SpbWalletDatabase.makeId());
        final iconBytes = _iconPng(templateIndex);
        database.saveTemplate(
          SpbWalletTemplateDraft(
            id: templateId,
            name: 'Тестовый шаблон ${templateIndex + 1}',
            fields: [
              for (var fieldIndex = 0; fieldIndex < fields.length; fieldIndex++)
                SpbWalletTemplateFieldRecord(
                  id: fields[fieldIndex],
                  name: 'Поле ${fieldIndex + 1}',
                  templateId: templateId,
                  fieldTypeId: fieldIndex == 2 ? 6 : 1,
                ),
            ],
            iconId: SpbWalletDatabase.makeId(),
            iconBytes: iconBytes,
            iconFileName: 'benchmark-$templateIndex.png',
            cardColor: 0xffe8f0f7 + templateIndex,
          ),
        );
        templates.add((id: templateId, fields: fields));
      }

      for (var cardIndex = 0; cardIndex < cardCount; cardIndex++) {
        final template = templates[cardIndex % templates.length];
        final cardId = SpbWalletDatabase.makeId();
        final folder = cardIndex % folderCount;
        database.saveCard(
          SpbWalletCardDraft(
            id: cardId,
            title: 'Карточка ${cardIndex.toString().padLeft(4, '0')}',
            description:
                'Заметка производительности для карточки $cardIndex\nВторая строка заметки.',
            categoryPath:
                'Тест / Раздел ${(folder ~/ 10) + 1} / Папка ${folder + 1}',
            templateId: template.id,
            fieldValues: {
              template.fields[0]: 'Пользователь $cardIndex',
              template.fields[1]: 'Пароль-$cardIndex-Performance',
              template.fields[2]: 'https://example.com/card/$cardIndex',
              template.fields[3]: 'user$cardIndex@example.com',
              template.fields[4]: 'Дополнительные данные $cardIndex',
            },
            modifiedAt: DateTime.utc(2026, 1, 1).add(
              Duration(minutes: cardIndex),
            ),
          ),
        );
        if (cardIndex % 100 == 0) {
          final attachmentSize = cardIndex.isEven ? 1024 : 32 * 1024;
          database.saveAttachment(
            cardId: cardId,
            fileName: 'attachment-$cardIndex.bin',
            bytes: Uint8List.fromList(
              List.generate(attachmentSize, (index) => index % 251),
            ),
          );
        }
      }
      database.flushToDisk();
    } finally {
      database.close();
    }
    return BenchmarkFixtureResult(
      path: path,
      password: password,
      cardCount: cardCount,
      templateCount: templateCount,
      folderCount: folderCount,
    );
  }

  Uint8List _iconPng(int seed) {
    final icon = image.Image(width: 128, height: 128, numChannels: 4);
    final red = 60 + (seed * 17) % 160;
    final green = 80 + (seed * 23) % 140;
    final blue = 100 + (seed * 31) % 120;
    image.fill(icon, color: image.ColorRgba8(red, green, blue, 255));
    image.fillCircle(
      icon,
      x: 64,
      y: 64,
      radius: 34,
      color: image.ColorRgba8(255, 255, 255, 220),
    );
    return Uint8List.fromList(image.encodePng(icon));
  }
}
