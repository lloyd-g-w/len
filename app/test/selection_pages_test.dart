import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/element_repository.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/data/surface_copier.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/features/editor/document/page_models.dart';
import 'package:len/ink/selection/ink_clipboard.dart';
import 'package:len/ink/selection/lasso.dart';
import 'package:len/ink/selection/lasso_config.dart';
import 'package:len/ink/selection/selection_controller.dart';
import 'package:len/ink/selection/selection_surfaces.dart';
import 'package:len/ink/surface_model.dart';
import 'package:len/ink/undo_history.dart';

import 'data_test.dart' show FakeClock;
import 'elements_test.dart' show textBox;

/// Two 100×100 pages stacked with a 20 unit gap: page a at (0, 0), page b
/// at (0, 120) in document space.
class _TwoPages implements SelectionSurfaces {
  _TwoPages(this.a, this.b, this.models);

  final SurfaceModel a, b;
  final PageModels models;

  static const _frames = {'a': Rect.fromLTWH(0, 0, 100, 100), 'b': Rect.fromLTWH(0, 120, 100, 100)};

  SurfaceModel _model(String id) => id == 'a' ? a : b;

  ShiftedSurface _seen(SurfaceModel from, String id) =>
      (model: _model(id), shift: _frames[id]!.topLeft - _frames[from.surfaceId]!.topLeft);

  @override
  Iterable<ShiftedSurface> near(SurfaceModel from, Rect area) {
    final doc = area.shift(_frames[from.surfaceId]!.topLeft);
    return [
      for (final id in _frames.keys)
        if (id != from.surfaceId && _frames[id]!.overlaps(doc)) _seen(from, id),
    ];
  }

  @override
  ShiftedSurface? at(SurfaceModel from, Offset point) {
    final doc = point + _frames[from.surfaceId]!.topLeft;
    for (final id in _frames.keys) {
      if (_frames[id]!.contains(doc)) return _seen(from, id);
    }
    return null;
  }

  @override
  void batch(void Function() edits) => models.group(edits);
}

Stroke dash(String id, String surface, Offset at) => Stroke(
  id: id,
  surfaceId: surface,
  tool: InkTool.ballpoint,
  color: 0xFF000000,
  width: 2,
  points: [for (var i = 0; i < 10; i++) StrokePoint(at.dx + i * 2, at.dy, 0.5)],
  createdAt: 1,
);

