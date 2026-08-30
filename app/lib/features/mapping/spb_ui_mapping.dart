part of '../../main.dart';

extension _SpbUiMapping on _VaultShellState {
  List<CardTemplate> spbTemplatesToUi(List<SpbWalletTemplateRecord> source) {
    return source.map((template) {
      final fields = template.fields.map((field) {
        final type = spbFieldTypeToUi(field.fieldTypeId, field.name);
        final secret = spbFieldIsSecret(field.fieldTypeId, field.name);
        return FieldDefinition(
          id: field.id,
          label: field.name.isEmpty ? 'Поле' : field.name,
          type: type,
          secret: secret,
        );
      }).toList();
      if (!fields.any((field) => field.id == spbDescriptionFieldId)) {
        fields.add(
          const FieldDefinition(
            id: spbDescriptionFieldId,
            label: 'Заметки',
            type: 'multiline_note',
          ),
        );
      }
      final iconId = spbTemplateIconForUi(template);
      rememberSpbIcon(iconId, template.iconId);
      return CardTemplate(
        id: template.id,
        name: template.name,
        iconId: iconId,
        colorId: spbTemplateColorToPaletteId(template.cardColor),
        spbColor: template.cardColor,
        categoryPath: template.categoryPath,
        fields: fields,
      );
    }).toList();
  }

  void _applySpbSnapshotImpl(SpbWalletSnapshot snapshot) {
    cardLoadFailures = List.of(snapshot.cardLoadFailures);
    walletLoadReport = snapshot.loadReport.hasIssues
        ? snapshot.loadReport
        : WalletLoadReport([
            for (final failure in cardLoadFailures)
              WalletLoadIssue(
                kind: WalletLoadIssueKind.card,
                entityId: failure.cardId,
                reason: failure.reason,
              ),
          ]);
    if (walletLoadReport.hasIssues) {
      message = walletLoadReport.issues.length == cardLoadFailures.length
          ? 'Не удалось отобразить ${cardLoadFailures.length} карточек'
          : 'Не удалось загрузить ${walletLoadReport.issues.length} элементов';
    }
    spbEmbeddedIconPngs = Map<String, Uint8List>.from(
      snapshot.embeddedIconPngs,
    );
    final loadedTemplates = spbTemplatesToUi(snapshot.templates);
    final knownTemplateIds =
        loadedTemplates.map((template) => template.id).toSet();
    final missingTemplateIds = snapshot.cards
        .map((card) => card.templateId)
        .where((id) => !knownTemplateIds.contains(id))
        .toSet();
    for (final templateId in missingTemplateIds) {
      final fieldIds = snapshot.cards
          .where((card) => card.templateId == templateId)
          .expand((card) => card.fieldValues.keys)
          .toSet()
          .toList()
        ..sort();
      loadedTemplates.add(
        CardTemplate(
          id: templateId,
          name: 'Неизвестный шаблон',
          iconId: 'key',
          colorId: 'neutral',
          fields: [
            for (var index = 0; index < fieldIds.length; index++)
              FieldDefinition(
                id: fieldIds[index],
                label: 'Сохранённое поле ${index + 1}',
                type: 'text',
              ),
            const FieldDefinition(
              id: spbDescriptionFieldId,
              label: 'Заметки',
              type: 'multiline_note',
            ),
          ],
        ),
      );
    }
    loadedTemplates.sort(
      (a, b) => compareNamedEntities(a.name, a.id, b.name, b.id),
    );
    templates = loadedTemplates;
    templatesById = indexEntitiesById(templates, (template) => template.id);
    items = spbCardsToUi(snapshot.cards)
        .where(
          (item) =>
              !sessionTrashCardIds.contains(item.id) &&
              !sessionTrashTemplateIds.contains(item.templateId) &&
              !isPathInSessionTrash(item.category),
        )
        .toList();
    templates = loadedTemplates
        .where((template) => !sessionTrashTemplateIds.contains(template.id))
        .toList();
    templatesById = indexEntitiesById(templates, (template) => template.id);
    itemsById = indexEntitiesById(items, (item) => item.id);
    categoryIconsByPath = spbCategoryIconsToUi(snapshot.categories)
      ..removeWhere((path, _) => isPathInSessionTrash(path));
    categoryColorsByPath = spbCategoryColorsToUi(snapshot.categories)
      ..removeWhere((path, _) => isPathInSessionTrash(path));
    categoryIdsByPath = spbCategoryIdsToUi(snapshot.categories)
      ..removeWhere((path, _) => isPathInSessionTrash(path));
    categoryPathsById = {
      for (final entry in categoryIdsByPath.entries) entry.value: entry.key,
    };
    navigationController.reconcileCategorySelection(
      categoryPathsById: categoryPathsById,
      categoryIdsByPath: categoryIdsByPath,
    );
    categoryPaths = spbCategoryPathsToUi(snapshot.categories)
      ..removeWhere(isPathInSessionTrash);
    final validIds = items.map((item) => item.id).toSet();
    recentlyOpenedItemIds
      ..clear()
      ..addAll(
        (spbWallet?.loadRecentlyOpenedCardIds() ?? const <String>[])
            .where(validIds.contains)
            .take(10),
      );
    refreshSpbSearchIndex();
  }

