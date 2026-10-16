import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:len/app_services.dart';
import 'package:len/core/clock.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/recording.dart';
import 'package:len/features/editor/tabs/editor_view_state.dart';

import 'big_library.dart';

/// What [StartupLibrary.build] made.
class StartupLibrary {
  StartupLibrary._(this.library, this.lectures);

  final BigLibrary library;

  /// The 500-page notebook of handwriting, open in the kept workspace.
  final Notebook lectures;

  /// The page the workspace was left at.
  static const int lecturePage = 250;

  /// Fills [s] with the library a launch is measured on: [notebookCount]
  /// notebooks (as [BigLibrary.build]: folders, favourites, a trash, PDF
  /// notebooks, a page of handwriting on each cover), a notebook of
  /// [lecturePages] pages of handwriting with three recordings, a
  /// recording on every tenth notebook, and the workspace left in the
  /// big notebook at [lecturePage] with a second tab open (so a launch
  /// restores it).
  static StartupLibrary build(
    AppServices s,
    Clock clock, {
    int notebookCount = 300,
    int lecturePages = 500,
  }) {
    final library = BigLibrary.build(
      s,
      clock,
      folderCount: 20,
      notebookCount: notebookCount,
      trashCount: 20,
      coverLines: 20,
    );
    final lectures = s.notebooks.create(
      title: 'Lectures',
      kind: NotebookKind.paged,
      paper: PaperStyle.collegeRuled,
      coverColor: 0,
    );
    s.database.transaction(() {
      s.pages.insertPages(lectures.id, [
        for (var i = 1; i < lecturePages; i++)
          (
            size: const Size(595, 842),
            paper: Paper(PaperStyle.collegeRuled),
            color: PaperColor.white,
            background: null,
          ),
      ]);
      var seed = 0;
      for (final p in s.pages.pagesOf(lectures.id)) {
        s.strokes.save(pageOfInk(p.id, clock, lines: 20, seed: seed++));
      }
      var r = 0;
      for (final n in [
        lectures,
        lectures,
        lectures,
        ...library.notebooks.where((_) => r++ % 10 == 0),
      ]) {
        final at = clock.nowMs();
        s.recordings.save(
          notebookId: n.id,
          parts: [RecordingPart((r++).toRadixString(16).padLeft(64, '0'), 60 * 60000)],
          mime: 'audio/mp4',
          title: 'Recording $r',
          segments: [RecordingSegment(at, 60 * 60000)],
          waveform: 'A' * 2400,
        );
      }
    });
    final second = library.notebooks[3];
    s.settings
      ..recentNotebooks = [lectures.id, second.id, for (final n in library.notebooks.take(10)) n.id]
      ..setEditorView(lectures.id, const EditorViewState.page(lecturePage).encode())
      ..workspace = jsonEncode({
        'tabs': [second.id, lectures.id],
        'active': lectures.id,
      });
    return StartupLibrary._(library, lectures);
  }

  /// Writes the install marker next to the database at [dbPath] (the app
  /// otherwise takes the data for a restored backup and a new device id).
  static void writeMarker(AppServices s, String dbPath) =>
      File('${File(dbPath).parent.path}/install-marker').writeAsStringSync(s.settings.deviceId());
}
