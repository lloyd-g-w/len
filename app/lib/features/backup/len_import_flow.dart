import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../app_services.dart';
import '../../core/format.dart';
import '../../data/archive/len_archives.dart';
import '../../platform/len_file_io.dart';
import '../../sync/sync_controller.dart';
import '../../ui/app_theme.dart';
import '../../ui/error_details.dart';
import '../documents/progress_dialog.dart';
import 'len_file_flows.dart' show lenFileTypes;
import 'restore_dialogs.dart';

/// Imports Len file [file] (picked by the user if not given) behind a
/// progress dialog. What the file is decides where it goes (UX_AUDIT
/// R8-15): a notebook or folder into the library's open folder, wherever
/// the import started; a library backup, after asking ([confirmRestore]),
/// at the top level as it was into an empty library, else into a folder
/// named after its date. Damaged parts are left out and reported (R8-14);
/// a restore offers Undo (R8-16). Returns what was imported, or null if
/// cancelled or failed (the user has then been told why). [restore]: the
/// user asked for a restore, so a file that can't be read says "Couldn’t
/// restore" (what the file is only shows once it has been read).
Future<LenImportResult?> importLenFlow(
  BuildContext context, {
  XFile? file,
  bool restore = false,
}) async {
  final services = AppScope.read(context);
  final picked = file ?? await openFile(acceptedTypeGroups: lenFileTypes);
  if (picked == null || !context.mounted) return null;
  final name = picked.name.isEmpty ? 'the file' : '“${picked.name}”';
  LenSource? source;
  var restoring = restore;
  try {
    source = await _open(context, services, picked);
    final manifest = source.manifest;
    restoring = manifest.kind == LenArchiveKind.library;
    if (!context.mounted) return null;
    final plan = restoring
        ? await _planRestore(context, services, source)
        : (parent: services.lenFiles.openFolder(), folderName: null, skip: const <String>{});
    if (plan == null || !context.mounted) {
      unawaited(source.close());
      return null;
    }
    final opened = source;
    final result = await runWithSteps(
      context,
      restoring ? 'Restoring' : 'Importing',
      subject: picked.name,
      cancellable: true,
      (progress) async {
        progress.stageStarted('Reading…');
        return services.lenFiles.import(
          opened,
          parent: plan.parent,
          folderName: plan.folderName,
          folderColor: Palette.covers[6],
          keepIds: restoring,
          skip: plan.skip,
          cancel: progress.token,
          onProgress: progress.advanced,
        );
      },
    );
    if (context.mounted) {
      final undo = restoring ? () => undoRestore(services, result) : null;
      showImported(
        context,
        result,
        folderName: plan.folderName,
        skipped: plan.skip.length,
        undo: undo,
      );
    }
    return result;
  } on Cancelled {
    return null;
  } on LenArchiveException catch (e) {
    unawaited(source?.close());
    if (context.mounted) {
      _failed(context, '${_couldnt(restoring)} $name: ${e.message}', '$e', restoring);
    }
    return null;
  } on Object catch (e, stack) {
    debugPrint('Len import failed: $e\n$stack');
    unawaited(source?.close());
    if (context.mounted) _failed(context, '${_couldnt(restoring)} $name', '$e', restoring);
    return null;
  }
}

/// Opens [picked] behind a progress dialog, so a big backup shows at once
/// (and the screen behind takes no second tap) while it is read. Cancel
/// abandons it; the file is closed once open.
Future<LenSource> _open(BuildContext context, AppServices services, XFile picked) async {
  final opening = openPickedInput(picked).then(services.lenFiles.open);
  try {
    return await runWithProgress(
      context,
      'Opening',
      () => opening,
      subject: picked.name.isEmpty ? null : picked.name,
      stage: 'Reading…',
    );
  } on Cancelled {
    unawaited(opening.then((s) => s.close(), onError: (Object _) {}));
    rethrow;
  }
}

String _couldnt(bool restoring) => restoring ? 'Couldn’t restore' : 'Couldn’t import';

/// Where a backup goes and what it leaves out, after asking; null if the
/// user cancelled.
Future<({String? parent, String? folderName, Set<String> skip})?> _planRestore(
  BuildContext context,
  AppServices services,
  LenSource source,
) async {
  final empty =
      services.notebooks.list().isEmpty &&
      services.notebooks.trashed().isEmpty &&
      services.folders.list().isEmpty;
  final present = services.lenFiles.present(source);
  final choice = await confirmRestore(
    context,
    manifest: source.manifest,
    notebooks: source.contents.notebooks.length,
    present: present.length,
    intoEmpty: empty,
    syncing: services.sync.state != SyncState.disabled,
  );
  if (choice == null) return null;
  final taken = {for (final f in services.folders.childrenOf(null)) f.name};
  return (
    parent: null,
    folderName: empty ? null : backupFolderName(source.manifest, taken: taken),
    skip: choice == RestoreChoice.skipPresent ? present.keys.toSet() : const <String>{},
  );
}

/// The folder a backup restored into a library that isn't empty goes
/// into: "Backup 13 Oct 2026", with the time when that name is [taken].
String backupFolderName(LenManifest manifest, {Set<String> taken = const {}}) {
  final at = DateTime.fromMillisecondsSinceEpoch(manifest.createdAt);
  final name = 'Backup ${formatDay(at)}';
  if (!taken.contains(name)) return name;
  String two(int n) => n.toString().padLeft(2, '0');
  return '$name, ${two(at.hour)}:${two(at.minute)}';
}

/// Takes a restore back: its notebooks go to the Trash (restorable), its
/// folders away.
void undoRestore(AppServices services, LenImportResult result) {
  services.database.transaction(() {
    for (final id in result.notebooks) {
      final notebook = services.notebooks.get(id);
      if (notebook != null && !notebook.isTrashed) services.notebooks.trash(id);
    }
    for (final id in result.folders) {
      if (services.folders.get(id) != null) services.folders.delete(id);
    }
  });
  services.lenFiles.changed();
}

void _failed(BuildContext context, String message, String details, bool restoring) => showMessage(
  context,
  message,
  action: SnackBarAction(
    label: 'Details',
    onPressed: () => unawaited(
      showErrorDetails(
        context,
        title: restoring ? 'Restore failed' : 'Import failed',
        details: details,
      ),
    ),
  ),
);
