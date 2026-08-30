import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/di/injector.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/utils/extensions/context_extensions.dart';
import '../../../../data/backup/backup_service.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/app_sheet.dart';

/// Export and restore (ADR §18).
///
/// A local file is the one copy of a user's training that cannot be broken
/// from the server end, so this sits in plain sight rather than behind a
/// "danger zone".
class BackupCard extends StatefulWidget {
  const BackupCard({super.key});

  @override
  State<BackupCard> createState() => _BackupCardState();
}

class _BackupCardState extends State<BackupCard> {
  bool _busy = false;

  Future<void> _export() async {
    if (_busy) return;
    setState(() => _busy = true);

    final l10n = context.l10n;
    try {
      final json = await getIt<BackupService>().export();

      // Written to a temporary file rather than shared as raw text: a backup
      // is measured in megabytes once there is real history, and every share
      // target handles a file better than a wall of JSON.
      final directory = await getTemporaryDirectory();
      final stamp = DateTime.now().toIso8601String().split('T').first;
      final file = File('${directory.path}/groove-backup-$stamp.json');
      await file.writeAsString(json);

      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: l10n.backupShareSubject,
        ),
      );
    } catch (error, stackTrace) {
      AppLogger.e('Export failed', error: error, stackTrace: stackTrace);
      if (mounted) context.showSnackBar(l10n.stateErrorBody, isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    if (_busy) return;

    final l10n = context.l10n;
    final service = getIt<BackupService>();

    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    final path = picked?.path;
    if (path == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final json = await File(path).readAsString();

      // Parsed and counted before anything is written, so the confirmation can
      // state exactly what is about to replace the user's data.
      final preview = service.preview(json);
      if (!mounted) return;

      final confirmed = await confirm(
        context,
        title: l10n.backupRestoreTitle,
        message: l10n.backupRestoreBody(preview.totalRows),
        confirmLabel: l10n.backupRestore,
      );
      if (!confirmed || !mounted) return;

      final restored = await service.restore(json);
      if (mounted) context.showSnackBar(l10n.backupRestored(restored));
    } on FormatException catch (error) {
      AppLogger.w('Backup rejected: $error', tag: 'BACKUP');
      if (mounted) context.showSnackBar(l10n.backupInvalid, isError: true);
    } catch (error, stackTrace) {
      AppLogger.e('Restore failed', error: error, stackTrace: stackTrace);
      if (mounted) context.showSnackBar(l10n.backupInvalid, isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs,
            ),
            leading: const Icon(Icons.ios_share_rounded),
            title: Text(l10n.backupExport),
            subtitle: Text(l10n.backupExportDescription),
            trailing: _busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
            // Disabled while busy, so a second tap can't start a parallel
            // export over the same temp file.
            onTap: _busy ? null : _export,
          ),
          const Divider(height: 1),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs,
            ),
            leading: Icon(
              Icons.settings_backup_restore_rounded,
              color: context.colors.error,
            ),
            title: Text(l10n.backupRestore),
            subtitle: Text(l10n.backupRestoreDescription),
            onTap: _busy ? null : _restore,
          ),
        ],
      ),
    );
  }
}
