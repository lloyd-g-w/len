import '../core/clock.dart';
import 'app_database.dart';
import 'element_repository.dart';
import 'folder_repository.dart';
import 'notebook_repository.dart';
import 'notebook_style_repository.dart';
import 'outline_repository.dart';
import 'page_repository.dart';
import 'recognised_text_repository.dart';
import 'recording_repository.dart';
import 'stroke_repository.dart';
import 'syncable.dart';
import 'template_repository.dart';
import 'versions/version_repository.dart';

/// The synced repositories over one connection, wired to each other: the
/// app's (see `AppServices`), or a worker's over its own connection to the
/// same file (pulled pages applied off the UI thread, `PullWorker`).
class Repositories {
  factory Repositories(
    AppDatabase database, {
    required String deviceId,
    Clock clock = const Clock(),
  }) {
    final strokes = StrokeRepository(database, deviceId: deviceId, clock: clock);
    final elements = ElementRepository(database, deviceId: deviceId, clock: clock);
    final recordings = RecordingRepository(database, deviceId: deviceId, clock: clock);
    final pages = PageRepository(database, deviceId: deviceId, clock: clock);
    final outline = OutlineRepository(database, deviceId: deviceId, clock: clock);
    final recognisedText = RecognisedTextRepository(database, deviceId: deviceId, clock: clock);
    return Repositories._(
      strokes: strokes,
      elements: elements,
      recordings: recordings,
      pages: pages,
      outline: outline,
      recognisedText: recognisedText,
      notebooks: NotebookRepository(
        database,
        deviceId: deviceId,
        pages: pages,
        strokes: strokes,
        elements: elements,
        recordings: recordings,
        outline: outline,
        recognisedText: recognisedText,
        clock: clock,
      ),
      folders: FolderRepository(database, deviceId: deviceId, clock: clock),
      templates: TemplateRepository(database, deviceId: deviceId, clock: clock),
      notebookStyles: NotebookStyleRepository(database, deviceId: deviceId, clock: clock),
      versions: VersionRepository(database, deviceId: deviceId, clock: clock),
    );
  }

  Repositories._({
    required this.strokes,
    required this.elements,
    required this.recordings,
    required this.pages,
    required this.outline,
    required this.recognisedText,
    required this.notebooks,
    required this.folders,
    required this.templates,
    required this.notebookStyles,
    required this.versions,
  });

  final StrokeRepository strokes;
  final ElementRepository elements;
  final RecordingRepository recordings;
  final PageRepository pages;
  final OutlineRepository outline;
  final RecognisedTextRepository recognisedText;
  final NotebookRepository notebooks;
  final FolderRepository folders;
  final TemplateRepository templates;
  final NotebookStyleRepository notebookStyles;

  /// Version history (after the content it holds, so its packs' blobs
  /// went up first).
  final VersionRepository versions;

  /// The synced stores by collection, in push order (parents first).
  late final Map<String, SyncableStore> byCollection = {
    for (final s in <SyncableStore>[
      folders,
      templates,
      notebookStyles,
      notebooks,
      pages,
      outline,
      strokes,
      elements,
      recordings,
      recognisedText,
      versions,
    ])
      s.collection: s,
  };
}
