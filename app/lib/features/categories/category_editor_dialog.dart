part of '../../main.dart';

class CategoryEditorDialog extends StatefulWidget {
  const CategoryEditorDialog({
    required this.editing,
    required this.initialName,
    required this.initialIconId,
    this.initialColorId = 'template_gray',
    super.key,
  });

  final bool editing;
  final String initialName;
  final String initialIconId;
  final String initialColorId;

  @override
  State<CategoryEditorDialog> createState() => _CategoryEditorDialogState();
}

class _CategoryEditorDialogState extends State<CategoryEditorDialog> {
  late final TextEditingController name;
  late String iconId;
  late String colorId;
  bool invalidName = false;

  @override
  void initState() {
    super.initState();
    name = TextEditingController(text: widget.initialName);
    iconId = widget.initialIconId;
    colorId = widget.initialColorId;
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  void save() {
    final value = name.text.trim();
    if (value.isEmpty || value.contains('/')) {
      setState(() => invalidName = true);
      return;
    }
    Navigator.pop(context, (name: value, iconId: iconId, colorId: colorId));
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final media = mediaQuery.size;
    // Keyboard avoidance is owned by the dialog route. Keep the editor surface
    // stable and let its scroll view reveal the focused control.
    final availableHeight = media.height;
    final fullScreen = Platform.isAndroid || media.width < 700;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.zero,
      child: Align(
        alignment: Alignment.center,
        child: Material(
          color: const Color(0xfff4f4f4),
          elevation: 24,
          clipBehavior: Clip.antiAlias,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.zero,
            side: BorderSide(color: Color(0xff7f8d98)),
          ),
          child: SizedBox(
            key: const Key('categoryEditorSurface'),
            width: fullScreen ? media.width : min(media.width - 24, 720),
            height: fullScreen
                ? availableHeight
                : min(max(0.0, availableHeight - 24), 620),
            child: Column(
              children: [
                Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xffa9c9e3), Color(0xffe9f1f8)],
                    ),
                    border: Border(
                      bottom: BorderSide(color: Color(0xff7f8d98)),
                    ),
                  ),
                  child: TextField(
                    key: const Key('categoryNameField'),
                    controller: name,
                    autofocus: true,
                    onChanged: (_) {
                      setState(() => invalidName = false);
                    },
                    onSubmitted: (_) => save(),
                    style: const TextStyle(fontSize: 18),
                    decoration: InputDecoration(
                      hintText: widget.editing
                          ? 'Название папки'
                          : 'Введите имя папки',
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                Expanded(
                  child: ColoredBox(
                    color: colorById(colorId).bg,
                    child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                        14,
                        14,
                        14,
                        18 + MediaQuery.viewInsetsOf(context).bottom,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Container(
                                key: const Key('categoryBoundIcon'),
                                width: 112,
                                height: 112,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  border: Border.all(
                                    color: const Color(0xff82929d),
                                    width: 2,
                                  ),
                                  borderRadius: BorderRadius.circular(5),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x26000000),
                                      offset: Offset(1, 2),
                                      blurRadius: 5,
                                    ),
                                  ],
                                ),
                                child: templateIconWidget(
                                  iconId.isEmpty ? 'folder' : iconId,
                                  size: 88,
                                  color: templatePictogramColor(colorId),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    const Text(
                                      'Выбрать иконку',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 7),
                                    LayoutBuilder(
                                      builder: (context, constraints) {
                                        final buttons = [
                                          SpbGrayPickerButton(
                                            key: const Key(
                                              'spbFolderIconPicker',
                                            ),
                                            label: 'SPB',
                                            icon: Icons.photo_library_outlined,
                                            tooltip: 'Иконки из базы SPB',
                                            onTap: pickSpbIcon,
                                          ),
                                          SpbGrayPickerButton(
                                            key: const Key(
                                              'categoryPictogramPicker',
                                            ),
                                            label: 'пиктограммы',
                                            icon: Icons.category_outlined,
                                            tooltip: 'Выбрать пиктограмму',
                                            onTap: pickPictogram,
                                          ),
                                          SpbGrayPickerButton(
                                            key: const Key(
                                              'categoryThirdPartyPicker',
                                            ),
                                            label: 'сторонние',
                                            icon: Icons.public_outlined,
                                            tooltip: 'Иконки Visual Studio',
                                            onTap: pickThirdPartyIcon,
                                          ),
                                          SpbGrayPickerButton(
                                            key: const Key(
                                              'categoryUploadIconButton',
                                            ),
                                            label: 'загрузить иконку',
                                            icon: Icons.upload_file_outlined,
                                            tooltip:
                                                'Загрузить файл PNG или ICO',
                                            onTap: pickCustomIconFile,
                                          ),
                                        ];
                                        if (constraints.maxWidth >= 420) {
                                          return Row(
                                            children: [
                                              for (var index = 0;
                                                  index < buttons.length;
                                                  index++) ...[
                                                if (index > 0)
                                                  const SizedBox(width: 7),
                                                Expanded(child: buttons[index]),
                                              ],
                                            ],
                                          );
                                        }
                                        final width =
                                            (constraints.maxWidth - 7) / 2;
                                        return Wrap(
                                          spacing: 7,
                                          runSpacing: 7,
                                          children: [
                                            for (final button in buttons)
                                              SizedBox(
                                                width: width,
                                                child: button,
                                              ),
                                          ],
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          ColorPicker(
                            value: colorId,
                            label: 'Цвет папки',
                            keyPrefix: 'categoryColor',
                            onChanged: (value) =>
                                setState(() => colorId = value),
                          ),
                          if (invalidName) ...[
                            const SizedBox(height: 12),
                            const Text(
                              'Введите название папки без символа «/».',
                              style: TextStyle(color: Color(0xffa90000)),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                Container(
                  height: 64,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: const BoxDecoration(
                    color: Color(0xffdce8f1),
                    border: Border(top: BorderSide(color: Color(0xff7f8d98))),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (widget.editing) ...[
                        SpbGradientActionButton(
                          key: const Key('categoryDeleteButton'),
                          icon: Icons.delete_outline,
                          tooltip: 'Удалить папку',
                          colors: const [Color(0xffffdc58), Color(0xffc58a00)],
                          onTap: () => Navigator.pop(context, (
                            name: '__delete__',
                            iconId: iconId,
                            colorId: colorId,
                          )),
                        ),
                        const SizedBox(width: 6),
                      ],
                      if (widget.editing || name.text.trim().isNotEmpty) ...[
                        SpbGradientActionButton(
                          key: const Key('categorySaveButton'),
                          icon: Icons.check,
                          tooltip: 'Сохранить папку',
                          colors: const [Color(0xff5bc96d), Color(0xff08772f)],
                          onTap: save,
                        ),
                        const SizedBox(width: 6),
                      ],
                      SpbGradientActionButton(
                        key: const Key('categoryCloseButton'),
                        icon: Icons.close,
                        tooltip: 'Закрыть без сохранения',
                        colors: const [Color(0xffff5a5f), Color(0xffa90000)],
                        onTap: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> pickSpbIcon() async {
    final picked = await showSpbOriginalIconPickerDialog(context, iconId);
    if (picked != null && mounted) setState(() => iconId = picked);
  }

  Future<void> pickPictogram() async {
    final picked = await showIconPickerDialog(context, iconId);
    if (picked != null && mounted) setState(() => iconId = picked);
  }

  Future<void> pickThirdPartyIcon() async {
    final picked = await showThirdPartyIconPickerDialog(context);
    if (picked == null || !mounted) return;
    final bytes = thirdPartyIconPngs[picked];
    if (bytes == null) return;
    setState(() => iconId = registerEmbeddedIcon(bytes));
  }

  Future<void> pickCustomIconFile() async {
    final picked = await pickUserIconFile(context);
    if (picked == null || !mounted) return;
    setState(() => iconId = registerEmbeddedIcon(picked.bytes));
  }
}
