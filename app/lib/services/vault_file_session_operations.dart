part of '../main.dart';

extension _VaultFileSessionOperations on _VaultShellState {
  Future<File> swlVaultFile() async {
    final directory = await appVaultDirectory();
    return File('${directory.path}/$normalizedVaultBaseName.swl');
  }

  Future<File> recentVaultsFile() async {
    final stateDirectory = await appStateDirectory();
    final current = File('${stateDirectory.path}/wallet_aps_recent_swl.json');
    if (!current.existsSync()) {
      // One-time compatibility copy for installations created before renaming.
      final legacy = File('${stateDirectory.path}/actitpass_recent_swl.json');
      if (legacy.existsSync()) {
        await legacy.copy(current.path);
      }
    }
    return current;
  }

  Future<Directory> appStateDirectory() async {
    if (Platform.isAndroid) {
      final directory = Directory('${Directory.systemTemp.parent.path}/files');
      if (!directory.existsSync()) {
        directory.createSync(recursive: true);
      }
      return directory;
    }
    final directory = await getApplicationSupportDirectory();
    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
    }
    return directory;
  }

  Future<File> prepareDesktopWorkingVault(String sourcePath) async {
    final source = File(sourcePath).absolute;
    if (!await source.exists()) {
      throw StateError('Файл базы не найден: ${source.path}');
    }
    await handlePendingLocalRecovery(source.path);
    final stateDirectory = await appStateDirectory();
    final workingDirectory = Directory(
      '${stateDirectory.path}${Platform.pathSeparator}vault_working',
    );
    await workingDirectory.create(recursive: true);
    final identity = sha256
        .convert(utf8.encode(source.path.toLowerCase()))
        .toString()
        .substring(0, 24);
    final working = File(
      '${workingDirectory.path}${Platform.pathSeparator}$identity.swl',
    );
    await source.copy(working.path);
    syncSourceLength = await source.length();
    syncSourceSha256 = await sha256File(source);
    return working;
  }

  Future<Directory> appVaultDirectory() async {
    final base = Platform.isAndroid
        ? await appStateDirectory()
        : await getApplicationDocumentsDirectory();
    final directory = Directory('${base.path}/Wallet APS');
    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
    }
    return directory;
  }

  bool isAndroidCacheWalletPath(String path) =>
      Platform.isAndroid && path.contains('/cache/spbwallet_');
  Future<void> initializeExternalWalletHandling() async {
    if (!Platform.isAndroid) return;
    spbWalletChannel.setMethodCallHandler((call) async {
      if (call.method != 'openWallet' || call.arguments is! Map) return;
      await applyExternalAndroidWallet(
        Map<Object?, Object?>.from(call.arguments as Map),
      );
    });
    try {
      await handlePendingAndroidRecovery();
      final launchWallet = await spbWalletChannel
          .invokeMapMethod<Object?, Object?>('getLaunchWallet');
      if (launchWallet != null) {
        await applyExternalAndroidWallet(launchWallet);
      }
    } on MissingPluginException {
      // Widget tests and non-Android targets do not provide this channel.
    }
  }

  Future<void> handlePendingAndroidRecovery() async {
    final recovery = await spbWalletChannel
        .invokeMapMethod<String, Object?>('getPendingSpbWalletRecovery');
    if (recovery == null || !mounted) return;
    final restore = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Найдена резервная копия базы'),
        content: const Text(
          'Предыдущая запись Android-хранилища была прервана или не прошла '
          'проверку. Восстановить последний подтверждённый файл?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Оставить текущий файл'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Восстановить'),
          ),
        ],
      ),
    );
    try {
      if (restore == true) {
        await spbWalletChannel
            .invokeMapMethod<String, Object?>('restoreSpbWalletRecovery');
        showSpbOperationMessage('Резервная копия .swl восстановлена.');
      } else {
        await spbWalletChannel.invokeMethod<bool>('discardSpbWalletRecovery');
      }
    } catch (error) {
      if (mounted) {
        _updateShellState(
            () => message = 'Не удалось восстановить .swl базу: $error');
      }
    }
  }

  Future<void> applyExternalAndroidWallet(Map<Object?, Object?> wallet) async {
    final path = wallet['localPath']?.toString();
    if (path == null || path.isEmpty || !mounted) return;
    if (unlocked || spbWallet != null) {
      if (!await closeCurrentVaultForPasswordPrompt() || !mounted) return;
    }
    final displayName =
        wallet['displayName']?.toString() ?? _vaultTitleFromPath(path);
    final uri = wallet['uri']?.toString();
    _updateShellState(() {
      entryMode = EntryMode.openSwl;
      spbWalletPath = path;
      spbWalletUri = uri;
      spbWalletWritable = wallet['writable'] != false;
      spbWalletDisplayPath = wallet['displayPath']?.toString() ?? uri ?? path;
      syncSourcePath = null;
      syncSourceLength = (wallet['sourceLength'] as num?)?.toInt();
      syncSourceSha256 = wallet['sourceSha256']?.toString();
      syncSourceUrl = null;
      syncSourceEtag = null;
      syncOriginProvider = null;
      vaultNameController.text = displayName;
      passwordController.clear();
      message = null;
    });
    if (uri != null && uri.isNotEmpty && wallet['persisted'] != false) {
      await rememberRecentVaultEntry(
        ExistingVault(
          title: displayName,
          uri: uri,
          displayPath: spbWalletDisplayPath,
        ),
      );
    }
    passwordFocusNode.requestFocus();
  }

  void synchronizeWindowMode() {
    if (!Platform.isWindows) return;
    final desiredMode = unlocked
        ? 'main'
        : message == null && !loginHintVisible
            ? 'login'
            : 'loginExpanded';
    final mainTitle = unlocked ? selectedVaultTitle : null;
    if (configuredWindowMode == desiredMode &&
        (!unlocked || configuredMainWindowTitle == mainTitle)) {
      return;
    }
    configuredWindowMode = desiredMode;
    configuredMainWindowTitle = mainTitle;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (unlocked) {
        configureMainWindow();
      } else {
        configureLoginWindow(expanded: message != null);
      }
    });
  }

  Future<void> configureLoginWindow({bool expanded = false}) async {
    if (!Platform.isWindows) return;
    try {
      await windowChannel.invokeMethod<void>(
        expanded ? 'showLoginExpanded' : 'showLogin',
      );
    } on MissingPluginException {
      // Other Flutter targets do not provide the Win32 window channel.
    }
  }

  Future<void> configureMainWindow() async {
    if (!Platform.isWindows) return;
    try {
      await windowChannel.invokeMethod<void>('showMain', selectedVaultTitle);
    } on MissingPluginException {
      // Other Flutter targets do not provide the Win32 window channel.
    }
  }

  Future<void> startLoginWindowDrag() async {
    if (!Platform.isWindows) return;
    try {
      await windowChannel.invokeMethod<void>('startDrag');
    } on MissingPluginException {
      // Other Flutter targets do not provide the Win32 window channel.
    }
  }

  Future<T> mutateVault<T>(FutureOr<T> Function() operation) async {
    final value = await vaultOperations.mutate(operation);
    vaultDirty = vaultOperations.isDirty;
    spbWritePending = vaultDirty;
    return value;
  }

  Future<SessionUndoEntry> captureSessionUndo(
    String label,
    String iconId,
  ) async {
    final wallet = spbWallet;
    if (wallet == null) {
      throw StateError('База данных не открыта.');
    }
    return SessionUndoEntry(
      label: label,
      iconId: iconId,
      databaseSnapshot: await wallet.createUndoSnapshot(),
      trash: List<SessionTrashEntry>.from(sessionTrash),
      trashCardIds: Set<String>.from(sessionTrashCardIds),
      trashFolderPaths: Set<String>.from(sessionTrashFolderPaths),
      trashTemplateIds: Set<String>.from(sessionTrashTemplateIds),
    );
  }

  void commitSessionUndo(SessionUndoEntry entry) {
    sessionUndoHistory.add(entry);
    var totalBytes = sessionUndoHistory.fold<int>(
      0,
      (sum, item) => sum + item.databaseSnapshot.byteLength,
    );
    while (sessionUndoHistory.length >
            _VaultShellState.sessionUndoEntryLimit ||
        totalBytes > _VaultShellState.sessionUndoByteLimit) {
      totalBytes -= sessionUndoHistory.first.databaseSnapshot.byteLength;
      sessionUndoHistory.removeAt(0).databaseSnapshot.dispose();
    }
    if (mounted) _updateShellState(() {});
  }

  void discardSessionUndo(SessionUndoEntry? entry) {
    entry?.databaseSnapshot.dispose();
  }

  void clearSessionUndoHistory() {
    for (final entry in sessionUndoHistory) {
      entry.databaseSnapshot.dispose();
    }
    sessionUndoHistory.clear();
  }

  Future<void> restoreSessionUndoAt(int index) async {
    final wallet = spbWallet;
    if (wallet == null ||
        sessionUndoInProgress ||
        index < 0 ||
        index >= sessionUndoHistory.length) {
      return;
    }
    sessionUndoInProgress = true;
    final entry = sessionUndoHistory[index];
    try {
      await mutateVault<void>(
        () => wallet.restoreUndoSnapshot(entry.databaseSnapshot),
      );
      sessionTrash
        ..clear()
        ..addAll(entry.trash);
      sessionTrashCardIds
        ..clear()
        ..addAll(entry.trashCardIds);
      sessionTrashFolderPaths
        ..clear()
        ..addAll(entry.trashFolderPaths);
      sessionTrashTemplateIds
        ..clear()
        ..addAll(entry.trashTemplateIds);
      for (final removed in sessionUndoHistory.sublist(
        index,
        sessionUndoHistory.length,
      )) {
        removed.databaseSnapshot.dispose();
      }
      sessionUndoHistory.removeRange(index, sessionUndoHistory.length);
      final written = await writeBackSpbWallet();
      final snapshot = wallet.loadSnapshot();
      if (!mounted) return;
      _updateShellState(() {
        applySpbSnapshot(snapshot);
        if (selectedItemId != null &&
            !items.any((item) => item.id == selectedItemId)) {
          selectedItemId = null;
        }
        if (selectedTemplateId != null &&
            !templates.any((template) => template.id == selectedTemplateId)) {
          selectedTemplateId = null;
        }
        if (written) message = null;
      });
      showSpbOperationMessage('Отменено: ${entry.label}');
    } catch (error) {
      showSpbOperationMessage('Не удалось отменить изменение: $error');
    } finally {
      sessionUndoInProgress = false;
    }
  }

  bool isPathInSessionTrash(String path) {
    final normalized = path.trim();
    return sessionTrashFolderPaths.any(
      (folderPath) =>
          normalized == folderPath || normalized.startsWith('$folderPath / '),
    );
  }

  void purgeSessionTrashFromDatabase() {
    final wallet = spbWallet;
    if (wallet == null || sessionTrash.isEmpty) {
      sessionTrash.clear();
      sessionTrashCardIds.clear();
      sessionTrashFolderPaths.clear();
      sessionTrashTemplateIds.clear();
      return;
    }
    final rootFolders = sessionTrashFolderPaths.where(
      (path) => !sessionTrashFolderPaths.any(
        (other) => other != path && path.startsWith('$other / '),
      ),
    );
    wallet.runTransaction<void>(() {
      for (final path in rootFolders) {
        wallet.deleteCategory(path);
      }
      for (final cardId in sessionTrashCardIds) {
        wallet.deleteCard(cardId);
      }
      for (final templateId in sessionTrashTemplateIds) {
        wallet.deleteTemplate(templateId);
      }
    });
    sessionTrash.clear();
    sessionTrashCardIds.clear();
    sessionTrashFolderPaths.clear();
    sessionTrashTemplateIds.clear();
  }

  Future<bool> finalizeSessionTrash() async {
    if (spbWallet != null && sessionTrash.isNotEmpty) {
      await mutateVault<void>(
        purgeSessionTrashFromDatabase,
      );
    }
    return writeBackSpbWallet();
  }

  Future<void> exitToPasswordPrompt() async {
    if (!await closeCurrentVaultForPasswordPrompt() || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) passwordFocusNode.requestFocus();
    });
  }

  void scheduleAutomaticUnlock() {
    passwordUnlockDebounce?.cancel();
    if (unlocked ||
        entryMode != EntryMode.openSwl ||
        spbWalletPath == null ||
        spbWalletPath!.isEmpty ||
        passwordController.text.isEmpty) {
      return;
    }
    passwordUnlockDebounce = Timer(
      const Duration(milliseconds: 180),
      () => unlock(automatic: true),
    );
  }

  Future<void> unlock({bool automatic = false}) async {
    if (automatic && automaticUnlockInProgress) return;
    final password = passwordController.text;
    if (entryMode == EntryMode.openSwl) {
      if (spbWalletPath == null || spbWalletPath!.isEmpty) {
        _updateShellState(() => message = 'Выберите файл базы .swl.');
        return;
      }
      try {
        if (automatic) automaticUnlockInProgress = true;
        await loadSpb64PngIconAssets();
        if (spbWallet != null) {
          final saved = await finalizeSessionTrash();
          if (!saved) {
            if (!automatic && mounted) {
              _updateShellState(
                () => message =
                    'Рабочая база сохранена, но исходный .swl файл пока не '
                        'обновлён. Устраните ошибку хранилища и повторите вход.',
              );
            }
            return;
          }
        }
        clearSessionUndoHistory();
        spbWallet?.close(flush: vaultDirty);
        if (!Platform.isAndroid &&
            syncSourcePath == null &&
            syncSourceUrl == null) {
          final sourcePath = spbWalletPath!;
          final working = await prepareDesktopWorkingVault(sourcePath);
          spbWalletPath = working.path;
          spbWalletDisplayPath = sourcePath;
          syncSourcePath = sourcePath;
        }
        final wallet = SpbWalletDatabase.open(spbWalletPath!, password);
        final snapshot = wallet.loadSnapshot();
        final integrityReport = wallet.inspectIntegrity();
        spbWallet = wallet;
        vaultOperations.reopen();
        vaultDirty = false;
        spbIconIdByUiIcon.clear();
        _updateShellState(() {
          applySpbSnapshot(snapshot);
          conflicts = [];
          lastSyncAt = null;
          selectedItemId = items.isEmpty ? null : items.first.id;
          unlocked = true;
          sessionController.markActivity();
          activeView = 'cards';
          message =
              integrityReport.hasProblems ? integrityReport.userMessage : null;
        });
        sessionController.markActivity();
        passwordUnlockDebounce?.cancel();
        passwordController.clear();
        confirmController.clear();
        if (!Platform.isAndroid || spbWalletUri == null) {
          await rememberRecentVault(syncSourcePath ?? spbWalletPath!);
        }
      } catch (error) {
        if (!automatic) {
          passwordController.clear();
          _updateShellState(
            () => message =
                'Не удалось открыть базу. Проверьте правильность пароля.',
          );
          passwordFocusNode.requestFocus();
        }
      } finally {
        if (automatic) automaticUnlockInProgress = false;
      }
      return;
    }
    if (createMode && password != confirmController.text) {
      _updateShellState(() => message = 'Пароли не совпадают.');
      return;
    }
    if (createMode) {
      if (creatingVault) return;
      _updateShellState(() {
        creatingVault = true;
        message = null;
      });
      await WidgetsBinding.instance.endOfFrame;
      await Future<void>.delayed(const Duration(milliseconds: 16));
      try {
        await createSwlVault(password);
        passwordController.clear();
        confirmController.clear();
      } catch (error) {
        _updateShellState(
            () => message = 'Не удалось создать .swl базу: $error');
      } finally {
        if (mounted) {
          _updateShellState(() => creatingVault = false);
        }
      }
      return;
    }
  }

  Future<bool> _closeCurrentVaultForPasswordPromptImpl() async {
    passwordUnlockDebounce?.cancel();
    automaticUnlockInProgress = false;
    if (spbWallet != null) {
      final saved = await finalizeSessionTrash();
      if (!saved) return false;
      await vaultOperations.lock();
    }
    clearSessionUndoHistory();
    spbWallet?.close(flush: vaultDirty);
    spbWallet = null;
    vaultOperations.reset();
    vaultDirty = false;
    passwordController.clear();
    confirmController.clear();
    revealed.clear();
    loginHintVisible = false;
    loginPasswordHint = '';
    showPassword = false;
    if (!mounted) return true;
    _updateShellState(() {
      unlocked = false;
      entryMode = EntryMode.openSwl;
      message = null;
    });
    return true;
  }

  Future<void> pickSpbWalletFile() async {
    if (Platform.isAndroid) {
      try {
        final picked = await spbWalletChannel.invokeMapMethod<String, Object?>(
          'pickSpbWallet',
        );
        if (picked == null) return;
        final path = picked['localPath']?.toString();
        if (path == null || path.isEmpty) return;
        if (!await closeCurrentVaultForPasswordPrompt() || !mounted) return;
        _updateShellState(() {
          spbWalletPath = path;
          spbWalletUri = picked['uri']?.toString();
          spbWalletWritable = picked['writable'] != false;
          spbWalletDisplayPath =
              picked['displayPath']?.toString() ?? spbWalletUri;
          syncSourcePath = null;
          syncSourceLength = (picked['sourceLength'] as num?)?.toInt();
          syncSourceSha256 = picked['sourceSha256']?.toString();
          syncSourceUrl = null;
          syncSourceEtag = null;
          syncOriginProvider = null;
          vaultNameController.text = picked['displayName']?.toString() ??
              File(path).uri.pathSegments.last;
          message = null;
        });
        final uri = spbWalletUri;
        if (uri != null && uri.isNotEmpty && picked['persisted'] != false) {
          await rememberRecentVaultEntry(
            ExistingVault(
              title: vaultNameController.text,
              uri: uri,
              displayPath: spbWalletDisplayPath,
            ),
          );
        } else if (picked['persisted'] == false) {
          showSpbOperationMessage(
            'Поставщик файла не разрешил постоянный доступ. После '
            'перезапуска файл потребуется выбрать снова.',
          );
        }
      } catch (error) {
        _updateShellState(
            () => message = 'Не удалось выбрать .swl файл: $error');
      }
      return;
    }
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['swl', 'db', 'sqlite'],
      withData: false,
    );
    final path = result?.files.single.path;
    if (path == null) return;
    if (!await closeCurrentVaultForPasswordPrompt() || !mounted) return;
    _updateShellState(() {
      spbWalletPath = path;
      spbWalletUri = null;
      spbWalletDisplayPath = path;
      syncSourcePath = null;
      syncSourceLength = null;
      syncSourceSha256 = null;
      syncSourceUrl = null;
      syncSourceEtag = null;
      syncOriginProvider = null;
      vaultNameController.text = File(path).uri.pathSegments.last;
      message = null;
    });
    await rememberRecentVault(path);
  }

  Future<void> loadRecentVaults() async {
    final found = <ExistingVault>[];
    try {
      final file = await recentVaultsFile();
      if (file.existsSync()) {
        final decoded = jsonDecode(await file.readAsString()) as List<dynamic>;
        for (final raw in decoded) {
          ExistingVault? vault;
          if (raw is String) {
            final file = File(raw);
            if (isAndroidCacheWalletPath(file.path)) continue;
            if (!file.existsSync() ||
                !file.path.toLowerCase().endsWith('.swl')) {
              continue;
            }
            vault = ExistingVault(
              title: _vaultTitleFromPath(file.path),
              path: file.path,
              displayPath: file.path,
            );
          } else if (raw is Map<String, dynamic>) {
            vault = ExistingVault.fromJson(raw);
            if (vault.uri == null) {
              final path = vault.path;
              if (path == null || isAndroidCacheWalletPath(path)) continue;
              if (!File(path).existsSync() ||
                  !path.toLowerCase().endsWith('.swl')) {
                continue;
              }
            }
          } else if (raw is Map) {
            vault = ExistingVault.fromJson(Map<String, dynamic>.from(raw));
          }
          if (vault == null) continue;
          if (found.any((entry) => entry.key == vault!.key)) {
            continue;
          }
          found.add(vault);
        }
      }
    } catch (_) {}
    if (!mounted) return;
    _updateShellState(() => recentVaults = found);
    if (found.isNotEmpty &&
        !unlocked &&
        entryMode == EntryMode.openSwl &&
        (spbWalletPath == null || spbWalletPath!.isEmpty)) {
      await chooseExistingVault(found.first);
    }
  }

  Future<void> rememberRecentVault(String path) async {
    if (path.isEmpty) return;
    if (isAndroidCacheWalletPath(path)) return;
    await rememberRecentVaultEntry(
      ExistingVault(
        title: _vaultTitleFromPath(path),
        path: path,
        displayPath: path,
      ),
    );
  }

  Future<void> rememberRecentVaultEntry(ExistingVault vault) async {
    final entries = [
      vault,
      ...recentVaults.where((entry) => entry.key != vault.key).where(
            (entry) =>
                entry.uri != null ||
                (entry.path != null && !isAndroidCacheWalletPath(entry.path!)),
          ),
    ].take(8).toList();
    final file = await recentVaultsFile();
    await file.writeAsString(
      const JsonEncoder.withIndent(
        '  ',
      ).convert(entries.map((entry) => entry.toJson()).toList()),
    );
    if (!mounted) return;
    _updateShellState(() => recentVaults = entries);
  }

  Future<void> createSwlVault(
    String password, {
    String passwordHint = '',
    File? targetFile,
    bool rememberLocalFile = true,
    bool unlockAfterCreate = true,
  }) async {
    final file = targetFile ?? await swlVaultFile();
    if (file.existsSync()) {
      throw StateError(
        'База "${file.uri.pathSegments.last}" уже есть. Выберите другое название или откройте существующую базу.',
      );
    }
    final baseData = await rootBundle.load('assets/base_wallet/MyWallet.swl');
    final payload = <String, dynamic>{
      'path': file.path,
      'password': password,
      'passwordHint': passwordHint,
      'baseBytes': baseData.buffer.asUint8List(
        baseData.offsetInBytes,
        baseData.lengthInBytes,
      ),
    };
    await compute<Map<String, dynamic>, bool>(
      createSwlVaultFromBaseFile,
      payload,
    );

    spbIconIdByUiIcon.clear();
    await loadSpb64PngIconAssets();
    final openedFile =
        Platform.isAndroid ? file : await prepareDesktopWorkingVault(file.path);
    final wallet = SpbWalletDatabase.open(openedFile.path, password);
    final snapshot = wallet.loadSnapshot();
    if (spbWallet != null) {
      final saved = await finalizeSessionTrash();
      if (!saved) {
        wallet.close(flush: false);
        throw StateError(
          'Текущая база не закрыта: исходный .swl файл не обновлён.',
        );
      }
    }
    clearSessionUndoHistory();
    spbWallet?.close(flush: vaultDirty);
    spbWallet = wallet;
    vaultOperations.reopen();
    vaultDirty = false;
    _updateShellState(() {
      spbWalletPath = openedFile.path;
      spbWalletUri = null;
      spbWalletDisplayPath = file.path;
      syncSourcePath = Platform.isAndroid ? null : file.path;
      if (Platform.isAndroid) {
        syncSourceLength = null;
        syncSourceSha256 = null;
      }
      syncSourceUrl = null;
      syncSourceEtag = null;
      syncOriginProvider = null;
      applySpbSnapshot(snapshot);
      conflicts = [];
      lastSyncAt = null;
      selectedItemId = items.isEmpty ? null : items.first.id;
      if (unlockAfterCreate) {
        unlocked = true;
        sessionController.markActivity();
        activeView = 'cards';
      }
      message = null;
    });
    if (rememberLocalFile) {
      await rememberRecentVault(file.path);
    }
  }

  Future<void> createNewVaultFromLogin() async {
    final pathController = TextEditingController();
    if (Platform.isAndroid) {
      pathController.text = 'Android-хранилище';
    }
    final nameController = TextEditingController(text: 'Новая база');
    final newPasswordController = TextEditingController();
    final repeatPasswordController = TextEditingController();
    final hintController = TextEditingController();
    var showNewPassword = false;
    var showRepeatedPassword = false;
    var isCreating = false;
    var createdVault = false;
    Map<String, Object?>? androidDocument;
    String? dialogError;

    Future<void> pickNewVaultDirectory(StateSetter setDialogState) async {
      if (Platform.isAndroid) {
        final baseName = nameController.text.trim().replaceAll(
              RegExp(r'\.swl$', caseSensitive: false),
              '',
            );
        final document = await spbWalletChannel
            .invokeMapMethod<String, Object?>('createSpbWalletDocument', {
          'displayName': '${baseName.isEmpty ? 'Новая база' : baseName}.swl',
        });
        if (document == null) return;
        setDialogState(() {
          androidDocument = document;
          pathController.text = document['displayPath']?.toString() ??
              document['displayName']?.toString() ??
              'Android-хранилище';
          dialogError = null;
        });
        return;
      }
      var selectedDirectory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Назначить путь для новой базы',
        lockParentWindow: true,
      );
      if (selectedDirectory == null || selectedDirectory.trim().isEmpty) {
        return;
      }
      if (Platform.isLinux) {
        var entityType = await FileSystemEntity.type(
          selectedDirectory,
          followLinks: true,
        );
        if (entityType == FileSystemEntityType.notFound &&
            await File(selectedDirectory).parent.exists()) {
          entityType = FileSystemEntityType.file;
        }
        selectedDirectory = normalizeNewVaultDirectorySelection(
          selectedDirectory,
          entityType,
        );
        if (selectedDirectory == null) {
          setDialogState(
            () => dialogError = 'Выберите существующую папку для новой базы.',
          );
          return;
        }
      }
      setDialogState(() {
        pathController.text = selectedDirectory!;
        dialogError = null;
      });
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xffececec),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          titlePadding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
          title: GestureDetector(
            key: const Key('newVaultDialogDragHandle'),
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) {
              unawaited(startLoginWindowDrag());
            },
            child: const SizedBox(
              height: 38,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Создание новой базы'),
              ),
            ),
          ),
          content: Theme(
            data: Theme.of(context).copyWith(
              inputDecorationTheme: const InputDecorationTheme(
                filled: true,
                fillColor: Colors.white,
              ),
            ),
            child: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: 42,
                      child: TextField(
                        key: const Key('newVaultPath'),
                        controller: pathController,
                        readOnly: true,
                        autofocus: true,
                        onTap: () => pickNewVaultDirectory(setDialogState),
                        decoration: InputDecoration(
                          labelText: 'Назначить путь',
                          hintText: Platform.isAndroid
                              ? 'Выберите файл в локальном или облачном хранилище'
                              : 'Выберите папку для новой базы',
                          border: const OutlineInputBorder(),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          suffixIconConstraints: const BoxConstraints.tightFor(
                            width: 40,
                            height: 40,
                          ),
                          suffixIcon: IconButton(
                            key: const Key('browseNewVaultPath'),
                            tooltip: Platform.isAndroid
                                ? 'Выбрать файл в проводнике'
                                : 'Выбрать папку в проводнике',
                            padding: EdgeInsets.zero,
                            icon: const Icon(Icons.folder_open_outlined),
                            onPressed: () =>
                                pickNewVaultDirectory(setDialogState),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 42,
                      child: TextField(
                        key: const Key('newVaultName'),
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'Название базы',
                          suffixText: '.swl',
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    PasswordField(
                      key: const Key('newVaultPassword'),
                      controller: newPasswordController,
                      label: 'Новый пароль',
                      visible: showNewPassword,
                      onToggle: () => setDialogState(
                        () => showNewPassword = !showNewPassword,
                      ),
                      onChanged: (_) => setDialogState(() {}),
                      compact: true,
                    ),
                    const SizedBox(height: 8),
                    PasswordStrengthBar(
                      key: const Key('newVaultPasswordStrength'),
                      password: newPasswordController.text,
                    ),
                    const SizedBox(height: 8),
                    PasswordField(
                      key: const Key('newVaultPasswordRepeat'),
                      controller: repeatPasswordController,
                      label: 'Повторите новый пароль',
                      visible: showRepeatedPassword,
                      onToggle: () => setDialogState(
                        () => showRepeatedPassword = !showRepeatedPassword,
                      ),
                      compact: true,
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 42,
                      child: TextField(
                        key: const Key('newVaultPasswordHint'),
                        controller: hintController,
                        decoration: const InputDecoration(
                          labelText: 'Подсказка',
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                      ),
                    ),
                    if (dialogError != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        dialogError!,
                        key: const Key('newVaultError'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
          actions: [
            SizedBox.square(
              dimension: 48,
              child: IgnorePointer(
                ignoring: isCreating,
                child: Opacity(
                  opacity: isCreating ? 0.6 : 1,
                  child: SpbGradientActionButton(
                    key: const Key('confirmCreateVault'),
                    icon: Icons.check,
                    tooltip: 'Создать базу',
                    colors: const [Color(0xff43a047), Color(0xff1b5e20)],
                    onTap: () async {
                      final selectedDirectory = pathController.text.trim();
                      final name = nameController.text.trim().replaceAll(
                            RegExp(r'\.swl$', caseSensitive: false),
                            '',
                          );
                      final newPassword = newPasswordController.text;
                      if (!Platform.isAndroid && selectedDirectory.isEmpty) {
                        setDialogState(
                          () => dialogError =
                              'Назначьте путь для файла новой базы.',
                        );
                        return;
                      }
                      if (name.isEmpty) {
                        setDialogState(
                          () => dialogError = 'Введите название базы.',
                        );
                        return;
                      }
                      if (newPassword.isEmpty) {
                        setDialogState(
                          () => dialogError = 'Введите новый пароль.',
                        );
                        return;
                      }
                      if (newPassword != repeatPasswordController.text) {
                        setDialogState(
                          () => dialogError = 'Новые пароли не совпадают.',
                        );
                        return;
                      }

                      final previousName = vaultNameController.text;
                      setDialogState(() {
                        isCreating = true;
                        dialogError = null;
                      });
                      vaultNameController.text = name;
                      try {
                        if (Platform.isAndroid) {
                          final document = androidDocument ??
                              await spbWalletChannel
                                  .invokeMapMethod<String, Object?>(
                                'createSpbWalletDocument',
                                {
                                  'displayName': '$normalizedVaultBaseName.swl',
                                },
                              );
                          if (document == null) {
                            if (dialogContext.mounted) {
                              setDialogState(() => isCreating = false);
                            }
                            return;
                          }
                          final directory = await appVaultDirectory();
                          final targetFile = File(
                            '${directory.path}${Platform.pathSeparator}'
                            '${DateTime.now().microsecondsSinceEpoch}_'
                            '$normalizedVaultBaseName.swl',
                          );
                          await createSwlVault(
                            newPassword,
                            passwordHint: hintController.text,
                            targetFile: targetFile,
                            rememberLocalFile: false,
                            unlockAfterCreate: false,
                          );
                          spbWalletUri = document['uri']?.toString();
                          spbWalletDisplayPath =
                              document['displayPath']?.toString() ??
                                  document['displayName']?.toString();
                          spbWalletWritable = document['writable'] != false;
                          final written = await writeBackSpbWallet(force: true);
                          if (!written) {
                            throw StateError(
                              'Не удалось записать новую базу в выбранный файл.',
                            );
                          }
                          await rememberRecentVaultEntry(
                            ExistingVault(
                              title: document['displayName']?.toString() ??
                                  '$normalizedVaultBaseName.swl',
                              uri: spbWalletUri,
                              displayPath: spbWalletDisplayPath,
                            ),
                          );
                        } else {
                          final targetFile = File(
                            '${Directory(selectedDirectory).path}'
                            '${Platform.pathSeparator}'
                            '$normalizedVaultBaseName.swl',
                          );
                          await createSwlVault(
                            newPassword,
                            passwordHint: hintController.text,
                            targetFile: targetFile,
                            unlockAfterCreate: false,
                          );
                        }
                        entryMode = EntryMode.openSwl;
                        createdVault = true;
                        if (dialogContext.mounted) {
                          Navigator.of(dialogContext).pop();
                        }
                      } catch (error) {
                        vaultNameController.text = previousName;
                        if (dialogContext.mounted) {
                          setDialogState(() {
                            isCreating = false;
                            dialogError =
                                'Не удалось создать .swl базу: $error';
                          });
                        }
                      }
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox.square(
              dimension: 48,
              child: IgnorePointer(
                ignoring: isCreating,
                child: Opacity(
                  opacity: isCreating ? 0.6 : 1,
                  child: SpbGradientActionButton(
                    key: const Key('cancelCreateVault'),
                    icon: Icons.close,
                    tooltip: 'Отмена',
                    colors: const [Color(0xffd32b31), Color(0xff7f0609)],
                    onTap: () => Navigator.of(dialogContext).pop(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    pathController.dispose();
    nameController.dispose();
    newPasswordController.clear();
    repeatPasswordController.clear();
    hintController.clear();
    newPasswordController.dispose();
    repeatPasswordController.dispose();
    hintController.dispose();
    if (!mounted) return;
    if (createdVault) {
      passwordController.clear();
      confirmController.clear();
      _updateShellState(() {
        unlocked = true;
        sessionController.markActivity();
        activeView = 'cards';
        message = null;
      });
    } else if (!unlocked) {
      passwordFocusNode.requestFocus();
    }
  }

  Future<void> chooseExistingVault(ExistingVault vault) async {
    try {
      if (Platform.isAndroid && vault.uri != null) {
        final copied = await spbWalletChannel.invokeMapMethod<String, Object?>(
          'copySpbWallet',
          {'uri': vault.uri, 'displayName': vault.title},
        );
        final localPath = copied?['localPath']?.toString();
        if (localPath == null || localPath.isEmpty) {
          throw StateError('Не удалось открыть выбранную .swl базу.');
        }
        if (!await closeCurrentVaultForPasswordPrompt() || !mounted) return;
        _updateShellState(() {
          entryMode = EntryMode.openSwl;
          message = null;
          spbWalletPath = localPath;
          spbWalletUri = vault.uri;
          spbWalletWritable = copied?['writable'] != false;
          spbWalletDisplayPath =
              copied?['displayPath']?.toString() ?? vault.displayPath;
          syncSourcePath = null;
          syncSourceLength = (copied?['sourceLength'] as num?)?.toInt();
          syncSourceSha256 = copied?['sourceSha256']?.toString();
          syncSourceUrl = null;
          syncSourceEtag = null;
          syncOriginProvider = null;
          vaultNameController.text =
              copied?['displayName']?.toString() ?? vault.title;
        });
      } else {
        if (!await closeCurrentVaultForPasswordPrompt() || !mounted) return;
        _updateShellState(() {
          entryMode = EntryMode.openSwl;
          message = null;
          spbWalletPath = vault.path;
          spbWalletUri = null;
          spbWalletWritable = true;
          spbWalletDisplayPath = vault.displayPath ?? vault.path;
          syncSourcePath = null;
          syncSourceLength = null;
          syncSourceSha256 = null;
          syncSourceUrl = null;
          syncSourceEtag = null;
          syncOriginProvider = null;
          vaultNameController.text = vault.title;
        });
      }
      await rememberRecentVaultEntry(
        ExistingVault(
          title: vaultNameController.text,
          path:
              Platform.isAndroid && spbWalletUri != null ? null : spbWalletPath,
          uri: spbWalletUri,
          displayPath: spbWalletDisplayPath,
        ),
      );
    } catch (error) {
      _updateShellState(
        () => message = 'Не удалось открыть последнюю .swl базу: $error',
      );
    }
  }

  Future<bool> writeBackSpbWallet({bool force = false}) async {
    final wallet = spbWallet;
    if (wallet == null) {
      spbWritePending = false;
      vaultDirty = false;
      return true;
    }
    if (vaultDirty && !vaultOperations.isDirty) {
      vaultOperations.markDirty();
    }
    if (!force && !vaultOperations.isDirty) {
      spbWritePending = false;
      vaultDirty = false;
      return true;
    }
    final ok = await vaultOperations.save((revision) async {
      wallet.saveRecentlyOpenedCardIds(recentlyOpenedItemIds);
      final stateDirectory = await appStateDirectory();
      final snapshot = await wallet.createVerifiedSnapshot(
        revision: revision,
        stagingDirectory: stateDirectory.path,
      );
      try {
        if (!snapshot.isValid) {
          throw StateError('SQLite quick_check: ${snapshot.quickCheck}');
        }
        if (Platform.isAndroid && spbWalletUri != null) {
          if (!spbWalletWritable) {
            throw StateError(
              'Файл открыт только для чтения. Выберите доступный для записи файл.',
            );
          }
          final written = await spbWalletChannel
              .invokeMapMethod<String, Object?>('writeSpbWallet', {
            'uri': spbWalletUri,
            'localPath': snapshot.path,
            'expectedLength': snapshot.length,
            'expectedSha256': snapshot.sha256,
            'expectedExistingLength': syncSourceLength,
            'expectedExistingSha256': syncSourceSha256,
          });
          if (written == null ||
              written['length'] != snapshot.length ||
              written['sha256'] != snapshot.sha256) {
            throw StateError(
              'Android не подтвердил размер и SHA-256 записанного файла.',
            );
          }
          syncSourceLength = snapshot.length;
          syncSourceSha256 = snapshot.sha256;
        }
        final sourcePath = syncSourcePath;
        if (sourcePath != null && sourcePath != spbWalletPath) {
          final result = await LocalFileVaultPublisher(
            sourcePath,
            expectedExistingLength: syncSourceLength,
            expectedExistingSha256: syncSourceSha256,
          ).publish(snapshot);
          syncSourceLength = result.length;
          syncSourceSha256 = result.sha256;
        }
        final sourceUrl = syncSourceUrl;
        if (sourceUrl != null) {
          final result = await WebDavVaultPublisher(
            destination: Uri.parse(sourceUrl),
            username: syncConfig['webdav:username']?.trim() ?? '',
            password: syncConfig['webdav:password'] ?? '',
            expectedEtag: syncSourceEtag,
          ).publish(snapshot);
          syncSourceEtag = result.etag;
        }
        if (spbWalletUri != null || sourcePath != null || sourceUrl != null) {
          lastSyncAt = DateTime.now();
        }
      } finally {
        await snapshot.dispose();
      }
    }, force: force);
    vaultDirty = vaultOperations.isDirty;
    spbWritePending = vaultDirty || !ok;
    if (!ok) {
      final error = vaultOperations.lastError;
      if (mounted) {
        final failure =
            'Изменения сохранены в рабочей копии, но не записаны в исходную '
            '.swl базу: $error';
        _updateShellState(() => message = failure);
        showSpbOperationMessage(failure);
      }
    }
    return ok;
  }

  bool ensureSpbWalletWritable() {
    if (!Platform.isAndroid || spbWalletUri == null || spbWalletWritable) {
      return true;
    }
    showSpbOperationMessage(
      'Эта база открыта только для чтения. Изменения не выполнялись.',
    );
    return false;
  }

  Future<void> createDatedArchiveCopy() async {
    if (spbWallet == null || spbWalletPath == null) {
      _updateShellState(() => message = 'Сначала откройте .swl базу.');
      return;
    }
    final saved = await writeBackSpbWallet();
    if (!saved || !mounted) return;
    if (Platform.isAndroid) {
      try {
        final now = DateTime.now();
        String two(int value) => value.toString().padLeft(2, '0');
        final baseName = selectedVaultTitle.replaceAll(
          RegExp(r'[\\/:*?"<>|]'),
          '_',
        );
        final bytes = await File(spbWalletPath!).readAsBytes();
        final path = await FilePicker.platform.saveFile(
          dialogTitle: 'Сохранить архивную копию',
          fileName: '${baseName}_${now.year}${two(now.month)}'
              '${two(now.day)}_${two(now.hour)}${two(now.minute)}.swl',
          type: FileType.custom,
          allowedExtensions: const ['swl'],
          bytes: bytes,
        );
        if (path != null) {
          showSpbOperationMessage('Архивная копия сохранена.');
        }
      } catch (error) {
        showSpbOperationMessage('Не удалось сохранить архивную копию: $error');
      }
      return;
    }
    final sourcePath = syncSourcePath ?? spbWalletPath!;
    final source = File(sourcePath);
    if (!source.existsSync()) {
      _updateShellState(
          () => message = 'Исходный файл базы не найден: $sourcePath');
      return;
    }
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    final suffix = '${now.year}${two(now.month)}${two(now.day)}';
    final sourceName = source.uri.pathSegments.last;
    final baseName = sourceName.replaceFirst(
      RegExp(r'\.swl$', caseSensitive: false),
      '',
    );
    final archiveName = '${suffix}_arc_$baseName.swl';
    final archivePath =
        '${source.parent.path}${Platform.pathSeparator}$archiveName';
    try {
      await source.copy(archivePath);
      if (!mounted) return;
      _updateShellState(() => message = 'Архивная копия создана: $archivePath');
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Архивная копия создана: $archiveName')),
        );
    } catch (error) {
      if (!mounted) return;
      _updateShellState(
          () => message = 'Не удалось создать архивную копию: $error');
    }
  }

  Future<void> repairCurrentWalletCompatibility() async {
    final wallet = spbWallet;
    final path = spbWalletPath;
    if (wallet == null || path == null || !ensureSpbWalletWritable()) return;
    final source = File(path);
    if (!source.existsSync()) {
      showSpbOperationMessage('Рабочая копия базы не найдена.');
      return;
    }
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
    final durableBackupBase = syncSourcePath ?? path;
    final backup = File(
      '$durableBackupBase.compatibility-$stamp.backup.swl',
    );
    SpbWalletUndoSnapshot? undo;
    try {
      final repairBackup = await wallet.createRepairBackup(backup.path);
      undo = await wallet.createUndoSnapshot();
      final report = await mutateVault(
        () => wallet.repairLegacyCompatibility(backup: repairBackup),
      );
      final written = await writeBackSpbWallet(force: true);
      if (!written) {
        throw StateError('Исправленная база не записана в исходный файл.');
      }
      undo.dispose();
      undo = null;
      final snapshot = wallet.loadSnapshot();
      if (!mounted) return;
      _updateShellState(() {
        applySpbSnapshot(snapshot);
        message = '${report.userMessage} Резервная копия: ${backup.path}';
      });
      showSpbOperationMessage(report.userMessage);
    } catch (error) {
      if (undo != null) {
        await wallet.restoreUndoSnapshot(undo);
        undo.dispose();
      }
      showSpbOperationMessage(
        'Восстановление отменено, исходные данные сохранены: $error',
      );
    }
  }
}
