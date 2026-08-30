part of '../main.dart';

SliverGridDelegate thirdPartyIconGridDelegate({bool? isAndroid}) {
  if (isAndroid ?? Platform.isAndroid) {
    return const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 4,
      childAspectRatio: 1,
      mainAxisSpacing: 7,
      crossAxisSpacing: 7,
    );
  }
  return const SliverGridDelegateWithMaxCrossAxisExtent(
    maxCrossAxisExtent: 82,
    childAspectRatio: 1,
    mainAxisSpacing: 7,
    crossAxisSpacing: 7,
  );
}

class SpbPanel extends StatelessWidget {
  const SpbPanel({required this.title, required this.children, super.key});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: const Color(0xffb9cee4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

class IconPickerField extends StatelessWidget {
  const IconPickerField({
    required this.label,
    required this.iconId,
    required this.onChanged,
    super.key,
  });

  final String label;
  final String iconId;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final icon = iconById(iconId);
    return Row(
      children: [
        CircleAvatar(child: Icon(templateIconGlyph(icon.id), size: 20)),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () async {
              final picked = await showIconPickerDialog(context, iconId);
              if (picked != null) onChanged(picked);
            },
            icon: Icon(templateIconGlyph(icon.id), size: 18),
            label: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
        ),
      ],
    );
  }
}

class _IconPickerScrollbar extends StatefulWidget {
  const _IconPickerScrollbar({
    required this.builder,
    required this.scrollbarKey,
  });

  final Widget Function(ScrollController controller) builder;
  final Key scrollbarKey;

  @override
  State<_IconPickerScrollbar> createState() => _IconPickerScrollbarState();
}

class _IconPickerScrollbarState extends State<_IconPickerScrollbar> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      key: widget.scrollbarKey,
      controller: _controller,
      thumbVisibility: true,
      trackVisibility: true,
      interactive: true,
      child: widget.builder(_controller),
    );
  }
}

Future<String?> showIconPickerDialog(
  BuildContext context,
  String selectedIconId,
) {
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Все пиктограммы'),
      content: SizedBox(
        width: min(MediaQuery.of(context).size.width - 48, 560),
        height: min(MediaQuery.of(context).size.height - 180, 420),
        child: _IconPickerScrollbar(
          scrollbarKey: const Key('pictogramPickerScrollbar'),
          builder: (controller) => GridView.builder(
            controller: controller,
            padding: const EdgeInsets.only(right: 12),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 52,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
            ),
            itemCount: templateIcons.length,
            itemBuilder: (context, index) {
              final icon = templateIcons[index];
              final selected = icon.id == selectedIconId;
              return Tooltip(
                message: icon.label,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => Navigator.pop(context, icon.id),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: selected
                          ? Theme.of(context).colorScheme.primaryContainer
                          : Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: selected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).dividerColor,
                      ),
                    ),
                    child: Center(
                      child: Icon(templateIconGlyph(icon.id), size: 24),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
      ],
    ),
  );
}

Future<String?> showSpbOriginalIconPickerDialog(
  BuildContext context,
  String selectedIconId,
) async {
  final iconAssets = await loadSpb64PngIconAssets();
  if (!context.mounted) return null;
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Иконки SPB Wallet'),
      content: SizedBox(
        width: min(MediaQuery.of(context).size.width - 48, 620),
        height: min(MediaQuery.of(context).size.height - 180, 460),
        child: _IconPickerScrollbar(
          scrollbarKey: const Key('spbIconPickerScrollbar'),
          builder: (controller) => GridView.builder(
            controller: controller,
            padding: const EdgeInsets.only(right: 12),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 82,
              childAspectRatio: 1,
              mainAxisSpacing: 7,
              crossAxisSpacing: 7,
            ),
            itemCount: iconAssets.length,
            itemBuilder: (context, index) {
              final iconId = iconAssets[index];
              final asset = iconId;
              final selected = iconId == selectedIconId;
              final fileName =
                  iconId.startsWith('spb://') ? iconId.substring(6) : iconId;
              return Tooltip(
                message: fileName,
                child: InkWell(
                  onTap: () => Navigator.pop(context, iconId),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: selected
                          ? Theme.of(context).colorScheme.primaryContainer
                          : Theme.of(context).colorScheme.surface,
                      border: Border.all(
                        color: selected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).dividerColor,
                      ),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: spbPackedImage(
                        asset,
                        width: 56,
                        height: 56,
                        fit: BoxFit.contain,
                        fallback: const Icon(Icons.image_outlined, size: 40),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
      ],
    ),
  );
}

Future<String?> showThirdPartyIconPickerDialog(BuildContext context) async {
  final iconAssets = await loadThirdPartyIconAssets();
  if (!context.mounted) return null;
  var visible = iconAssets;
  return showDialog<String>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Сторонние иконки'),
        content: SizedBox(
          width: min(MediaQuery.of(context).size.width - 48, 660),
          height: min(MediaQuery.of(context).size.height - 180, 520),
          child: Column(
            children: [
              TextField(
                key: const Key('thirdPartyIconSearch'),
                decoration: const InputDecoration(
                  hintText: 'Поиск по имени файла',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (query) {
                  final normalized = query.trim().toLowerCase();
                  setDialogState(() {
                    visible = normalized.isEmpty
                        ? iconAssets
                        : iconAssets
                            .where(
                              (entry) =>
                                  entry.toLowerCase().contains(normalized),
                            )
                            .toList(growable: false);
                  });
                },
              ),
              const SizedBox(height: 10),
              Expanded(
                child: _IconPickerScrollbar(
                  scrollbarKey: const Key('thirdPartyIconPickerScrollbar'),
                  builder: (controller) => GridView.builder(
                    controller: controller,
                    padding: const EdgeInsets.only(right: 12),
                    gridDelegate: thirdPartyIconGridDelegate(),
                    itemCount: visible.length,
                    itemBuilder: (context, index) {
                      final iconId = visible[index];
                      final bytes = thirdPartyIconPngs[iconId];
                      final fileName = iconId.split('/').last;
                      return Tooltip(
                        message: fileName,
                        child: InkWell(
                          onTap: () => Navigator.pop(context, iconId),
                          borderRadius: BorderRadius.circular(7),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border.all(
                                color: Theme.of(context).dividerColor,
                              ),
                              borderRadius: BorderRadius.circular(7),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: bytes == null
                                  ? const Icon(Icons.broken_image_outlined)
                                  : Image.memory(
                                      bytes,
                                      width: 56,
                                      height: 56,
                                      fit: BoxFit.contain,
                                      filterQuality: FilterQuality.medium,
                                    ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
        ],
      ),
    ),
  );
}

class SpbGrayPickerButton extends StatelessWidget {
  const SpbGrayPickerButton({
    required this.label,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    super.key,
  });

  final String label;
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Opacity(
        opacity: onTap == null ? 0.48 : 1,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(5),
            child: Ink(
              height: 48,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xfff4f4f4), Color(0xff969696)],
                ),
                border: Border.all(color: const Color(0xff676767)),
                borderRadius: BorderRadius.circular(5),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.white,
                    offset: Offset(-1, -1),
                    blurRadius: 0.5,
                  ),
                  BoxShadow(
                    color: Color(0x66000000),
                    offset: Offset(1, 1),
                    blurRadius: 1,
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 18, color: const Color(0xff303030)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xff303030),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
