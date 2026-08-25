// Stable data-layer entry point. The implementation remains in its original
// location so existing integrations keep working while main.dart is split up.
export '../spb_wallet/spb_wallet_database.dart';

import 'dart:typed_data';

import '../spb_wallet/spb_wallet_database.dart';

abstract interface class WalletCatalogRepository {
  SpbWalletSnapshot loadCatalog();
  SpbWalletCardDetails loadCardDetails(String cardId);
  List<SpbWalletAttachmentRecord> loadAttachments(String cardId);
  Uint8List loadAttachmentBytes(String attachmentId);
  String? loadBackground(String cardId);
  Map<String, Map<String, String>> loadSearchableValues();
}

class SpbWalletCatalogRepository implements WalletCatalogRepository {
  const SpbWalletCatalogRepository(this.database);

  final SpbWalletDatabase database;

  @override
  SpbWalletSnapshot loadCatalog() => database.loadCatalog();

  @override
  SpbWalletCardDetails loadCardDetails(String cardId) =>
      database.loadCardDetails(cardId);

  @override
  List<SpbWalletAttachmentRecord> loadAttachments(String cardId) =>
      database.loadAttachments(cardId);

  @override
  Uint8List loadAttachmentBytes(String attachmentId) =>
      database.readAttachmentBytes(attachmentId);

  @override
  String? loadBackground(String cardId) =>
      database.loadCardBackgroundBase64(cardId);

  @override
  Map<String, Map<String, String>> loadSearchableValues() =>
      database.loadSearchableValues();
}
