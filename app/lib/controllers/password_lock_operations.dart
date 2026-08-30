part of '../main.dart';

extension _PasswordLockOperations on _VaultShellState {
  Future<void> replaceCurrentWalletPassword({
    required String oldPassword,
    required String newPassword,
    required String passwordHint,
  }) async {
    final wallet = spbWallet;
    final path = spbWalletPath;
    if (wallet == null || path == null || path.isEmpty) {
      throw StateError('Кошелек не открыт.');
    }
    wallet.saveRecentlyOpenedCardIds(recentlyOpenedItemIds);
    wallet.flushToDisk();
    final sourceFile = File(path);
    final suffix = DateTime.now().microsecondsSinceEpoch;
    final temporaryFile = File('$path.password-change-$suffix.tmp');
    final backupFile = File('$path.password-change-$suffix.backup');
    await compute<Map<String, dynamic>, bool>(
      cloneSwlVaultWithPassword,
      <String, dynamic>{
        'path': temporaryFile.path,
        'password': newPassword,
        'sourcePassword': oldPassword,
        'passwordHint': passwordHint,
        'baseBytes': await sourceFile.readAsBytes(),
      },
    );
    final verification = SpbWalletDatabase.open(
      temporaryFile.path,
      newPassword,
    );
    verification.close(flush: false);

    clearSessionUndoHistory();
    wallet.close(flush: false);
    spbWallet = null;
    try {
      await sourceFile.rename(backupFile.path);
      await temporaryFile.rename(sourceFile.path);
      final reopened = SpbWalletDatabase.open(path, newPassword);
      final snapshot = reopened.loadSnapshot();
      spbWallet = reopened;
      vaultOperations.reopen();
      vaultDirty = false;
      _updateShellState(() => applySpbSnapshot(snapshot));
      final written = await writeBackSpbWallet(force: true);
      if (!written) {
        throw StateError('Не удалось записать базу в исходное хранилище.');
      }
      if (backupFile.existsSync()) await backupFile.delete();
    } catch (_) {
      spbWallet?.close(flush: false);
      spbWallet = null;
      if (sourceFile.existsSync()) await sourceFile.delete();
      if (backupFile.existsSync()) await backupFile.rename(sourceFile.path);
      spbWallet = SpbWalletDatabase.open(path, oldPassword);
      if (temporaryFile.existsSync()) await temporaryFile.delete();
      rethrow;
    }
  }

