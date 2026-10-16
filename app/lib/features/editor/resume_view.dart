import '../../app_services.dart';
import '../../data/surface_stats.dart';
import '../../domain/notebook.dart';
import '../../platform/background_query.dart';
import 'tabs/open_notebooks.dart';

/// Where notebook [notebook] opens on this device at once: the view this
/// device kept for it. (Then [writtenElsewhere] may move it on.)
EditorViewState? keptView(AppServices services, Notebook notebook) =>
    EditorViewState.decode(services.settings.editorView(notebook.id));

/// The page (id) of paged notebook [notebook] it should move on to from [kept]
/// ([keptView]) as it opens (UX_AUDIT R16-4), or null: if another device
/// wrote in it since this one last left it (or it was never opened here),
/// the page written last. Write pages 14–16 on the tablet, open the
/// notebook on the laptop: it shows page 16, not the page the laptop showed
/// a week ago. Asked off the UI thread (it reads every stroke of the
/// notebook), so the editor opens on [kept] meanwhile.
Future<String?> writtenElsewhere(AppServices services, Notebook notebook, EditorViewState? kept) {
  final id = notebook.id;
  final deviceId = services.strokes.deviceId;
  final after = kept?.savedAt ?? 0;
  return queryInBackground(
    services.database,
    (db) => SurfaceStats(db).pageWrittenElsewhere(id, deviceId: deviceId, after: after),
  );
}

/// When this device leaves notebook [notebookId] ([EditorViewState.savedAt]),
/// as a version: the newest of what other devices wrote in it that is here
/// (0 if nothing). Versions are the writing devices' clocks, not this
/// one's: ink already seen never looks newer (a device whose clock runs
/// fast), and what a device whose clock runs slow writes later still does.
int leftAt(AppServices services, String notebookId) =>
    SurfaceStats(services.database)
        .newestElsewhere(notebookId, deviceId: services.strokes.deviceId);
