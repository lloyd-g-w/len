import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app_services.dart';
import '../../core/format.dart';
import '../../data/archive/len_archives.dart';
import '../../platform/file_export.dart' show canSaveToDevice;
import '../../platform/len_file_io.dart';
import '../../ui/app_theme.dart';
import '../../ui/error_details.dart';
import '../documents/export/export_messages.dart';
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

/// The file name of a library backup made [at]: `Len backup 2026-10-13.len`.
String backupFileName(DateTime at) {
  String two(int n) => n.toString().padLeft(2, '0');
  return 'Len backup ${at.year}-${two(at.month)}-${two(at.day)}.${LenFormat.extension}';
}

/// Writes [scope] as a Len file named [name] behind a progress dialog and
/// saves (desktop), shares or with [toDevice] saves (Android) or downloads
/// (web) it, then says where it went. Returns whether it was saved.
Future<bool> exportLenFlow(
  BuildContext context,
  LenScope scope, {
  required String name,
  bool toDevice = false,
}) async {
  final services = AppScope.read(context);
  LenFileOutput? output;
  try {
    final written = await runWithSteps(
      context,
      scope.kind == LenArchiveKind.library ? 'Backing up' : 'Exporting',
      subject: name,
      cancellable: true,
      (progress) async {
        progress.stageStarted('Writing…');
        final out = output = await createLenFileOutput(name);
        final report = await services.lenFiles.write(
          scope,
          out.stream,
          cancel: progress.token,
          onProgress: progress.advanced,
        );
        progress.check();
        return report;
      },
    );
    if (!context.mounted) {
      await output?.discard();
      return false;
    }
    final saved = await output!.deliver(mime: LenFormat.mime, toDevice: toDevice);
    if (saved == null || !context.mounted) return false;
    final missing = written.missingBlobs;
    showExported(
      context,
      saved,
      plural: 'files',
      note: missing == 0
          ? null
          : '${missing == 1 ? '1 file wasn’t' : '$missing files weren’t'} on this device yet',
    );
    return true;
  } on Cancelled {
    await output?.discard();
    return false;
  } on Object catch (e, stack) {
    debugPrint('Len export failed: $e\n$stack');
    await output?.discard();
    if (context.mounted) showExportFailed(context, '“$name”', e);
    return false;
  }
}

/// Imports Len file [file] (picked by the user if not given) as a copy
/// behind a progress dialog: a notebook or folder into [parent] (null: the
/// library's top level), a library backup into a new folder named after
/// its date. Returns what was imported, or null if cancelled or failed
/// (the user has then been told why).
Future<LenImportResult?> importLenFlow(BuildContext context, {XFile? file, String? parent}) async {
  final services = AppScope.read(context);
  final picked = file ?? await openFile(acceptedTypeGroups: lenFileTypes);
  if (picked == null || !context.mounted) return null;
  final name = picked.name.isEmpty ? 'the file' : '“${picked.name}”';
  try {
    final result = await runWithSteps(
      context,
      'Importing',
      subject: picked.name,
      cancellable: true,
      (progress) async {
        progress.stageStarted('Reading…');
        return services.lenFiles.import(
          await openPickedInput(picked),
          parent: parent,
          // A backup goes into its own folder.
          folderName: (manifest) =>
              manifest.kind == LenArchiveKind.library ? backupFolderName(manifest) : null,
          folderColor: Palette.covers[6],
          cancel: progress.token,
          onProgress: progress.advanced,
        );
      },
    );
    if (context.mounted) showMessage(context, importedMessage(result));
    return result;
  } on Cancelled {
    return null;
  } on LenArchiveException catch (e) {
    if (context.mounted) _failed(context, '${e.message}: couldn’t import $name', '$e');
    return null;
  } on Object catch (e, stack) {
    debugPrint('Len import failed: $e\n$stack');
    if (context.mounted) _failed(context, 'Couldn’t import $name', '$e');
    return null;
  }
}

/// The folder a restored backup goes into: "Backup 13 Oct 2026".
String backupFolderName(LenManifest manifest) =>
    'Backup ${formatDay(DateTime.fromMillisecondsSinceEpoch(manifest.createdAt))}';

/// "Imported “Lecture”", "Restored your backup into “Backup 13 Oct 2026”",
/// with what was left out.
@visibleForTesting
String importedMessage(LenImportResult result) {
  final manifest = result.manifest;
  final what = switch (manifest.kind) {
    LenArchiveKind.notebook => 'Imported “${manifest.title}”',
    LenArchiveKind.folder => 'Imported the folder “${manifest.title}”',
    LenArchiveKind.library => 'Restored your backup into “${backupFolderName(manifest)}”',
  };
  final missing = result.missingBlobs;
  final skipped = result.skipped;
  return [
    what,
    if (missing > 0) '${missing == 1 ? '1 file was' : '$missing files were'} missing from it',
    if (skipped > 0) '${skipped == 1 ? '1 item' : '$skipped items'} couldn’t be read',
  ].join('; ');
}

void _failed(BuildContext context, String message, String details) => showMessage(
  context,
  message,
  action: SnackBarAction(
    label: 'Details',
    onPressed: () => showErrorDetails(context, title: 'Import failed', details: details),
  ),
);

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
