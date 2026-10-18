import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:archive/archive.dart';
import 'package:len/app_services.dart';
import 'package:len/data/archive/len_archives.dart';
import 'package:len/data/font_repository.dart';
import 'package:len/data/stroke_queries.dart';
import 'package:len/data/surface_copier.dart';
import 'package:len/data/versions/versions.dart';
import 'package:len/domain/cancellation.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/notebook_style.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/recording.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/domain/surface_element.dart';
import 'package:len/domain/text/text_data.dart';
import 'package:len/ink/selection/connectors.dart';
import 'package:len/ink/shapes/shape_anchors.dart';
import 'package:len/ink/shapes/shape_builder.dart';

part 'random_content_edits.dart';

/// Random user edits on one device, as the app makes them: notebooks,
/// pages, strokes, text boxes (chains flowing across pages included),
/// trash and deletion, folders, notebook styles, recordings in parts,
/// templates, duplicated notebooks, pages copied or moved, deleted text
/// brought back (undo), backups taken and restored (or cancelled),
/// imported fonts, version history and connectors
/// (`random_content_edits.dart`). Each edit is one of the repositories' own
/// operations.
class RandomEdits {
  RandomEdits(this.s, this.r);

  final AppServices s;
  final math.Random r;

  T _pick<T>(List<T> from) => from[r.nextInt(from.length)];

  List<String> _ids(String sql, [List<Object?> args = const []]) => [
    for (final row in s.database.db.select(sql, args)) row['id'] as String,
  ];

  /// Notebooks in the library (not trashed).
  List<String> get _notebooks =>
      _ids('SELECT id FROM notebooks WHERE deleted = 0 AND trashed_at IS NULL ORDER BY id');

  List<String> get _paged => _ids(
    "SELECT id FROM notebooks WHERE deleted = 0 AND trashed_at IS NULL AND kind = 'paged' "
    'ORDER BY id',
  );

  List<String> get _trashed =>
      _ids('SELECT id FROM notebooks WHERE deleted = 0 AND trashed_at IS NOT NULL ORDER BY id');

  List<String> _pagesOf(String notebook) => [for (final p in s.pages.pagesOf(notebook)) p.id];

  /// Pages and canvases of notebooks in the library.
  List<String> get _surfaces => [
    for (final nb in _notebooks)
      if (s.notebooks.get(nb)!.kind == NotebookKind.canvas) nb else ..._pagesOf(nb),
  ];

  List<String> get _folders => _ids('SELECT id FROM folders WHERE deleted = 0 ORDER BY id');

  List<String> get _styles => _ids('SELECT id FROM notebook_styles WHERE deleted = 0 ORDER BY id');

  List<String> get _recordings => _ids(
    'SELECT r.id FROM recordings r JOIN notebooks n ON n.id = r.notebook_id '
    'WHERE r.deleted = 0 AND n.deleted = 0 AND n.trashed_at IS NULL ORDER BY r.id',
  );

  List<SurfaceElement> _boxesOn(String surface) => [
    for (final e in s.elements.allOn(surface))
      if (e.type == ElementType.text.name) e,
  ];

  /// The last edit [any] made (for traces).
  static String lastEdit = '';

  /// Makes one random edit.
  Future<void> any() async {
    final edits = <Future<void> Function()?>[
      newNotebook,
      addPage,
      stroke,
      stroke,
      stroke,
      deleteStroke,
      deletePage,
      newTextChain,
      newTextChain,
      editText,
      deleteText,
      trash,
      restore,
      deleteForever,
      newFolder,
      moveToFolder,
      deleteFolder,
      style,
      recording,
      recording,
      template,
      rename,
      outline,
      duplicate,
      copyPages,
      undoDeleteText,
      backup,
      font,
      version,
      version,
      connector,
      connector,
    ];
    final edit = edits[r.nextInt(edits.length)]!;
    lastEdit = '$edit';
    await edit();
  }

  Future<void> newNotebook() async {
    final folders = _folders;
    final styles = _styles;
    final style = styles.isEmpty || r.nextBool() ? null : s.notebookStyles.get(_pick(styles));
    final kind =
        style?.choice.kind ?? (r.nextInt(4) == 0 ? NotebookKind.canvas : NotebookKind.paged);
    s.notebooks.create(
      title: 'n${r.nextInt(1000)}',
      kind: kind,
      paper: PaperStyle.blank,
      coverColor: style?.choice.coverColor ?? 0xFF000000 + r.nextInt(0xFFFFFF),
      folderId: folders.isEmpty || r.nextBool() ? null : _pick(folders),
    );
  }