  List<SecretItem> spbCardsToUi(List<SpbWalletCardRecord> source) {
    return source.map((card) {
      final template = templateFor(card.templateId);
      final iconId = spbCardIconForUi(card.iconId, template.iconId);
      final values = spbCardValuesForUi(template, card);
      rememberSpbIcon(iconId, card.iconId);
      return SecretItem(
        id: card.id,
        templateId: card.templateId,
        title: card.title.isEmpty ? '.swl карточка' : card.title,
        category: card.categoryPath,
        colorId: spbColorToPaletteId(card.cardColor),
        iconId: iconId,
        values: values,
        attachments: card.attachments
            .map(
              (attachment) => SecretAttachment(
                id: attachment.id,
                fileName: attachment.fileName,
                size: attachment.size,
                decodeError: attachment.decodeError,
              ),
            )
            .toList(),
        modifiedAt: card.modifiedAt ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        hitCount: card.hitCount,
        backgroundImageBase64: card.backgroundImageBase64,
        spbColor: card.cardColor,
        fieldOrder: card.fieldOrder,
        hiddenFieldIds: card.hiddenFieldIds,
      );
    }).toList();
  }

  void rememberSpbIcon(String uiIconId, String spbIconId) {
    if (spbIconId.isEmpty || !isSpbHexId(spbIconId)) return;
    spbIconIdByUiIcon.putIfAbsent(uiIconId, () => spbIconId);
  }

  String? spbIconIdForUi(String uiIconId, String fallbackUiIconId) {
    if (isSpbHexId(uiIconId)) return uiIconId.toUpperCase();
    final selectedAsset = spbPngIconAsset(uiIconId);
    if (selectedAsset != null) {
      final normalizedSelectedAsset = normalizeSpbPackedIconId(selectedAsset);
      for (final entry in spbOriginalIconAssets.entries) {
        if (normalizeSpbPackedIconId(entry.value) == normalizedSelectedAsset) {
          return entry.key;
        }
      }
    }
    final direct = spbIconIdByUiIcon[uiIconId];
    if (direct != null && isSpbHexId(direct)) return direct;
    if (uiIconId == fallbackUiIconId) {
      final fallback = spbIconIdByUiIcon[fallbackUiIconId];
      if (fallback != null && isSpbHexId(fallback)) return fallback;
    }
    return syntheticSpbIconIdForUi(uiIconId);
  }

  Map<String, String> spbCategoryIconsToUi(
    List<SpbWalletCategoryRecord> categories,
  ) {
    final byId = {for (final category in categories) category.id: category};
    final result = <String, String>{};
    String pathFor(SpbWalletCategoryRecord category) {
      final names = <String>[];
      var current = category;
      var guard = 0;
      while (guard++ < 64) {
        if (current.name.isNotEmpty) names.add(current.name);
        final parent = byId[current.parentId];
        if (parent == null) break;
        current = parent;
      }
      return names.reversed.join(' / ');
    }

    for (final category in categories) {
      final path = pathFor(category);
      if (path.isEmpty) continue;
      final iconId = spbFolderIconAsset(path, category.iconId);
      rememberSpbIcon(iconId, category.iconId);
      result[path] = iconId;
    }
    return result;
  }

