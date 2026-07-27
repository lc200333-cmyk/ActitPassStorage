import 'dart:io';

import 'package:actit_pass_storage/spb_wallet/spb_wallet_database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('missing card and folder icons use original SPB Wallet icons', () async {
    final directory = await Directory.systemTemp.createTemp(
      'actitpass_icon_fallback_',
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
}
