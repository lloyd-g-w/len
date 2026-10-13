import 'dart:async';

import 'package:flutter/material.dart';

import '../../../platform/file_export.dart' as platform;
import '../../../ui/error_details.dart';
import '../../../ui/messages.dart';

/// "Saved “Lecture.pdf”" (with Show in folder on desktops), "Saved 3
/// images to “Exports”", "Shared “Lecture.pdf”", "Downloaded 3 images":
/// where exported [files] went. [plural] names several ("images"); [note]
/// adds what was left out ("· 2 images couldn't be included").
void showExported(
  BuildContext context,
  platform.ExportedFiles files, {
  required String plural,
  String? note,
}) {
  final what = files.count == 1 && files.name != null
      ? '“${files.name}”'
      : '${files.count} $plural';
  final message = switch (files.to) {
    platform.ExportedTo.file || platform.ExportedTo.device => 'Saved $what',
    platform.ExportedTo.folder =>
      files.name == null ? 'Saved $what' : 'Saved ${files.count} $plural to “${files.name}”',
    platform.ExportedTo.shared => 'Shared $what',
    platform.ExportedTo.downloaded => 'Downloaded $what',
  };
  final path = files.path;
  showMessage(
    context,
    note == null ? message : '$message · $note',
    duration: note == null ? null : const Duration(seconds: 8),
    action: path == null || !platform.canShowInFolder
        ? null
        : SnackBarAction(
            label: 'Show in folder',
            onPressed: () => unawaited(platform.showInFolder(path)),
          ),
  );
}

/// "Couldn't export “Lecture.pdf”", with the error under Details (the
/// raw text never goes in the message).
void showExportFailed(BuildContext context, String subject, Object error) => showMessage(
  context,
  'Couldn’t export $subject',
  action: SnackBarAction(
    label: 'Details',
    onPressed: () =>
        unawaited(showErrorDetails(context, title: 'Export failed', details: '$error')),
  ),
);