  Future<void> addPage() async {
    final paged = _paged;
    if (paged.isEmpty) return newNotebook();
    final nb = _pick(paged);
    final pages = s.pages.pagesOf(nb);
    s.pages.addPage(nb, after: pages.isEmpty || r.nextBool() ? null : _pick(pages));
  }

  Future<void> stroke() async {
    final surfaces = _surfaces;
    if (surfaces.isEmpty) return newNotebook();
    final surface = _pick(surfaces);
    s.strokes.save([
      Stroke(
        id: s.clock.newId(),
        surfaceId: surface,
        tool: r.nextInt(5) == 0 ? InkTool.highlighter : InkTool.ballpoint,
        color: 0xFF000000 + r.nextInt(0xFFFFFF),
        width: 1.0 + r.nextInt(6),
        points: [
          for (var i = 1 + r.nextInt(40); i > 0; i--)
            StrokePoint(r.nextDouble() * 800, r.nextDouble() * 1100, r.nextDouble()),
        ],
        createdAt: s.clock.nowMs(),
      ),
    ]);
    _touch(surface);
  }

  void _touch(String surface) {
    final notebook = s.pages.notebookOf(surface) ?? surface;
    s.notebooks.touch(notebook);
  }

  Future<void> deleteStroke() async {
    final surfaces = _surfaces;
    if (surfaces.isEmpty) return;
    final surface = _pick(surfaces);
    final strokes = _ids(
      'SELECT id FROM strokes WHERE surface_id = ? AND deleted = 0 ORDER BY id',
      [surface],
    );
    if (strokes.isEmpty) return;
    s.strokes.delete([_pick(strokes)]);
    _touch(surface);
  }

  Future<void> deletePage() async {
    final paged = _paged;
    if (paged.isEmpty) return;
    final pages = _pagesOf(_pick(paged));
    if (pages.length < 2) return;
    s.notebooks.deletePage(_pick(pages));
  }

  SurfaceElement _box(String id, String surface, int createdAt, {TextFlow? flow}) => SurfaceElement(
    id: id,
    surfaceId: surface,
    type: ElementType.text.name,
    rect: Rect.fromLTWH(40, flow == null ? 60.0 + r.nextInt(400) : 40, 300, 90),
    z: r.nextInt(10).toDouble(),
    createdAt: createdAt,
    data: TextData.rich(
      text: 'text ${r.nextInt(100000)}',
      font: _textFont(),
      spacing: _pick(ParagraphSpacing.values),
    ).withFlow(flow).toJson(),
  );

  /// A text box, on a page continued on up to two pages after it.
  Future<void> newTextChain() async {
    final surfaces = _surfaces;
    if (surfaces.isEmpty) return newNotebook();
    final surface = _pick(surfaces);
    final now = s.clock.nowMs();
    final head = _box(s.clock.newId(), surface, now);
    final chain = [head];
    final notebook = s.pages.notebookOf(surface);
    if (notebook != null) {
      final pages = _pagesOf(notebook);
      final at = pages.indexOf(surface);
      for (var i = at + 1; i < pages.length && i <= at + r.nextInt(3); i++) {
        chain.add(_box(s.clock.newId(), pages[i], now, flow: TextFlow(from: chain.last.id)));
      }
    }
    s.elements.save(chain);
    _touch(surface);
  }

  /// Rewrites a text box and the boxes continuing it (as the app does: one
  /// edit, continuations keeping their ids or replaced by new ones).
  Future<void> editText() async {
    final (surface, box) = _someBox() ?? (null, null);
    if (box == null) return newTextChain();
    final chain = _chainFrom(box);
    final keep = r.nextBool();
    final saved = <SurfaceElement>[];
    for (final e in chain) {
      final flow = TextFlow.fromJson(e.data['flow']);
      final from = saved.isEmpty ? flow : TextFlow(from: saved.last.id);
      final id = keep || saved.isEmpty ? e.id : s.clock.newId();
      saved.add(_box(id, e.surfaceId, e.createdAt, flow: from).copyWith(rect: e.rect));
    }
    if (!keep) s.elements.delete([for (final e in chain.skip(1)) e.id]);
    s.elements.save(saved);
    _touch(surface!);
  }

  Future<void> deleteText() async {
    final (surface, box) = _someBox() ?? (null, null);
    if (box == null) return;
    s.elements.delete([for (final e in _chainFrom(box)) e.id]);
    _touch(surface!);
  }

  (String, SurfaceElement)? _someBox() {
    final surfaces = _surfaces..shuffle(r);
    for (final surface in surfaces.take(5)) {
      final boxes = _boxesOn(surface);
      if (boxes.isNotEmpty) return (surface, _pick(boxes));
    }
    return null;
  }

