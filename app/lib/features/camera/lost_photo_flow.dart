import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';

import '../../app_services.dart';
import '../../domain/notebook.dart';
import '../../ui/messages.dart';
import '../documents/import/import_targets.dart';
import 'camera.dart';
import 'camera_purpose.dart';

/// What the library lends [resumeLostPhoto].
class LostPhotoHost {
  const LostPhotoHost({required this.scanNew, required this.show, required this.importFiles});

  /// Scans pages starting with these photos into a new notebook (which
  /// then opens).
  final Future<void> Function(List<XFile> photos) scanNew;

  /// Shows a notebook in the editor (in a tab if an editor is up).
  final void Function(Notebook notebook) show;

  /// Takes photos as if shared to Len: into the shown editor (asked) or
  /// a new notebook.
  final Future<void> Function(List<XFile> photos) importFiles;
}

/// At startup: if Android killed Len while the camera app was in front
/// and a photo came back ([Camera.retrieveLost]), carries on with what
/// the camera was opened for — the scan screen with the photo (in the
/// notebook it was scanning into, opened first), or the photo inserted
/// where it was meant to go. A scan whose notebook is gone becomes a new
/// notebook; a photo whose notebook is gone is taken like a shared image.
Future<void> resumeLostPhoto(BuildContext context, AppServices services, LostPhotoHost host) async {
  final lost = await services.camera.retrieveLost();
  if (lost == null || !context.mounted) return;
  showMessage(context, 'Recovered the photo you took');
  final photo = lost.photo;
  switch (lost.purpose) {
    case ScanNewNotebook():
      await host.scanNew([photo]);
    case ScanIntoNotebook(:final notebookId, :final afterPageId):
      final editor = await _editorOf(services, host, notebookId, paged: true);
      if (editor != null && await editor.resumeScan(photo, afterPageId: afterPageId)) return;
      if (context.mounted) await host.scanNew([photo]);
    case PhotoOnSurface(:final notebookId, :final surfaceId, :final at):
      final editor = await _editorOf(services, host, notebookId);
      if (editor != null) return editor.insertPhoto(photo, surfaceId: surfaceId, at: at);
      if (context.mounted) await host.importFiles([photo]);
    case null:
      await host.importFiles([photo]);
  }
}

/// The editor of notebook [id], shown first; null if the notebook is gone
/// (or trashed, or not [paged] when asked) or its editor didn't come up.
Future<ImportTarget?> _editorOf(
  AppServices services,
  LostPhotoHost host,
  String id, {
  bool paged = false,
}) async {
  final notebook = services.notebooks.get(id);
  if (notebook == null || notebook.isTrashed) return null;
  if (paged && notebook.kind != NotebookKind.paged) return null;
  final targets = services.incomingFiles.targets;
  if (targets.active?.notebookId != id) host.show(notebook);
  return targets.waitFor(id);
}