  Future<void> _openChangePasswordDialogImpl() async {
    final oldController = TextEditingController();
    final newController = TextEditingController();
    final repeatController = TextEditingController();
    final hintController = TextEditingController(
      text: spbWallet?.loadPasswordHint() ?? '',
    );
    var showOld = false;
    var showNew = false;
    var showRepeat = false;
    var saving = false;
    String? errorText;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final media = MediaQuery.of(context);
          final narrow = media.size.width < 600;
          return AlertDialog(
            key: const Key('changePasswordDialog'),
            scrollable: true,
            insetPadding: EdgeInsets.symmetric(
              horizontal: narrow ? 4 : 40,
              vertical: narrow ? 8 : 24,
            ),
            backgroundColor: const Color(0xffececec),
            surfaceTintColor: Colors.transparent,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            titlePadding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
            title: GestureDetector(
              key: const Key('changePasswordDialogDragHandle'),
              behavior: HitTestBehavior.opaque,
              onPanStart: (_) {
                unawaited(startLoginWindowDrag());
              },
              child: const SizedBox(
                height: 38,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Изменить пароль'),
                ),
              ),
            ),
            content: SizedBox(
              width: narrow ? double.maxFinite : 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PasswordField(
                    key: const Key('changePasswordOld'),
                    controller: oldController,
                    label: 'Старый пароль',
                    visible: showOld,
                    onToggle: () => setDialogState(() => showOld = !showOld),
                    compact: true,
                  ),
                  const SizedBox(height: 8),
                  PasswordField(
                    key: const Key('changePasswordNew'),
                    controller: newController,
                    label: 'Новый пароль',
                    visible: showNew,
                    onChanged: (_) => setDialogState(() {}),
                    onToggle: () => setDialogState(() => showNew = !showNew),
                    compact: true,
                  ),
                  const SizedBox(height: 8),
                  PasswordStrengthBar(
                    key: const Key('changePasswordStrength'),
                    password: newController.text,
                  ),
                  const SizedBox(height: 8),
                  PasswordField(
                    key: const Key('changePasswordRepeat'),
                    controller: repeatController,
                    label: 'Повторите новый пароль',
                    visible: showRepeat,
                    onToggle: () =>
                        setDialogState(() => showRepeat = !showRepeat),
                    compact: true,
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 42,
                    child: TextField(
                      key: const Key('changePasswordHint'),
                      controller: hintController,
                      decoration: const InputDecoration(
                        labelText: 'Подсказка',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                    ),
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      errorText!,
                      key: const Key('changePasswordError'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
            actions: [
              IgnorePointer(
                ignoring: saving,
                child: Opacity(
                  opacity: saving ? 0.6 : 1,
                  child: SpbGradientActionButton(
                    key: const Key('cancelChangePassword'),
                    icon: Icons.close,
                    tooltip: 'Отменить',
                    colors: const [Color(0xffff5a5f), Color(0xffa90000)],
                    onTap: () => Navigator.of(dialogContext).pop(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IgnorePointer(
                ignoring: saving,
                child: Opacity(
                  opacity: saving ? 0.6 : 1,
                  child: SpbGradientActionButton(
                    key: const Key('confirmChangePassword'),
                    icon: Icons.check,
                    tooltip: saving ? 'Сохранение…' : 'Сохранить',
                    colors: const [Color(0xff5bc96d), Color(0xff08772f)],
                    onTap: () async {
                      FocusScope.of(dialogContext).unfocus();
                      await SystemChannels.textInput.invokeMethod<void>(
                        'TextInput.hide',
                      );
                      await WidgetsBinding.instance.endOfFrame;
                      final oldPassword = oldController.text;
                      final newPassword = newController.text;
                      final repeatedPassword = repeatController.text;
                      if (oldPassword.isEmpty) {
                        setDialogState(
                          () => errorText = 'Введите старый пароль.',
                        );
                        return;
                      }
                      if (newPassword.isEmpty) {
                        setDialogState(
                            () => errorText = 'Введите новый пароль.');
                        return;
                      }
                      if (newPassword != repeatedPassword) {
                        setDialogState(
                          () => errorText = 'Новые пароли не совпадают.',
                        );
                        return;
                      }
                      setDialogState(() {
                        saving = true;
                        errorText = null;
                      });
                      try {
                        await replaceCurrentWalletPassword(
                          oldPassword: oldPassword,
                          newPassword: newPassword,
                          passwordHint: hintController.text,
                        );
                        if (dialogContext.mounted) {
                          Navigator.of(dialogContext).pop();
                        }
                        showSpbOperationMessage('Пароль кошелька изменен.');
                      } catch (_) {
                        if (dialogContext.mounted) {
                          setDialogState(() {
                            saving = false;
                            errorText =
                                'Не удалось изменить пароль. Проверьте старый пароль.';
                          });
                        }
                      }
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
    oldController.dispose();
    newController.dispose();
    repeatController.dispose();
    hintController.dispose();
  }

  String openDatabaseTitle() {
    if (spbWallet != null) {
      final path = spbWalletDisplayPath ?? spbWalletPath;
      if (path == null || path.isEmpty) return '.swl база';
      if (path.startsWith('content://')) {
        final name = vaultNameController.text.trim();
        return name.isEmpty ? '.swl база' : name;
      }
      return File(path).uri.pathSegments.isEmpty
          ? path
          : File(path).uri.pathSegments.last;
    }
    final name = vaultNameController.text.trim();
    return name.isEmpty ? 'personal' : name;
  }

  String? spbWalletUserPath() => spbWalletDisplayPath ?? spbWalletPath;

  String get selectedVaultTitle {
    final path = spbWalletDisplayPath ?? spbWalletPath;
    String withoutSwlExtension(String name) =>
        name.replaceFirst(RegExp(r'\.swl$', caseSensitive: false), '');
    if (path != null && path.isNotEmpty) {
      if (path.startsWith('content://')) {
        final name = vaultNameController.text.trim();
        return name.isEmpty ? 'база' : withoutSwlExtension(name);
      }
      return withoutSwlExtension(_vaultTitleFromPath(path));
    }
    if (recentVaults.isNotEmpty) {
      return withoutSwlExtension(recentVaults.first.title);
    }
    return 'файл не выбран';
  }

  String? get selectedVaultModifiedText {
    final path = spbWalletPath;
    if (path == null || path.isEmpty) return null;
    try {
      final file = File(path);
      if (!file.existsSync()) return null;
      final modified = file.lastModifiedSync().toLocal();
      String two(int value) => value.toString().padLeft(2, '0');
      return '${two(modified.day)}.${two(modified.month)}.'
          '${two(modified.year % 100)} ${two(modified.hour)}.'
          '${two(modified.minute)}';
    } on FileSystemException {
      return null;
    }
  }

  void insertPasswordText(String value) {
    final nextText = '${passwordController.text}$value';
    passwordController.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextText.length),
    );
    passwordFocusNode.requestFocus();
  }

  void backspacePassword() {
    final text = passwordController.text;
    if (text.isNotEmpty) {
      final nextText = text.substring(0, text.length - 1);
      passwordController.value = TextEditingValue(
        text: nextText,
        selection: TextSelection.collapsed(offset: nextText.length),
      );
    }
    passwordFocusNode.requestFocus();
  }

  void clearPassword() {
    passwordController.clear();
    passwordFocusNode.requestFocus();
  }

  void showLoginPasswordHint() {
    if (loginHintVisible) return;
    final path = spbWalletPath;
    final hint = path == null || path.isEmpty
        ? ''
        : SpbWalletDatabase.readPasswordHint(path);
    _updateShellState(() {
      loginPasswordHint = hint.trim().isEmpty ? 'Подсказка не задана.' : hint;
      loginHintVisible = true;
    });
  }

  void hideLoginPasswordHint() {
    if (!loginHintVisible) return;
    _updateShellState(() => loginHintVisible = false);
  }

  Future<void> exitApplication() async {
    sessionController.cancelLockedExitTimer();
    sessionController.finishLockedExitWarning();
    final saved = await finalizeSessionTrash();
    if (!saved) {
      showSpbOperationMessage(
        'Программа не закрыта: не удалось сохранить изменения базы.',
      );
      return;
    }
    passwordController.clear();
    confirmController.clear();
    clearSessionUndoHistory();
    await vaultOperations.close();
    spbWallet?.close(flush: false);
    spbWallet = null;
    vaultOperations.reset();
    vaultDirty = false;
    spbWalletPath = null;
    spbWalletUri = null;
    spbWalletDisplayPath = null;
    if (Platform.isAndroid || Platform.isIOS) {
      await SystemNavigator.pop();
    } else {
      exit(0);
    }
  }

  void ensureLockedExitTimer() {
    sessionController.ensureLockedExitTimer(
      () => unawaited(exitApplication()),
    );
  }

  void recordLockedUserActivity() {
    if (unlocked) return;
    sessionController.recordLockedUserActivity(
      () => unawaited(exitApplication()),
    );
  }

  void ensureInactivityTimer() {
    sessionController.ensureInactivityTimer(
      () => unawaited(showInactivityWarning()),
    );
  }

  void recordUserActivity() {
    if (!unlocked || closingForInactivity || inactivityWarningVisible) return;
    sessionController.recordUserActivity(
      () => unawaited(showInactivityWarning()),
    );
  }

  Future<void> _showInactivityWarningImpl() async {
    if (!mounted || inactivityWarningVisible || closingForInactivity) return;
    if (!sessionController.beginInactivityWarning()) {
      sessionController.finishInactivityWarning();
      await closeAfterInactivity();
      return;
    }
    StateSetter? updateDialog;
    sessionController.startInactivityCountdown(
      onTick: () => updateDialog?.call(() {}),
      onExpired: () {
        if (mounted && Navigator.of(context, rootNavigator: true).canPop()) {
          Navigator.of(context, rootNavigator: true).pop(false);
        }
      },
    );
    final continued = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          updateDialog = setDialogState;
          return Dialog(
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.zero,
              side: BorderSide(color: Color(0xff7f8d98)),
            ),
            child: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    height: 48,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xffa9c9e3), Color(0xffe9f1f8)],
                      ),
                      border: Border(
                        bottom: BorderSide(color: Color(0xff7f8d98)),
                      ),
                    ),
                    child: const Text(
                      'Предупреждение',
                      style: TextStyle(fontSize: 18),
                    ),
                  ),
                  Container(
                    width: double.infinity,
                    color: const Color(0xfff4f4f4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 24,
                    ),
                    child: Text(
                      'Хранилище будет заблокировано через '
                      '$inactivitySecondsRemaining секунд',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 20),
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
                        SpbGradientActionButton(
                          key: const Key('inactivityContinueButton'),
                          icon: Icons.play_arrow,
                          tooltip: 'Продолжить работу',
                          colors: const [Color(0xff5bc96d), Color(0xff08772f)],
                          onTap: () => Navigator.of(dialogContext).pop(true),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    sessionController.finishInactivityWarning();
    if (continued == true && mounted) {
      _updateShellState(() {
        activeView = 'cards';
        mobilePane = 0;
      });
      recordUserActivity();
    } else {
      await closeAfterInactivity();
    }
  }

  Future<void> closeAfterInactivity() async {
    if (!sessionController.beginClosingForInactivity()) return;
    final saved = await finalizeSessionTrash();
    clearSessionUndoHistory();
    if (saved) {
      await vaultOperations.lock();
      spbWallet?.close(flush: false);
      spbWallet = null;
      vaultOperations.reset();
      vaultDirty = false;
      spbWritePending = false;
    }
    passwordController.clear();
    confirmController.clear();
    revealed.clear();
    if (!mounted) {
      sessionController.finishClosingForInactivity();
      return;
    }
    Navigator.of(
      context,
      rootNavigator: true,
    ).popUntil((route) => route.isFirst);
    sessionController.finishClosingForInactivity();
    _updateShellState(() {
      unlocked = false;
      entryMode = EntryMode.openSwl;
      activeView = 'cards';
      mobilePane = 0;
      if (saved) message = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) passwordFocusNode.requestFocus();
    });
  }

  Widget passwordKey({
    required String label,
    required VoidCallback onPressed,
    Widget? child,
    Color top = const Color(0xff2483bc),
    Color bottom = const Color(0xff07436c),
    double fontSize = 34,
    FontWeight fontWeight = FontWeight.w500,
    double height = 62,
    double minimumHeight = 48,
    Key? key,
  }) {
    return Semantics(
      button: true,
      label: label,
      child: SizedBox(
        height: max(height, minimumHeight),
        child: Material(
          key: key,
          color: Colors.transparent,
          child: Ink(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [top, bottom],
              ),
              border: Border.all(color: const Color(0xff5c6870)),
              borderRadius: BorderRadius.circular(3),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  offset: Offset(0, 2),
                  blurRadius: 2,
                ),
              ],
            ),
            child: InkWell(
              onTap: onPressed,
              borderRadius: BorderRadius.circular(3),
              child: Center(
                child: child ??
                    Text(
                      label,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: fontSize,
                        height: 1,
                        fontWeight: fontWeight,
                        shadows: const [
                          Shadow(color: Colors.black45, offset: Offset(1, 1)),
                        ],
                      ),
                    ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget keypadRow(List<Widget> children) => Row(
        children: [
          for (var index = 0; index < children.length; index++) ...[
            if (index > 0) const SizedBox(width: 5),
            Expanded(child: children[index]),
          ],
        ],
      );

  void selectVirtualKeyboardMode(VirtualKeyboardMode mode) {
    _updateShellState(() => virtualKeyboardMode = mode);
    passwordFocusNode.requestFocus();
  }

  Widget buildPasswordKeyboard({
    required Color redTop,
    required Color redBottom,
  }) {
    if (virtualKeyboardMode == VirtualKeyboardMode.symbols) {
      Widget symbolKey(String symbol) => passwordKey(
            key: Key('keypadSymbol$symbol'),
            label: symbol,
            height: 42,
            minimumHeight: 42,
            fontSize: 25,
            onPressed: () => insertPasswordText(symbol),
          );

      return Column(
        children: [
          keypadRow([
            for (final symbol in [
              '+',
              '×',
              '÷',
              '=',
              '/',
              '_',
              '<',
              '>',
              '[',
              ']',
            ])
              symbolKey(symbol),
          ]),
          const SizedBox(height: 2),
          keypadRow([
            for (final symbol in [
              '!',
              '@',
              '#',
              r'$',
              '%',
              '^',
              '&',
              '*',
              '(',
              ')',
            ])
              symbolKey(symbol),
          ]),
          const SizedBox(height: 2),
          keypadRow([
            passwordKey(
              key: const Key('keypadSymbolsPage'),
              label: '1/2',
              height: 42,
              minimumHeight: 42,
              fontSize: 18,
              onPressed: passwordFocusNode.requestFocus,
            ),
            for (final symbol in ['-', "'", '"', ':', ';', ',', '?'])
              symbolKey(symbol),
            passwordKey(
              key: const Key('keypadBackspace'),
              label: '<-',
              height: 42,
              minimumHeight: 42,
              fontSize: 22,
              top: redTop,
              bottom: redBottom,
              onPressed: backspacePassword,
            ),
          ]),
        ],
      );
    }

    if (virtualKeyboardMode != VirtualKeyboardMode.numeric) {
      final uppercase = virtualKeyboardMode == VirtualKeyboardMode.uppercase;
      Widget letterKey(String baseLetter) {
        final letter = uppercase ? baseLetter : baseLetter.toLowerCase();
        return passwordKey(
          key: Key('keypadLetter$letter'),
          label: letter,
          height: 42,
          minimumHeight: 42,
          fontSize: 24,
          onPressed: () => insertPasswordText(letter),
        );
      }

      return Column(
        children: [
          keypadRow([
            for (final letter in [
              'Q',
              'W',
              'E',
              'R',
              'T',
              'Y',
              'U',
              'I',
              'O',
              'P',
            ])
              letterKey(letter),
          ]),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: keypadRow([
              for (final letter in [
                'A',
                'S',
                'D',
                'F',
                'G',
                'H',
                'J',
                'K',
                'L',
              ])
                letterKey(letter),
            ]),
          ),
          const SizedBox(height: 2),
          keypadRow([
            passwordKey(
              key: const Key('keypadClear'),
              label: 'CLR',
              height: 42,
              minimumHeight: 42,
              fontSize: 17,
              top: redTop,
              bottom: redBottom,
              onPressed: clearPassword,
            ),
            for (final letter in ['Z', 'X', 'C', 'V', 'B', 'N', 'M'])
              letterKey(letter),
            passwordKey(
              key: const Key('keypadBackspace'),
              label: '<-',
              height: 42,
              minimumHeight: 42,
              fontSize: 22,
              top: redTop,
              bottom: redBottom,
              onPressed: backspacePassword,
            ),
          ]),
        ],
      );
    }

    return Column(
      children: [
        keypadRow([
          for (final digit in ['1', '2', '3'])
            passwordKey(
              key: Key('keypad$digit'),
              label: digit,
              onPressed: () => insertPasswordText(digit),
            ),
        ]),
        const SizedBox(height: 5),
        keypadRow([
          for (final digit in ['4', '5', '6'])
            passwordKey(
              key: Key('keypad$digit'),
              label: digit,
              onPressed: () => insertPasswordText(digit),
            ),
        ]),
        const SizedBox(height: 5),
        keypadRow([
          for (final digit in ['7', '8', '9'])
            passwordKey(
              key: Key('keypad$digit'),
              label: digit,
              onPressed: () => insertPasswordText(digit),
            ),
        ]),
        const SizedBox(height: 5),
        keypadRow([
          passwordKey(
            key: const Key('keypadClear'),
            label: 'CLR',
            fontSize: 29,
            top: redTop,
            bottom: redBottom,
            onPressed: clearPassword,
          ),
          passwordKey(
            key: const Key('keypad0'),
            label: '0',
            onPressed: () => insertPasswordText('0'),
          ),
          passwordKey(
            key: const Key('keypadBackspace'),
            label: '<-',
            fontSize: 31,
            top: redTop,
            bottom: redBottom,
            onPressed: backspacePassword,
          ),
        ]),
      ],
    );
  }

  Widget buildLocked() {
    const redTop = Color(0xffd32b31);
    const redBottom = Color(0xff7f0609);
    const modeTop = Color(0xffb96b25);
    const greenTop = Color(0xff43a047);
    const greenBottom = Color(0xff1b5e20);
    const modeBottom = Color(0xff6d3107);

    return Scaffold(
      backgroundColor: const Color(0xfff4f4f4),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: SizedBox(
              width: min(MediaQuery.sizeOf(context).width, 562),
              height: message == null && !loginHintVisible ? 590 : 650,
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  padding: EdgeInsets.zero,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Container(
                      width: constraints.maxWidth,
                      decoration: BoxDecoration(
                        color: const Color(0xfff4f4f4),
                        border: Border.all(color: const Color(0xffc6c6c6)),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onPanStart: (_) {
                              unawaited(startLoginWindowDrag());
                            },
                            child: Container(
                              height: 44,
                              color: const Color(0xff777777),
                              alignment: Alignment.centerLeft,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              child: const Text(
                                'Пароль',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                ),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Text.rich(
                                    TextSpan(
                                      children: [
                                        TextSpan(
                                          text: selectedVaultTitle,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        if (selectedVaultModifiedText
                                            case final modified?)
                                          TextSpan(text: ', $modified'),
                                      ],
                                    ),
                                    key: const Key('passwordPrompt'),
                                    maxLines: 1,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      color: Color(0xff16212a),
                                      fontWeight: FontWeight.normal,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  height: 48,
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Expanded(
                                        child: TextSelectionTheme(
                                          data: const TextSelectionThemeData(
                                            cursorColor: Colors.black,
                                            selectionColor: Colors.transparent,
                                            selectionHandleColor:
                                                Colors.transparent,
                                          ),
                                          child: TextField(
                                            key: const Key('passwordInput'),
                                            controller: passwordController,
                                            focusNode: passwordFocusNode,
                                            autofocus: true,
                                            obscureText: !showPassword,
                                            enableSuggestions: false,
                                            autocorrect: false,
                                            keyboardType:
                                                TextInputType.visiblePassword,
                                            textInputAction:
                                                TextInputAction.done,
                                            onSubmitted: (_) => unlock(),
                                            decoration: InputDecoration(
                                              isDense: true,
                                              filled: true,
                                              fillColor: Colors.white,
                                              border: const OutlineInputBorder(
                                                borderRadius: BorderRadius.zero,
                                              ),
                                              suffixIcon: IconButton(
                                                key: const Key(
                                                  'loginPasswordVisibility',
                                                ),
                                                tooltip: showPassword
                                                    ? 'Скрыть пароль'
                                                    : 'Показать пароль',
                                                icon: Icon(
                                                  showPassword
                                                      ? Icons.visibility_off
                                                      : Icons.visibility,
                                                ),
                                                onPressed: () =>
                                                    _updateShellState(
                                                  () => showPassword =
                                                      !showPassword,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Listener(
                                        key: const Key(
                                          'loginPasswordHintButton',
                                        ),
                                        onPointerDown: (_) =>
                                            showLoginPasswordHint(),
                                        onPointerUp: (_) =>
                                            hideLoginPasswordHint(),
                                        onPointerCancel: (_) =>
                                            hideLoginPasswordHint(),
                                        child: SizedBox.square(
                                          dimension: 48,
                                          child: passwordKey(
                                            label: 'Подсказка пароля',
                                            height: 48,
                                            top: const Color(0xffffdc58),
                                            bottom: const Color(0xffc58a00),
                                            onPressed:
                                                passwordFocusNode.requestFocus,
                                            child: const Icon(
                                              Icons.question_mark,
                                              color: Colors.white,
                                              size: 28,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (loginHintVisible) ...[
                                  const SizedBox(height: 8),
                                  Container(
                                    key: const Key('loginPasswordHint'),
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: const Color(0xfffff4bc),
                                      border: Border.all(
                                        color: const Color(0xffb18b00),
                                      ),
                                    ),
                                    child: Text(loginPasswordHint),
                                  ),
                                ],
                                const SizedBox(height: 20),
                                buildPasswordKeyboard(
                                  redTop: redTop,
                                  redBottom: redBottom,
                                ),
                                const SizedBox(height: 6),
                                keypadRow([
                                  passwordKey(
                                    key: const Key('keypadModeUppercase'),
                                    label: 'ABC',
                                    fontSize: 23,
                                    top: modeTop,
                                    bottom: modeBottom,
                                    onPressed: () => selectVirtualKeyboardMode(
                                      VirtualKeyboardMode.uppercase,
                                    ),
                                  ),
                                  passwordKey(
                                    key: const Key('keypadModeLowercase'),
                                    label: 'abc',
                                    fontSize: 23,
                                    top: modeTop,
                                    bottom: modeBottom,
                                    onPressed: () => selectVirtualKeyboardMode(
                                      VirtualKeyboardMode.lowercase,
                                    ),
                                  ),
                                  passwordKey(
                                    key: const Key('keypadModeNumeric'),
                                    label: '123',
                                    fontSize: 23,
                                    top: modeTop,
                                    bottom: modeBottom,
                                    onPressed: () => selectVirtualKeyboardMode(
                                      VirtualKeyboardMode.numeric,
                                    ),
                                  ),
                                  passwordKey(
                                    key: const Key('keypadModeSymbols'),
                                    label: '#!?',
                                    fontSize: 23,
                                    top: modeTop,
                                    bottom: modeBottom,
                                    onPressed: () => selectVirtualKeyboardMode(
                                      VirtualKeyboardMode.symbols,
                                    ),
                                  ),
                                ]),
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 18),
                                  child: Divider(height: 1),
                                ),
                                Row(
                                  children: [
                                    Expanded(
                                      child: SizedBox(
                                        width: double.infinity,
                                        height: 48,
                                        child: passwordKey(
                                          key: const Key('fileMenu'),
                                          label: 'Открыть файл',
                                          child: const Icon(
                                            Icons.folder_outlined,
                                            color: Colors.white,
                                            size: 25,
                                          ),
                                          height: 48,
                                          fontSize: 18,
                                          top: const Color(0xffffdc58),
                                          bottom: const Color(0xffc58a00),
                                          onPressed: pickSpbWalletFile,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: passwordKey(
                                        key: const Key('createVault'),
                                        label: '+',
                                        height: 40,
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                        top: const Color(0xffffdc58),
                                        bottom: const Color(0xffc58a00),
                                        onPressed: createNewVaultFromLogin,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: passwordKey(
                                        key: const Key('loginOk'),
                                        label: 'OK',
                                        height: 40,
                                        fontSize: 18,
                                        top: greenTop,
                                        bottom: greenBottom,
                                        onPressed: unlock,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: passwordKey(
                                        key: const Key('loginCancel'),
                                        label: '',
                                        child: const Icon(
                                          Icons.power_settings_new,
                                          color: Colors.white,
                                          size: 25,
                                        ),
                                        height: 40,
                                        fontSize: 18,
                                        top: redTop,
                                        bottom: redBottom,
                                        onPressed: () {
                                          exitApplication();
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                                if (message != null) ...[
                                  const SizedBox(height: 12),
                                  Text(
                                    message!,
                                    key: const Key('loginMessage'),
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.error,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