  /// [box] and the boxes continuing it on the following pages.
  List<SurfaceElement> _chainFrom(SurfaceElement box) {
    final chain = [box];
    final notebook = s.pages.notebookOf(box.surfaceId);
    if (notebook == null) return chain;
    final pages = _pagesOf(notebook);
    for (var i = pages.indexOf(box.surfaceId) + 1; i > 0 && i < pages.length; i++) {
      final next = [
        for (final e in _boxesOn(pages[i]))
          if (TextFlow.fromJson(e.data['flow'])?.from == chain.last.id) e,
      ];
      if (next.isEmpty) break;
      chain.add(next.first);
    }
    return chain;
  }

  Future<void> trash() async {
    final notebooks = _notebooks;
    if (notebooks.isNotEmpty) s.notebooks.trash(_pick(notebooks));
  }

  Future<void> restore() async {
    final trashed = _trashed;
    if (trashed.isNotEmpty) s.notebooks.restore(_pick(trashed));
  }

  Future<void> deleteForever() async {
    final trashed = _trashed;
    if (trashed.isNotEmpty) s.notebooks.delete(_pick(trashed));
  }

  Future<void> newFolder() async {
    final folders = _folders;
    s.folders.create(
      name: 'f${r.nextInt(1000)}',
      parentId: folders.isEmpty || r.nextBool() ? null : _pick(folders),
      color: r.nextInt(8),
    );
  }

  Future<void> moveToFolder() async {
    final notebooks = _notebooks, folders = _folders;
    if (notebooks.isEmpty) return;
    if (folders.isNotEmpty && r.nextInt(3) == 0) {
      final folder = _pick(folders);
      final parent = r.nextBool() ? null : _pick(folders);
      if (s.folders.canMove(folder, parent)) s.folders.move(folder, parent);
      return;
    }
    s.notebooks.moveTo(
      _pick(notebooks),
      folders.isEmpty || r.nextInt(4) == 0 ? null : _pick(folders),
    );
  }

  Future<void> deleteFolder() async {
    final folders = _folders;
    if (folders.isEmpty) return newFolder();
    s.notebooks.trashAllIn(s.folders.delete(_pick(folders)));
  }

  Future<void> style() async {
    final styles = _styles;
    switch (styles.isEmpty ? 0 : r.nextInt(4)) {
      case 0:
        s.notebookStyles.create(
          name: 's${r.nextInt(1000)}',
          choice: NotebookChoice(
            kind: r.nextBool() ? NotebookKind.paged : NotebookKind.canvas,
            coverColor: 0xFF000000 + r.nextInt(0xFFFFFF),
          ),
        );
      case 1:
        s.notebookStyles.setDefault(_pick(styles), isDefault: r.nextInt(4) != 0);
      case 2:
        s.notebookStyles.rename(_pick(styles), 's${r.nextInt(1000)}');
      default:
        s.notebookStyles.delete(_pick(styles));
    }
  }

  Future<String> _blob(String mime) {
    final bytes = Uint8List.fromList([
      for (var i = 16 + r.nextInt(2000); i > 0; i--) r.nextInt(256),
    ]);
    return s.blobs.putBytes(bytes, mime: mime);
  }

  /// A new recording, a part added to one being made, or a rename, trim or
  /// deletion.
  Future<void> recording() async {
    final recordings = _recordings;
    if (recordings.isEmpty || r.nextInt(3) == 0) {
      final notebooks = _notebooks;
      if (notebooks.isEmpty) return newNotebook();
      final blob = await _blob('audio/aac');
      final now = s.clock.nowMs();
      s.recordings.save(
        notebookId: _pick(notebooks),
        parts: [RecordingPart(blob, 1000 + r.nextInt(5000))],
        mime: 'audio/aac',
        title: 'r${r.nextInt(100)}',
        segments: [RecordingSegment(now, 1000)],
      );
      return;
    }
    final id = _pick(recordings);
    final current = s.recordings.get(id)!;
    switch (r.nextInt(4)) {
      case 0 || 1:
        final blob = await _blob('audio/aac');
        final parts = [...current.parts, RecordingPart(blob, 1000 + r.nextInt(5000))];
        s.recordings.save(
          id: id,
          notebookId: current.notebookId,
          parts: parts,
          mime: current.mime,
          title: current.title,
          segments: [
            RecordingSegment(current.startedAt, parts.fold(0, (sum, p) => sum + p.durationMs)),
          ],
        );
      case 2:
        if (r.nextBool()) {
          s.recordings.rename(id, 'r${r.nextInt(100)}');
        } else {
          s.recordings.trim(id, 0, current.durationMs ~/ 2);
        }
      default:
        s.recordings.delete(id);
    }
  }

