import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../data/archive/len_archives.dart';
import '../../ui/app_dialogs.dart';
import '../../ui/error_details.dart';
import '../../ui/messages.dart';

/// How to restore a backup whose notebooks are partly here already.
enum RestoreChoice {
  /// Everything, as copies where a notebook is here already.
  all,

  /// Leave out the notebooks that are here already.
  skipPresent,
}

/// Asks before restoring the backup of [manifest] (UX_AUDIT R8-16): what
/// it holds, where it goes, that nothing is replaced, that it syncs, and
/// whether to skip the [present] notebooks already here. Null if
/// cancelled.
Future<RestoreChoice?> confirmRestore(
  BuildContext context, {
  required LenManifest manifest,
  required int notebooks,
  required int present,
  required bool intoEmpty,
  required bool syncing,
}) => showDialog<RestoreChoice>(
  context: context,
  builder: (context) => AppDialog(
    title: 'Restore this backup?',
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: dialogFormWidth),
      child: Text(
        restoreQuestion(
          manifest: manifest,
          notebooks: notebooks,
          present: present,
          intoEmpty: intoEmpty,
          syncing: syncing,
        ),
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      if (present > 0) ...[
        TextButton(
          onPressed: () => Navigator.pop(context, RestoreChoice.all),
          child: const Text('Restore all'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, RestoreChoice.skipPresent),
          child: const Text('Skip those'),
        ),
      ] else
        FilledButton(
          onPressed: () => Navigator.pop(context, RestoreChoice.all),
          child: const Text('Restore'),
        ),
    ],
  ),
);

/// The body of [confirmRestore].
@visibleForTesting
String restoreQuestion({
  required LenManifest manifest,
  required int notebooks,
  required int present,
  required bool intoEmpty,
  required bool syncing,
}) {
  final at = DateTime.fromMillisecondsSinceEpoch(manifest.createdAt);
  final count = notebooks == 1 ? '1 notebook' : '$notebooks notebooks';
  String two(int n) => n.toString().padLeft(2, '0');
  return [
    'The backup from ${formatDay(at)}, ${two(at.hour)}:${two(at.minute)} holds $count.',
    if (intoEmpty)
      'They come back as they were.'
    else
      'They are added in a folder of their own; nothing here is replaced.',
    if (present > 0)
      '${present == 1 ? '1 of them is' : '$present of them are'} here already: '
          'skip those, or restore them again as copies?',
    if (syncing) 'Everything restored syncs to your other devices too.',
  ].join(' ');
}

/// Says what [result] brought in (UX_AUDIT R8-14): a message when nothing
/// was left out, else a dialog with what was and its details. A restore
/// went into [folderName] (if given) and offers [undo]; [skipped]
/// notebooks were left out as here already.
void showImported(
  BuildContext context,
  LenImportResult result, {
  String? folderName,
  int skipped = 0,
  VoidCallback? undo,
}) {
  final message = importedMessage(result, folderName: folderName, skipped: skipped);
  if (result.complete) {
    showMessage(
      context,
      message,
      action: undo == null ? null : SnackBarAction(label: 'Undo', onPressed: undo),
    );
    return;
  }
  unawaited(
    showDialog<void>(
      context: context,
      builder: (context) => AppDialog(
        title: result.manifest.kind == LenArchiveKind.library
            ? 'Restored, with gaps'
            : 'Imported, with gaps',
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: dialogFormWidth),
          child: Text('$message. ${gapsMessage(result)}'),
        ),
        actions: [
          if (result.problems.isNotEmpty)
            ErrorDetailsButton(title: 'What was damaged', details: result.problems.join('\n')),
          if (undo != null)
            TextButton(
              onPressed: () {
                undo();
                Navigator.pop(context);
              },
              child: const Text('Undo restore'),
            ),
          FilledButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    ),
  );
}

/// "Restored your backup into “Backup 13 Oct 2026”" (its [folderName]),
/// "Imported “Lecture”", with notebooks [skipped] as here already.
@visibleForTesting
String importedMessage(LenImportResult result, {String? folderName, int skipped = 0}) {
  final manifest = result.manifest;
  final what = switch (manifest.kind) {
    LenArchiveKind.notebook => 'Imported “${manifest.title}”',
    LenArchiveKind.folder => 'Imported the folder “${manifest.title}”',
    LenArchiveKind.notebooks => switch (result.notebooks.length) {
      1 => 'Imported 1 notebook',
      final n => 'Imported $n notebooks',
    },
    LenArchiveKind.library =>
      folderName == null || result.folder == null
          ? 'Restored your backup'
          : 'Restored your backup into “$folderName”',
  };
  if (skipped == 0) return what;
  return '$what; ${skipped == 1 ? '1 notebook was' : '$skipped notebooks were'} here already';
}

/// What a Len file lacked or held damaged: "2 files (PDFs, images or
/// recordings) were missing or damaged and 3 items couldn’t be read: they
/// are left out".
@visibleForTesting
String gapsMessage(LenImportResult result) {
  final missing = result.missingBlobs, skipped = result.skipped;
  final parts = [
    if (missing == 1) '1 file (a PDF, image or recording) was missing or damaged',
    if (missing > 1) '$missing files (PDFs, images or recordings) were missing or damaged',
    if (skipped > 0) '${skipped == 1 ? '1 item' : '$skipped items'} couldn’t be read',
    if (result.lostParts > 0) 'part of the handwriting and text couldn’t be read',
  ];
  final listed = parts.length == 1
      ? parts.single
      : '${parts.sublist(0, parts.length - 1).join(', ')} and ${parts.last}';
  return '${listed[0].toUpperCase()}${listed.substring(1)}: '
      '${parts.length == 1 && skipped + missing == 1 ? 'it is' : 'they are'} left out.';
}