void main() {
  late AppDatabase db;
  late PageModels models;
  late SurfaceModel a, b;
  late SelectionController selection;
  late SurfaceCopier stored;

  setUp(() {
    db = AppDatabase.inMemory();
    final clock = FakeClock();
    final strokes = StrokeRepository(db, deviceId: 'd', clock: clock);
    final elements = ElementRepository(db, deviceId: 'd', clock: clock);
    stored = SurfaceCopier(strokes, elements: elements);
    SurfaceModel pageModel(String id) =>
        SurfaceModel(surfaceId: id, repository: strokes, elementRepository: elements, clock: clock);
    // Page a: ink near its bottom; page b: ink and a text box near its top.
    strokes.save([dash('sa', 'a', const Offset(40, 90)), dash('sb', 'b', const Offset(40, 10))]);
    elements.save([textBox('t', const Offset(10, 20), surface: 'b', width: 40)]);
    models = PageModels();
    const page = Rect.fromLTWH(0, 0, 100, 100);
    a = models.acquire('a', () => pageModel('a'))..ensureLoaded(page);
    b = models.acquire('b', () => pageModel('b'))..ensureLoaded(page);
    selection = SelectionController(model: a, clipboard: InkClipboard(), clock: clock)
      ..surfaces = _TwoPages(a, b, models);
  });

  tearDown(() {
    selection.dispose();
    models.dispose();
    db.close();
  });

  /// A lasso on page a's coordinates reaching from y 80 on page a to y 80
  /// on page b (document y 200).
  final acrossGap = Lasso(const [Offset(0, 80), Offset(100, 80), Offset(100, 200), Offset(0, 200)]);

  test('a lasso moved into another page\'s coordinates', () {
    final shifted = acrossGap.shifted(const Offset(0, -120));
    expect(shifted.bounds, const Rect.fromLTRB(0, -40, 100, 80));
    expect(shifted.contains(const Offset(50, 20)), isTrue);
  });

  test('a lasso across the page gap selects on both pages', () {
    selection.selectLasso(acrossGap);
    expect(selection.strokes.map((s) => s.id), unorderedEquals(['sa', 'sb']));
    expect(selection.elements.single.id, 't');
    expect(selection.spansSurfaces, isTrue);
    // Page b's items are shown in page a's coordinates.
    final sb = selection.strokes.firstWhere((s) => s.id == 'sb');
    expect(sb.points.first.offset, const Offset(40, 130));
    expect(selection.elements.single.rect.top, 140);
    expect(a.isHidden('sa') && b.isHidden('sb') && b.isHidden('t'), isTrue);
    selection.clear();
    expect(b.isHidden('sb') || b.isHidden('t'), isFalse);
  });

  test('the lasso options apply on every page it reaches', () {
    Lasso across(LassoConfig config) => Lasso(acrossGap.points, config: config);
    selection.selectLasso(across(const LassoConfig(kinds: {LassoKind.text})));
    expect(selection.strokes, isEmpty);
    expect(selection.elements.single.id, 't');
    // From page a's y 89 to page b's y 35: both dashes lie wholly inside,
    // the box (page b's y 20 to 50) does not.
    selection.selectLasso(
      Lasso(const [
        Offset(0, 89),
        Offset(100, 89),
        Offset(100, 155),
        Offset(0, 155),
      ], config: const LassoConfig(cover: LassoCover.whole)),
    );
    expect(selection.strokes.map((s) => s.id), unorderedEquals(['sa', 'sb']));
    expect(selection.elements, isEmpty, reason: 'the box reaches past the lasso');
    selection.selectLasso(
      Lasso(const [
        Offset(0, 155),
        Offset(100, 155),
        Offset(100, 200),
        Offset(0, 200),
      ], config: const LassoConfig(cover: LassoCover.touching)),
    );
    expect(selection.strokes, isEmpty);
    expect(selection.elements.single.id, 't', reason: 'the lasso crosses the box on page b');
  });

  test('moving a two-page selection is one undo step; items stay on their pages', () {
    selection.selectLasso(acrossGap);
    final move = selection.frame!.moved(const Offset(5, 0));
    selection
      ..setPreview(move.transform, move.frame)
      ..commitPreview();
    expect(a.strokeById('sa'), isNull);
    expect(stored.loadAll('a').single.points.first.offset, const Offset(45, 90));
    expect(stored.loadAll('b').single.points.first.offset, const Offset(45, 10));
    expect(b.elementById('t')!.rect.left, 15);
    expect(selection.strokes, hasLength(2)); // Still selected.

    expect(models.canUndo, isTrue);
    models.undo();
    expect(a.strokeById('sa'), isNotNull);
    expect(b.strokeById('sb'), isNotNull);
    expect(b.elementById('t')!.rect.left, 10);
    expect(models.canUndo, isFalse);
    models.redo();
    expect(b.elementById('t')!.rect.left, 15);
    expect(stored.loadAll('a').single.points.first.offset, const Offset(45, 90));
  });

  test('dropping items onto the next page moves them there, converted into its space', () {
    // Text box on page a, moved with the ink down by 60: centres land on b.
    a.commit(
      InkEdit(addedElements: [textBox('ta', const Offset(10, 70), surface: 'a', width: 40)]),
    );
    selection.select([a.strokeById('sa')!], [a.elementById('ta')!]);
    final move = selection.frame!.moved(const Offset(0, 60));
    selection
      ..setPreview(move.transform, move.frame)
      ..commitPreview();
    expect(stored.loadAll('a'), isEmpty);
    expect(stored.loadAllElements('a'), isEmpty);
    // Page a y 90 + 60 = document 150 = page b y 30.
    final moved = stored.loadAll('b').firstWhere((s) => s.id != 'sb');
    expect(moved.surfaceId, 'b');
    expect(moved.points.first.offset, const Offset(40, 30));
    final ta = stored.loadAllElements('b').firstWhere((e) => e.id == 'ta'); // Same id.
    expect(ta.surfaceId, 'b');
    expect(ta.rect.top, 10);
    expect(b.elementById('ta'), isNotNull);
    expect(a.elementById('ta'), isNull);
    // Still selected (from page a's point of view), and movable back.
    expect(selection.spansSurfaces, isTrue);
    expect(selection.elements.single.rect.top, 130);

    models.undo();
    expect(stored.loadAllElements('a').single.id, 'ta');
    expect(stored.loadAllElements('a').single.rect.top, 70);
    expect(stored.loadAll('a').single.id, 'sa');
    expect(stored.loadAll('b').single.id, 'sb');
    expect(b.elementById('ta'), isNull);
    models.redo();
    expect(stored.loadAllElements('b').map((e) => e.id), contains('ta'));
    expect(stored.loadAllElements('a'), isEmpty);
  });

  test('delete, recolour and duplicate act on both pages with one undo each', () {
    selection
      ..selectLasso(acrossGap)
      ..recolor(0xFFFF0000);
    expect(stored.loadAll('a').single.color, 0xFFFF0000);
    expect(stored.loadAll('b').single.color, 0xFFFF0000);
    expect(selection.strokes, hasLength(2));

    selection.duplicate(); // Offset by 24: copies land on the page under them.
    expect(stored.loadAll('a'), hasLength(2));
    expect(stored.loadAll('b'), hasLength(2));
    models.undo();
    expect(stored.loadAll('a'), hasLength(1));
    expect(stored.loadAll('b'), hasLength(1));

    selection.selectLasso(acrossGap);
    selection.delete();
    expect(stored.loadAll('a'), isEmpty);
    expect(stored.loadAll('b'), isEmpty);
    expect(stored.loadAllElements('b'), isEmpty);
    models.undo();
    expect(stored.loadAll('a'), hasLength(1));
    expect(stored.loadAll('b'), hasLength(1));
    expect(stored.loadAllElements('b'), hasLength(1));
    models.undo(); // The recolour, on both pages at once.
    expect(stored.loadAll('a').single.color, 0xFF000000);
    expect(stored.loadAll('b').single.color, 0xFF000000);
  });
}