  Map<String, String> spbCategoryColorsToUi(
    List<SpbWalletCategoryRecord> categories,
  ) {
    final byId = {for (final category in categories) category.id: category};
    final result = <String, String>{};
    for (final category in categories) {
      if (category.colorId.isEmpty) continue;
      final names = <String>[];
      var current = category;
      var guard = 0;
      while (guard++ < 64) {
        if (current.name.isNotEmpty) names.add(current.name);
        final parent = byId[current.parentId];
        if (parent == null) break;
        current = parent;
      }
      final path = names.reversed.join(' / ');
      if (path.isNotEmpty) result[path] = category.colorId;
    }
    return result;
  }

  Map<String, String> spbCategoryIdsToUi(
    List<SpbWalletCategoryRecord> categories,
  ) {
    final pathsById = buildCategoryPathsById(
      categories,
      idOf: (category) => category.id,
      parentIdOf: (category) => category.parentId,
      nameOf: (category) => category.name,
    );
    return {
      for (final entry in pathsById.entries)
        if (entry.value.isNotEmpty) entry.value: entry.key,
    };
  }

  Set<String> spbCategoryPathsToUi(List<SpbWalletCategoryRecord> categories) {
    final byId = {for (final category in categories) category.id: category};
    final result = <String>{};
    String pathFor(SpbWalletCategoryRecord category) {
      final names = <String>[];
      var current = category;
      var guard = 0;
      while (guard++ < 64) {
        if (current.name.isNotEmpty) names.add(current.name);
        final parent = byId[current.parentId];
        if (parent == null) break;
        current = parent;
      }
      return names.reversed.join(' / ');
    }

    for (final category in categories) {
      final path = pathFor(category);
      if (path.isNotEmpty) result.add(path);
    }
    return result;
  }

  String defaultIconForCategoryPath(String path) {
    final normalized = path.toLowerCase();
    if (normalized.contains('пример') || normalized.contains('demo')) {
      if (normalized.contains('финанс')) return 'bank';
      if (normalized.contains('работ')) return 'briefcase';
      if (normalized.contains('сервис')) return 'globe';
      if (normalized.contains('документ')) return 'id';
      if (normalized.contains('доступ')) return 'key';
      return 'bookmark';
    }
    if (normalized.contains('кредит') ||
        normalized.contains('карта') ||
        normalized.contains('card')) {
      return 'card';
    }
    if (normalized.contains('личн') ||
        normalized.contains('паспорт') ||
        normalized.contains('документ') ||
        normalized.contains('personal')) {
      return normalized.contains('паспорт') || normalized.contains('документ')
          ? 'id'
          : 'contact';
    }
    if (normalized.contains('путеше') ||
        normalized.contains('ави') ||
        normalized.contains('билет') ||
        normalized.contains('travel') ||
        normalized.contains('flight')) {
      return 'plane';
    }
    if (normalized.contains('программ') ||
        normalized.contains('about') ||
        normalized.contains('spb')) {
      return 'info';
    }
    if (normalized.contains('банк') ||
        normalized.contains('финанс') ||
        normalized.contains('деньг') ||
        normalized.contains('money')) {
      return 'bank';
    }
    if (normalized.contains('почт') || normalized.contains('mail')) {
      return 'mail';
    }
    if (normalized.contains('работ') ||
        normalized.contains('проект') ||
        normalized.contains('office') ||
        normalized.contains('work')) {
      return 'briefcase';
    }
    if (normalized.contains('сервис') ||
        normalized.contains('сайт') ||
        normalized.contains('web') ||
        normalized.contains('internet')) {
      return 'globe';
    }
    if (normalized.contains('дом') || normalized.contains('home')) {
      return 'home';
    }
    if (normalized.contains('здоров') || normalized.contains('мед')) {
      return 'heart';
    }
    if (normalized.contains('сем') || normalized.contains('family')) {
      return 'family';
    }
    if (normalized.contains('покуп') || normalized.contains('shop')) {
      return 'cart';
    }
    if (normalized.contains('архив') || normalized.contains('archive')) {
      return 'snowflake';
    }
    return 'folder';
  }
}
