part of '../../main.dart';

class CardFieldValuesList extends StatefulWidget {
  const CardFieldValuesList({
    required this.fields,
    required this.item,
    required this.foreground,
    required this.revealed,
    required this.onToggle,
    super.key,
  });

  final List<FieldDefinition> fields;
  final SecretItem item;
  final Color foreground;
  final Set<String> revealed;
  final void Function(String revealKey, bool isRevealed) onToggle;

  @override
  State<CardFieldValuesList> createState() => _CardFieldValuesListState();
}

class _CardFieldValuesListState extends State<CardFieldValuesList> {
  final ScrollController controller = ScrollController();

  @override
  void didUpdateWidget(covariant CardFieldValuesList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id == widget.item.id) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && controller.hasClients) controller.jumpTo(0);
    });
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final populatedFields = widget.fields
        .where(
          (field) =>
              field.id != spbDescriptionFieldId &&
              (widget.item.values[field.id] ?? '').isNotEmpty,
        )
        .toList();
    return Scrollbar(
      key: const Key('cardFieldsScrollbar'),
      controller: controller,
      thumbVisibility: true,
      child: ListView(
        controller: controller,
        padding: const EdgeInsets.only(right: 10),
        children: [
          for (final field in populatedFields)
            Builder(
              key: ValueKey('${widget.item.id}:${field.id}'),
              builder: (context) {
                final revealKey = '${widget.item.id}:${field.id}';
                final isRevealed = widget.revealed.contains(revealKey);
                final value = widget.item.values[field.id]!;
                final secret = fieldDefinitionIsSecret(field);
                return FieldValueRow(
                  label: field.label,
                  value: fieldDisplayValue(field, value, revealed: isRevealed),
                  copyValue: value,
                  foreground: widget.foreground,
                  secret: secret,
                  revealed: isRevealed,
                  onToggle: secret
                      ? () => widget.onToggle(revealKey, isRevealed)
                      : null,
                );
              },
            ),
        ],
      ),
    );
  }
}

class FieldValueRow extends StatefulWidget {
  const FieldValueRow({
    required this.label,
    required this.value,
    required this.copyValue,
    required this.foreground,
    this.secret = false,
    this.revealed = false,
    this.onToggle,
    super.key,
  });

  final String label;
  final String value;
  final String copyValue;
  final Color foreground;
  final bool secret;
  final bool revealed;
  final VoidCallback? onToggle;

  @override
  State<FieldValueRow> createState() => _FieldValueRowState();
}

class _FieldValueRowState extends State<FieldValueRow> {
  Timer? copiedTimer;
  bool copied = false;

  @override
  void dispose() {
    copiedTimer?.cancel();
    super.dispose();
  }

  Future<void> copyValue() async {
    await copyCardFieldValue(widget.copyValue);
    if (!mounted) return;
    copiedTimer?.cancel();
    setState(() => copied = true);
    copiedTimer = Timer(const Duration(seconds: 10), () {
      if (mounted) setState(() => copied = false);
    });
  }

  Future<void> showCopyMenu(LongPressStartDetails details) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final picked = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(
          details.globalPosition.dx,
          details.globalPosition.dy,
          1,
          1,
        ),
        Offset.zero & overlay.size,
      ),
      items: const [
        PopupMenuItem(
          value: 'copy',
          child: ListTile(
            dense: true,
            leading: Icon(Icons.copy),
            title: Text('Копировать'),
          ),
        ),
      ],
    );
    if (picked == 'copy') await copyValue();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: copyValue,
        onLongPressStart: showCopyMenu,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.44),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: widget.foreground.withValues(alpha: 0.10),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: widget.foreground.withValues(alpha: 0.62),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 180),
                      child: SingleChildScrollView(
                        primary: false,
                        child: Text(
                          widget.value,
                          style: TextStyle(
                            color: widget.foreground,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: copied ? 'Скопировано' : 'Копировать',
                icon: Icon(copied ? Icons.check : Icons.copy),
                onPressed: copyValue,
              ),
              if (widget.secret && widget.onToggle != null)
                IconButton(
                  tooltip: widget.revealed ? 'Скрыть' : 'Показать',
                  icon: Icon(
                    widget.revealed ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: widget.onToggle,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
