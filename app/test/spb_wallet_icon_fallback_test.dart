import 'dart:io';

import 'package:wallet_aps/spb_wallet/spb_wallet_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

void main() {
  test('template keeps its embedded icon and exact background color', () async {
    final directory = await Directory.systemTemp.createTemp(
      'wallet_aps_template_style_',
    );
    final path = '${directory.path}${Platform.pathSeparator}template.swl';
    final wallet = SpbWalletDatabase.create(path, 'style-password');
    final templateId = SpbWalletDatabase.makeId();
    final iconId = SpbWalletDatabase.makeId();
    final sourceIcon = image.Image(width: 16, height: 16);
    image.fill(
      sourceIcon,
      color: image.ColorRgb8(120, 180, 220),
    );
    final iconBytes = image.encodePng(sourceIcon);
    try {
      wallet.saveTemplate(
        SpbWalletTemplateDraft(
          id: templateId,
          name: 'Цветной шаблон',
          iconId: iconId,
          cardColor: 0xd8ecfa,
          iconBytes: iconBytes,
          iconFileName: 'custom.png',
          fields: const [],
        ),
      );

      final snapshot = wallet.loadSnapshot();
      final template = snapshot.templates.single;
      expect(template.iconId, iconId);
      expect(template.cardColor, 0xd8ecfa);
      expect(snapshot.embeddedIconPngs[iconId], isNotEmpty);
    } finally {
      wallet.close();
      await directory.delete(recursive: true);
    }
  });

  test('card and folder keep their embedded custom icons', () async {
    final directory = await Directory.systemTemp.createTemp(
      'wallet_aps_card_folder_icons_',
    );
    final path = '${directory.path}${Platform.pathSeparator}icons.swl';
    final wallet = SpbWalletDatabase.create(path, 'icon-password');
    final templateId = SpbWalletDatabase.makeId();
    final cardId = SpbWalletDatabase.makeId();
    final cardIconId = SpbWalletDatabase.makeId();
    final folderIconId = SpbWalletDatabase.makeId();
    final sourceIcon = image.Image(width: 16, height: 16);
    image.fill(sourceIcon, color: image.ColorRgb8(90, 150, 210));
    final iconBytes = image.encodePng(sourceIcon);
    try {
      wallet.saveTemplate(
        SpbWalletTemplateDraft(
          id: templateId,
          name: 'Шаблон',
          fields: const [],
        ),
      );
      wallet.createCategory(
        'Папка',
        folderIconId,
        iconBytes: iconBytes,
      );
      wallet.saveCard(
        SpbWalletCardDraft(
          id: cardId,
          title: 'Карточка',
          description: '',
          categoryPath: 'Папка',
          templateId: templateId,
          fieldValues: const {},
          iconId: cardIconId,
          iconBytes: iconBytes,
        ),
      );

      final snapshot = wallet.loadSnapshot();
      expect(snapshot.cards.single.iconId, cardIconId);
      expect(snapshot.categories.single.iconId, folderIconId);
      expect(snapshot.embeddedIconPngs[cardIconId], isNotEmpty);
      expect(snapshot.embeddedIconPngs[folderIconId], isNotEmpty);

      final replacementFolderIconId = SpbWalletDatabase.makeId();
      wallet.renameCategory(
        'Папка',
        'Переименованная папка',
        replacementFolderIconId,
        iconBytes: iconBytes,
      );
      final renamed = wallet.loadSnapshot();
      expect(renamed.categories.single.name, 'Переименованная папка');
      expect(renamed.categories.single.iconId, replacementFolderIconId);
      expect(
        renamed.embeddedIconPngs[replacementFolderIconId],
        isNotEmpty,
      );
    } finally {
      wallet.close();
      await directory.delete(recursive: true);
    }
  });

  test('missing card and folder icons use original SPB Wallet icons', () async {
    final directory = await Directory.systemTemp.createTemp(
      'wallet_aps_icon_fallback_',
    );
    final path = '${directory.path}${Platform.pathSeparator}icons.swl';
    final wallet = SpbWalletDatabase.create(path, 'test-password');
    try {
      final defaultTemplateId = SpbWalletDatabase.makeId();
      wallet.saveTemplate(
        SpbWalletTemplateDraft(
          id: defaultTemplateId,
          name: 'Без иконки',
          fields: const [],
        ),
      );
      wallet.saveCard(
        SpbWalletCardDraft(
          id: SpbWalletDatabase.makeId(),
          title: 'Карточка без иконки',
          description: '',
          categoryPath: 'Папка без иконки / Вложенная папка',
          templateId: defaultTemplateId,
          fieldValues: const {},
        ),
      );

      const websiteIconId = 'A6E0F0CFDFAF6928';
      final websiteTemplateId = SpbWalletDatabase.makeId();
      wallet.saveTemplate(
        SpbWalletTemplateDraft(
          id: websiteTemplateId,
          name: 'Сайт',
          iconId: websiteIconId,
          fields: const [],
        ),
      );
      wallet.saveCard(
        SpbWalletCardDraft(
          id: SpbWalletDatabase.makeId(),
          title: 'Карточка с иконкой шаблона',
          description: '',
          categoryPath: '',
          templateId: websiteTemplateId,
          fieldValues: const {},
        ),
      );

      wallet.createCategory('Созданная папка', '');

      final snapshot = wallet.loadSnapshot();
      expect(
        snapshot.cards
            .singleWhere((card) => card.title == 'Карточка без иконки')
            .iconId,
        SpbWalletDatabase.defaultCardIconId,
      );
      expect(
        snapshot.cards
            .singleWhere((card) => card.title == 'Карточка с иконкой шаблона')
            .iconId,
        websiteIconId,
      );
      expect(
        snapshot.categories.map((category) => category.iconId),
        everyElement(SpbWalletDatabase.defaultFolderIconId),
      );
    } finally {
      wallet.close();
      await directory.delete(recursive: true);
    }
  });

  test('read-only open and close preserve the database timestamp', () async {
    final directory = await Directory.systemTemp.createTemp(
      'wallet_aps_read_only_',
    );
    final file = File(
      '${directory.path}${Platform.pathSeparator}read-only.swl',
    );
    const password = 'read-only-password';
    final created = SpbWalletDatabase.create(file.path, password);
    final templateId = SpbWalletDatabase.makeId();
    created.saveTemplate(
      SpbWalletTemplateDraft(
        id: templateId,
        name: 'Read only',
        fields: const [],
      ),
    );
    created.saveCard(
      SpbWalletCardDraft(
        id: SpbWalletDatabase.makeId(),
        title: 'Viewed card',
        description: '',
        categoryPath: '',
        templateId: templateId,
        fieldValues: const {},
      ),
    );
    created.close();

    final originalTimestamp = DateTime.utc(2020, 1, 2, 3, 4, 6);
    await file.setLastModified(originalTimestamp);
    final opened = SpbWalletDatabase.open(file.path, password);
    opened.loadSnapshot();
    expect(opened.loadRecentlyOpenedCardIds(), isEmpty);
    opened.close(flush: false);

    expect(await file.lastModified(), originalTimestamp.toLocal());
    await directory.delete(recursive: true);
  });

  test('in-memory undo snapshot restores changed card data', () async {
    final directory = await Directory.systemTemp.createTemp(
      'wallet_aps_undo_snapshot_',
    );
    final path = '${directory.path}${Platform.pathSeparator}undo.swl';
    final wallet = SpbWalletDatabase.create(path, 'undo-password');
    final templateId = SpbWalletDatabase.makeId();
    final cardId = SpbWalletDatabase.makeId();
    wallet.saveTemplate(
      SpbWalletTemplateDraft(
        id: templateId,
        name: 'Undo template',
        fields: const [],
      ),
    );
    wallet.saveCard(
      SpbWalletCardDraft(
        id: cardId,
        title: 'Before',
        description: '',
        categoryPath: '',
        templateId: templateId,
        fieldValues: const {},
      ),
    );
    final undo = await wallet.createUndoSnapshot();
    try {
      wallet.saveCard(
        SpbWalletCardDraft(
          id: cardId,
          title: 'After',
          description: '',
          categoryPath: '',
          templateId: templateId,
          fieldValues: const {},
        ),
      );
      expect(wallet.loadSnapshot().cards.single.title, 'After');

      await wallet.restoreUndoSnapshot(undo);
      expect(wallet.loadSnapshot().cards.single.title, 'Before');
    } finally {
      undo.dispose();
      wallet.close();
      await directory.delete(recursive: true);
    }
  });
}
