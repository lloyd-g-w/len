import 'dart:ui';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/archive/len_scope.dart';
import 'package:len/data/blob_backend.dart';
import 'package:len/data/surface_copier.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/ink/shapes/shape_builder.dart';

// Copies of pages and notebooks (duplicate, send to another notebook, Len
// files) keep their connectors: each copied arrow attaches to the copy of
// its box, the copied shapes being shapes of their own.

AppServices _services() {
  final s = AppServices.create(AppDatabase.inMemory(), blobBackend: MemoryBlobBackend());
  addTearDown(s.dispose);
  return s;
}

Stroke _shape(String id, String surface, ShapeGeometry shape) => Stroke(
  id: id,
  surfaceId: surface,
  tool: InkTool.ballpoint,
  color: 0xFF1C7ED6,
  width: 2,
  points: ShapeBuilder.pointsOf(shape),
  createdAt: 1,
  style: ShapeBuilder.styleFor(const StrokeStyle(unit: 1)),
  shape: shape,
);

final _box = ShapeBuilder.dragged(
  ShapeKind.rectangle,
  const Offset(300, 200),
  const Offset(400, 300),
);

/// A notebook whose first page holds an edited box (stroke `box2`, shape
/// `box`), a box never edited (`plain`) and an arrow from `plain` to
/// `box`, and a line attached to a shape not on the page.
({Notebook notebook, String page}) _notebook(AppServices s) {
  final n = s.notebooks.create(
    title: 'Diagram',
    kind: NotebookKind.paged,
    paper: PaperStyle.blank,
    coverColor: 0xFF3B5BDB,
  );
  final page = s.pages.pagesOf(n.id).single.id;
  s.strokes.save([
    _shape('box2', page, _box.withOrigin('box')),
    _shape('plain', page, _box.map((p) => p - const Offset(250, 0))),
    _shape(
      'arrow',
      page,
      ShapeGeometry(
        ShapeKind.arrow,
        const [Offset(150, 250), Offset(300, 250)],
        tail: const ShapeAttachment('plain', 0.375),
        tip: const ShapeAttachment('box', 0.875),
      ),
    ),
    _shape(
      'stray',
      page,
      ShapeGeometry(ShapeKind.line, const [
        Offset(0, 0),
        Offset(10, 0),
      ], tip: const ShapeAttachment('elsewhere', 0)),
    ),
  ]);
  return (notebook: n, page: page);
}

/// Checks the copy of [_notebook]'s page on [surface].
/// With [fresh], they are new strokes and shapes.
void _expectCopied(AppServices s, String surface, {bool fresh = true}) {
  final strokes = SurfaceCopier(s.strokes).loadAll(surface);
  expect(strokes, hasLength(4));
  Stroke kind(ShapeKind k, {bool left = false}) => strokes.firstWhere(
    (x) => x.shape!.kind == k && (k != ShapeKind.rectangle || (x.bounds.left < 200) == left),
  );
  final box = kind(ShapeKind.rectangle), plain = kind(ShapeKind.rectangle, left: true);
  final arrow = kind(ShapeKind.arrow), stray = kind(ShapeKind.line);
  final names = {'box', 'box2', 'plain', 'arrow', 'stray', 'elsewhere'};
  if (fresh) {
    for (final x in strokes) {
      expect(names.contains(x.id), isFalse, reason: 'a copy has an id of its own');
    }
    expect(names.contains(box.shapeId), isFalse, reason: 'and is a shape of its own');
    expect(names.contains(plain.shapeId), isFalse);
  }
  expect(arrow.shape!.tail!.id, plain.shapeId);
  expect(arrow.shape!.tip!.id, box.shapeId);
  expect(arrow.shape!.tip!.at, 0.875);
  // Attached to nothing on the page, in the copy as in the original.
  expect(strokes.where((x) => x.shapeId == stray.shape!.tip!.id), isEmpty);
}

void main() {
  test('a duplicated page', () {
    final s = _services();
    final (:notebook, :page) = _notebook(s);
    final copy = s.pages.insertPages(notebook.id, [
      (
        size: const Size(600, 800),
        paper: Paper(PaperStyle.blank),
        color: PaperColor.white,
        background: null,
      ),
    ]).single;
    SurfaceCopier(s.strokes, elements: s.elements).copy(from: page, to: copy.id);
    _expectCopied(s, copy.id);
  });

  test('a duplicated notebook', () {
    final s = _services();
    final (:notebook, page: _) = _notebook(s);
    final copy = s.notebooks.duplicate(notebook.id)!;
    _expectCopied(s, s.pages.pagesOf(copy.id).single.id);
  });

  test('pages sent to another notebook', () {
    final s = _services();
    final (:notebook, :page) = _notebook(s);
    final other = s.notebooks.create(
      title: 'Other',
      kind: NotebookKind.paged,
      paper: PaperStyle.blank,
      coverColor: 0xFF3B5BDB,
    );
    final copied = s.notebooks.copyPages(notebook.id, [page], other.id);
    _expectCopied(s, copied.pages.single);
  });

  test('a Len file imported (a copy) and restored (ids kept)', () async {
    final source = _services();
    final (:notebook, page: _) = _notebook(source);
    final out = OutputMemoryStream();
    await source.lenFiles.write(LenScope.notebook(notebook.id), out);
    final bytes = out.getBytes();

    final target = _services();
    final imported = await target.lenFiles.import(
      await target.lenFiles.open(InputMemoryStream(bytes)),
    );
    _expectCopied(target, target.pages.pagesOf(imported.notebooks.single).single.id);

    final restored = _services();
    final kept = await restored.lenFiles.import(
      await restored.lenFiles.open(InputMemoryStream(bytes)),
      keepIds: true,
    );
    // Whether its strokes keep their ids or not, the arrow attaches to the box.
    _expectCopied(restored, restored.pages.pagesOf(kept.notebooks.single).single.id, fresh: false);
  });
}
