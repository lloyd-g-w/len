import '../../app_services.dart';
import '../../data/surface_stats.dart';
import '../../domain/notebook.dart';
import 'tabs/open_notebooks.dart';

/// Where notebook [notebook] opens on this device (UX_AUDIT R16-4): the
/// view this device kept for it, unless another device wrote in it since
/// this one last left it (or it was never opened here): then a paged
/// notebook opens framed on the page written last. Write pages 14–16 on the
/// tablet, open the notebook on the laptop: it shows page 16, not the page
/// the laptop showed a week ago.
EditorViewState? resumeView(AppServices services, Notebook notebook) {
  final kept = EditorViewState.decode(services.settings.editorView(notebook.id));
  if (notebook.kind != NotebookKind.paged) return kept;
  final page = SurfaceStats(services.database).pageWrittenElsewhere(
    notebook.id,
    deviceId: services.strokes.deviceId,
    after: kept?.savedAt ?? 0,
  );
  if (page == null) return kept;
  final index = services.pages.pagesOf(notebook.id).indexWhere((p) => p.id == page);
  if (index < 0 || index == kept?.page) return kept;
  return EditorViewState.page(index, fit: kept?.fit);
}

/// When this device leaves notebook [notebookId] ([EditorViewState.savedAt]):
/// now, or the newest version of what other devices wrote in it if later.
/// Versions are the writing device's clock: one running fast must not
/// make ink already seen here look newer than this device's leaving, and
/// move the notebook to it on every open.
int leftAt(AppServices services, String notebookId) {
  final now = services.clock.nowMs();
  final newest = SurfaceStats(services.database)
      .newestElsewhere(notebookId, deviceId: services.strokes.deviceId);
  return newest > now ? newest : now;
}
