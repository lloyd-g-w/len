import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app_services.dart';
import '../../core/format.dart';
import '../../data/archive/len_archives.dart';
import '../../platform/file_export.dart' show canSaveToDevice;
import '../../platform/len_file_io.dart';
import '../../ui/app_dialogs.dart';
import '../../ui/error_details.dart';
import '../documents/export/export_messages.dart' show showExported;
import '../documents/export/export_options.dart' show safeFileName;
import '../documents/progress_dialog.dart';

/// Len files in the file picker. Android's picker filters by MIME type,
/// and no app knows Len's: there it shows every file.
List<XTypeGroup> get lenFileTypes => defaultTargetPlatform == TargetPlatform.android
    ? const [XTypeGroup(label: 'Len')]
    : const [
        XTypeGroup(label: 'Len', extensions: [LenFormat.extension], mimeTypes: [LenFormat.mime]),
      ];

/// The file name of a Len file of [title]: `Lecture.len`.
String lenFileName(String title) => '${safeFileName(title)}.${LenFormat.extension}';

/// The file name of a library backup made [at]: `Len backup 13 Oct
/// 2026.len` (the date as in the folder a restore makes, R8-20).
String backupFileName(DateTime at) => 'Len backup ${formatDay(at)}.${LenFormat.extension}';

/// Above this many bytes of files, a browser that can't write a backup as
/// it goes is likely to run out of memory: warn first (UX_AUDIT R8-17).
const webBackupWarnBytes = 500 << 20;

/// Writes [scope] as a Len file named [name] behind a progress dialog,
/// asking where to save it first where the platform can (desktop, some
/// browsers), else sharing or with [toDevice] saving it (Android) or
/// downloading it (web) when done; then says where it went. Returns
/// whether it was saved.
Future<bool> exportLenFlow(
  BuildContext context,
  LenScope scope, {
  required String name,
  bool toDevice = false,
}) async {
  final services = AppScope.read(context);
  final backup = scope.kind == LenArchiveKind.library;
  if (backup && !lenFilesStream && !await _confirmLarge(context, services)) return false;
  LenFileOutput? output;
  try {
    output = await createLenFileOutput(name, mime: LenFormat.mime, toDevice: toDevice);
    if (output == null || !context.mounted) {
      await output?.discard();
      return false;
    }
    final out = output;
    final written = await runWithSteps(
      context,
      backup ? 'Backing up' : 'Exporting',
      subject: name,
      cancellable: true,
      (progress) async {
        progress.stageStarted('Writing…');
        final report = await services.lenFiles.write(
          scope,
          out.stream,
          cancel: progress.token,
          onProgress: progress.advanced,
          drain: out.drain,
        );
        progress.check();
        return report;
      },
    );
    if (!context.mounted) {
      await out.discard();
      return false;
    }
    final saved = await out.deliver();
    if (saved == null || !context.mounted) return false;
    showExported(context, saved, plural: 'files', note: notDownloadedNote(written.missingBlobs));
    return true;
  } on Cancelled {
    await output?.discard();
    return false;
  } on Object catch (e, stack) {
    debugPrint('Len export failed: $e\n$stack');
    await output?.discard();
    if (!context.mounted) return false;
    showMessage(
      context,
      backup ? 'Couldn’t back up your library' : 'Couldn’t export “$name”',
      action: SnackBarAction(
        label: 'Details',
        onPressed: () => unawaited(
          showErrorDetails(
            context,
            title: backup ? 'Backup failed' : 'Export failed',
            details: '$e',
          ),
        ),
      ),
    );
    return false;
  }
}

/// What a Len file left out because it wasn't on this device (and
/// couldn't be downloaded first), R8-22.
@visibleForTesting
String? notDownloadedNote(int missing) => switch (missing) {
  0 => null,
  1 => '1 PDF, image or recording isn’t downloaded yet and isn’t in it',
  _ => '$missing PDFs, images or recordings aren’t downloaded yet and aren’t in it',
};

/// In a browser that can't write as it goes, asks before backing up more
/// than [webBackupWarnBytes] of files (R8-17).
Future<bool> _confirmLarge(BuildContext context, AppServices services) async {
  final bytes = services.lenFiles.libraryBlobBytes();
  if (bytes < webBackupWarnBytes) return true;
  return confirmAction(
    context,
    title: 'Back up ${formatBytes(bytes)} in this browser?',
    message:
        'This browser holds a backup in memory while making it, and one this big may fail. '
        'Back up your folders one by one instead (Export… in a folder’s menu), or set up sync.',
    confirmLabel: 'Back up anyway',
  );
}

/// Backs up the whole library into one Len file (Settings → Backup, the
/// library's notice) and remembers when; returns whether it was saved.
Future<bool> backupLibraryFlow(BuildContext context) async {
  final services = AppScope.read(context);
  final now = DateTime.now();
  final saved = await exportLenFlow(
    context,
    const LenScope.library(),
    name: backupFileName(now),
    // Android: a backup belongs in a file the user keeps, not a message.
    toDevice: canSaveToDevice,
  );
  if (saved) services.settings.lastBackupAt = now.millisecondsSinceEpoch;
  return saved;
}
