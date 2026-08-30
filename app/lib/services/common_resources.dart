part of '../main.dart';

final rootScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
const spbIconBundleAsset = 'assets/spb_icons.bundle';
const thirdPartyIconBundleAsset = 'assets/third_party/NewIcons.zip';
List<String> spb64PngIconAssets = [];
Future<List<String>>? spb64PngIconAssetsFuture;
Map<String, Uint8List> spbBundledIconPngs = {};
Map<String, Uint8List> spbEmbeddedIconPngs = {};
List<String> thirdPartyIconAssets = [];
Future<List<String>>? thirdPartyIconAssetsFuture;
Map<String, Uint8List> thirdPartyIconPngs = {};

Future<List<String>> loadSpb64PngIconAssets() {
  return spb64PngIconAssetsFuture ??= () async {
    final data = await rootBundle.load(spbIconBundleAsset);
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    final packedIcons = <String, Uint8List>{};
    String? pickerManifest;
    for (final file in archive.files) {
      if (!file.isFile) continue;
      final normalizedName = file.name.replaceAll('\\', '/');
      if (normalizedName == 'icons_64x64.txt') {
        pickerManifest = utf8.decode(file.content, allowMalformed: true);
      } else if (normalizedName.toLowerCase().endsWith('.png')) {
        packedIcons['spb://$normalizedName'] = Uint8List.fromList(file.content);
      }
    }
    spbBundledIconPngs = packedIcons;
    final manifest = pickerManifest ?? '';
    spb64PngIconAssets = manifest
        .split(RegExp(r'\r?\n'))
        .map((path) => normalizeSpbPackedIconId(path.trim()))
        .where(
          (path) =>
              path.toLowerCase().endsWith('.png') &&
              packedIcons.containsKey(path),
        )
        .toSet()
        .toList(growable: false);
    return spb64PngIconAssets;
  }();
}

Future<List<String>> loadThirdPartyIconAssets() {
  return thirdPartyIconAssetsFuture ??= () async {
    final data = await rootBundle.load(thirdPartyIconBundleAsset);
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    final packedIcons = <String, Uint8List>{};
    for (final file in archive.files) {
      if (!file.isFile) continue;
      final normalizedName = file.name.replaceAll('\\', '/');
      if (!normalizedName.toLowerCase().endsWith('.png')) continue;
      packedIcons['third-party://$normalizedName'] = Uint8List.fromList(
        file.content,
      );
    }
    thirdPartyIconPngs = packedIcons;
    thirdPartyIconAssets = packedIcons.keys.toList(growable: false)
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return thirdPartyIconAssets;
  }();
}

String normalizeSpbPackedIconId(String iconId) {
  var normalized = iconId.replaceAll('\\', '/');
  const legacyPrefixes = <String>[
    'assets/spb_icons_package/',
    'assets/spb_wallet_libraries/icons/',
  ];
  for (final prefix in legacyPrefixes) {
    if (normalized.startsWith(prefix)) {
      normalized = normalized.substring(prefix.length);
      break;
    }
  }
  return normalized.startsWith('spb://') ? normalized : 'spb://$normalized';
}

Uint8List? spbPackedIconBytes(String iconId) =>
    spbBundledIconPngs[normalizeSpbPackedIconId(iconId)];

Widget spbPackedImage(
  String iconId, {
  double? width,
  double? height,
  BoxFit fit = BoxFit.contain,
  FilterQuality filterQuality = FilterQuality.medium,
  Widget? fallback,
}) {
  final bytes = spbPackedIconBytes(iconId);
  if (bytes == null) return fallback ?? const SizedBox.shrink();
  return Image.memory(
    bytes,
    width: width,
    height: height,
    fit: fit,
    filterQuality: filterQuality,
    gaplessPlayback: true,
    errorBuilder: fallback == null ? null : (_, __, ___) => fallback,
  );
}

Future<void> copySensitiveText(String value) async {
  await SecureClipboardService.copy(value);
}

Future<void> copyCardFieldValue(String value) async {
  await copySensitiveText(value);
  rootScaffoldMessengerKey.currentState
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      const SnackBar(
        content: Text('Скопировано'),
        duration: Duration(milliseconds: 900),
        behavior: SnackBarBehavior.floating,
      ),
    );
}

bool get usesDesktopCardTextControls => Platform.isWindows || Platform.isLinux;

Widget desktopCardTextContextMenu(
  BuildContext context,
  EditableTextState editableTextState,
) {
  final value = editableTextState.textEditingValue;
  final selection = value.selection;
  final selectedText = selection.isValid && !selection.isCollapsed
      ? selection.textInside(value.text)
      : '';
  final defaultItems = {
    for (final item in editableTextState.contextMenuButtonItems)
      item.type: item,
  };
  final items = selectedText.isEmpty
      ? editableTextState.contextMenuButtonItems
      : <ContextMenuButtonItem>[
          ContextMenuButtonItem(
            type: ContextMenuButtonType.cut,
            label: 'Cut',
            onPressed: defaultItems[ContextMenuButtonType.cut]?.onPressed,
          ),
          ContextMenuButtonItem(
            type: ContextMenuButtonType.copy,
            label: 'Copy',
            onPressed: () async {
              editableTextState.hideToolbar();
              await copyCardFieldValue(selectedText);
            },
          ),
          ContextMenuButtonItem(
            type: ContextMenuButtonType.paste,
            label: 'Paste',
            onPressed: defaultItems[ContextMenuButtonType.paste]?.onPressed,
          ),
          ContextMenuButtonItem(
            type: ContextMenuButtonType.share,
            label: 'Share',
            onPressed: () async {
              editableTextState.hideToolbar();
              await copyCardFieldValue(selectedText);
            },
          ),
        ];
  return AdaptiveTextSelectionToolbar.buttonItems(
    anchors: editableTextState.contextMenuAnchors,
    buttonItems: items,
  );
}