  /// An outline entry added, renamed or deleted.
  Future<void> outline() async {
    final paged = _paged;
    if (paged.isEmpty) return newNotebook();
    final nb = _pick(paged);
    final entries = s.outline.entriesOf(nb);
    final pages = _pagesOf(nb);
    if (entries.isEmpty || r.nextBool()) {
      if (pages.isEmpty) return;
      s.outline.add(
        notebookId: nb,
        pageId: _pick(pages),
        title: 'o${r.nextInt(100)}',
        parentId: entries.isEmpty || r.nextBool() ? null : _pick(entries).id,
      );
    } else if (r.nextBool()) {
      s.outline.update(_pick(entries).copyWith(title: 'o${r.nextInt(100)}'));
    } else {
      s.outline.delete(_pick(entries).id);
    }
    _touch(nb);
  }

  /// A notebook duplicated (with its pages, content, recordings and outline).
  Future<void> duplicate() async {
    final notebooks = _notebooks;
    if (notebooks.isEmpty) return newNotebook();
    s.notebooks.duplicate(_pick(notebooks));
  }

  /// Some pages copied to the end of another notebook, sometimes deleted
  /// here after (a move).
  Future<void> copyPages() async {
    final paged = _paged;
    if (paged.length < 2) return newNotebook();
    final from = _pick(paged);
    final to = _pick([
      for (final n in paged)
        if (n != from) n,
    ]);
    final pages = _pagesOf(from)..shuffle(r);
    if (pages.isEmpty) return;
    final moved = pages.take(1 + r.nextInt(pages.length)).toList();
    s.notebooks.copyPages(from, moved, to);
    if (r.nextBool() && moved.length < pages.length) {
      for (final page in moved) {
        s.notebooks.deletePage(page);
      }
    }
    _touch(to);
  }

  /// A deleted text box brought back as it was (undo), if its page is live.
  Future<void> undoDeleteText() async {
    final rows = s.database.db.select(
      "SELECT * FROM elements WHERE deleted = 1 AND type = 'text' AND data <> '{}' ORDER BY id",
    );
    final surfaces = _surfaces.toSet();
    final boxes = [
      for (final row in rows)
        if (surfaces.contains(row['surface_id'])) ?StrokeQueries.rowToElement(row),
    ];
    if (boxes.isEmpty) return;
    final box = _pick(boxes);
    s.elements.save([box]);
    _touch(box.surfaceId);
  }

  /// Font files imported so far (devices import some of them again).
  static final List<Uint8List> fontFiles = [];

  /// Backups each device took, by device id ([backup] restores them).
  static final Map<String, Uint8List> backups = {};

  /// A backup of the library taken, or the last one restored (keeping ids:
  /// notebooks deleted since come back under their own), sometimes
  /// cancelled half way.
  Future<void> backup() async {
    final device = s.notebooks.deviceId;
    final saved = backups[device];
    if (saved == null || r.nextInt(3) == 0) {
      final out = OutputMemoryStream();
      await s.lenFiles.write(const LenScope.library(), out);
      backups[device] = out.getBytes();
      return;
    }
    final present = s.lenFiles.present(await s.lenFiles.open(InputMemoryStream(saved)));
    final cancel = CancellationToken();
    final cancelAt = r.nextInt(3) == 0 ? r.nextDouble() : null;
    try {
      await s.lenFiles.import(
        await s.lenFiles.open(InputMemoryStream(saved)),
        keepIds: true,
        skip: present.keys.toSet(),
        folderName: r.nextBool() ? 'Backup' : null,
        cancel: cancel,
        onProgress: (done) {
          if (cancelAt != null && done >= cancelAt) cancel.cancel();
        },
      );
    } on Cancelled {
      // Nothing restored.
    }
  }

  Future<void> template() async {
    final templates = _ids('SELECT id FROM templates WHERE deleted = 0 ORDER BY id');
    if (templates.isNotEmpty && r.nextInt(3) == 0) {
      s.templates.delete(_pick(templates));
      return;
    }
    final blob = await _blob('image/png');
    s.templates.create(name: 't${r.nextInt(100)}', blob: blob, size: const Size(600, 800));
  }

  Future<void> rename() async {
    final notebooks = _notebooks;
    if (notebooks.isEmpty) return newNotebook();
    final n = s.notebooks.get(_pick(notebooks))!;
    if (r.nextBool()) {
      s.notebooks.update(n.copyWith(title: 't${r.nextInt(1000)}'));
    } else {
      s.notebooks.setFavorite(n.id, !n.favorite);
    }
  }
}
