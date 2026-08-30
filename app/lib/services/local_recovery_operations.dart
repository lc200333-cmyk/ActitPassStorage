part of '../main.dart';

extension _LocalRecoveryOperations on _VaultShellState {
  Future<void> handlePendingLocalRecovery(String destinationPath) async {
    final recovery =
        await LocalFileVaultPublisher.pendingRecovery(destinationPath);
    if (recovery == null || !mounted) return;
    final canRestore = recovery.canRestorePrevious;
    final restore = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Незавершённое сохранение базы'),
        content: Text(
          canRestore
              ? 'Для ${File(destinationPath).uri.pathSegments.last} найдена '
                  'резервная копия. Восстановить предыдущий подтверждённый файл?'
              : 'Для ${File(destinationPath).uri.pathSegments.last} найдена '
                  'неподтверждённая новая запись. Предыдущей копии нет; можно '
                  'проверить и оставить текущий файл.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Оставить новый файл'),
          ),
          if (canRestore)
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Восстановить'),
            ),
        ],
      ),
    );
    if (restore == true) {
      await recovery.restorePrevious();
    } else {
      await recovery.keepPublished();
    }
  }
}
