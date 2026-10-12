import 'dart:async';
import 'dart:ui' as ui;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../core/clock.dart';
import '../../domain/stroke.dart';
import '../../domain/surface_element.dart';
import '../../domain/text/text_data.dart';
import '../elements/element_order.dart';
import '../geometry/affine.dart';
import '../render/content_painter.dart';
import '../surface_model.dart';
import '../undo_history.dart';
import 'ink_clipboard.dart';
import 'lasso.dart';
import 'selection_frame.dart';
import 'selection_plan.dart';
import 'selection_reach.dart';
import 'selection_surfaces.dart';
import 'transform_items.dart';

part 'selection_controller_actions.dart';

/// The state of a [SelectionController]: what is selected, where it is
/// stored, the gesture preview and the commit machinery. The actions live
/// in `selection_controller_actions.dart`.
abstract class _SelectionCore extends ChangeNotifier {
  _SelectionCore({required this._model, required this.clipboard, required this.clock}) {
    _model.addListener(_onModelChanged);
    _watchImages();
  }

  final InkClipboard clipboard;
  final Clock clock;

  SurfaceModel _model;
  SurfaceModel get model => _model;
  set model(SurfaceModel value) {
    if (identical(value, _model)) return;
    clear();
    _model.removeListener(_onModelChanged);
    _model = value..addListener(_onModelChanged);
    _watchImages();
  }

  StreamSubscription<String>? _imageChanges;

  /// Other surfaces the selection may reach (pages of a document).
  SelectionSurfaces? surfaces;

  /// Re-records the selection when one of its images finishes decoding.
  void _watchImages() {
    unawaited(_imageChanges?.cancel());
    _imageChanges = _model.images?.changes.listen((blob) {
      if (_picture == null || !_elements.any((e) => e.data['blob'] == blob)) return;
      _picture!.dispose();
      _picture = _record();
      notifyListeners();
    });
  }

  List<Stroke> _strokes = const [];
  List<SurfaceElement> _elements = const [];
  Map<String, SelectionSource> _sources = const {};

  /// Other surfaces holding selected items (hidden there, watched).
  Set<SurfaceModel> _others = const {};
  SelectionFrame? _frame;
  SelectionFrame? _previewFrame;
  Affine _preview = Affine.identity;
  ui.Picture? _picture;
  bool _editing = false;

  /// Margin (world units) between the content and a new selection's
  /// frame, so thin selections (one line) still have room to grab.
  double framePadding = 0;

  /// Device pixels per world unit, for the resolution of selected images.
  double pixelScale = 1;

  List<Stroke> get strokes => _strokes;
  List<SurfaceElement> get elements => _elements;
  bool get isEmpty => _strokes.isEmpty && _elements.isEmpty;

  /// Whether some selected items are stored on other surfaces (pages).
  bool get spansSurfaces => _sources.isNotEmpty;

  /// The frame as shown (including an in-progress gesture).
  SelectionFrame? get frame => _previewFrame ?? _frame;

  /// Transform of the in-progress gesture, applied to [picture].
  Affine get preview => _preview;

  /// The selected content as recorded at selection time (world coords).
  ui.Picture? get picture => _picture;

  /// Selects [strokes] and [elements] (replacing any previous selection).
  /// Items stored on other surfaces are given in this surface's
  /// coordinates, with their [sources] (by id).
  void select(
    Iterable<Stroke> strokes,
    Iterable<SurfaceElement> elements, {
    SelectionFrame? frame,
    Map<String, SelectionSource> sources = const {},
  }) {
    _strokes = List.unmodifiable(strokes);
    _elements = List.unmodifiable(elements);
    _sources = Map.unmodifiable(sources);
    _preview = Affine.identity;
    _previewFrame = null;
    _picture?.dispose();
    _picture = null;
    _frame = isEmpty ? null : frame ?? _frameAround(_strokes, _elements);
    if (!isEmpty) _picture = _record();
    _hide();
    notifyListeners();
  }

  /// Selects what [lasso] (this surface's coordinates) encloses here and
  /// on the other [surfaces] it reaches.
  void selectLasso(Lasso lasso) {
    final pick = SelectionReach.pick(_model, surfaces, lasso);
    select(pick.strokes, pick.elements, sources: pick.sources);
  }

  /// Hides the selected items on the surfaces holding them (and watches
  /// those surfaces for changes underneath the selection).
  void _hide() => _others = SelectionReach.hide(
    owner: this,
    model: _model,
    ids: [for (final s in _strokes) s.id, for (final e in _elements) e.id],
    sources: _sources,
    before: _others,
    onChanged: _onModelChanged,
  );

  void clear() {
    if (isEmpty && _frame == null) return;
    select(const [], const []);
  }

  // ---------------------------------------------------------------------------
  // Transform gestures

  /// Shows [t] (with the resulting [frame]) without committing anything.
  void setPreview(Affine t, SelectionFrame frame) {
    _preview = t;
    _previewFrame = frame;
    notifyListeners();
  }

  /// Commits the previewed transform as one undoable edit.
  void commitPreview() {
    final t = _preview;
    final frame = _previewFrame;
    if (t.isIdentity || frame == null) {
      cancelPreview();
      return;
    }
    final strokes = [for (final s in _strokes) TransformItems.stroke(s, t, id: clock.newId())];
    final elements = [for (final e in _elements) TransformItems.element(e, t)];
    _replace(strokes, elements, frame: frame, transfer: true);
  }

  void cancelPreview() {
    if (_previewFrame == null && _preview.isIdentity) return;
    _preview = Affine.identity;
    _previewFrame = null;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Internals

  void _paste(List<Stroke> strokes, List<SurfaceElement> elements, Rect bounds, Offset at) {
    final t = Affine.translation(at - bounds.center);
    final now = clock.nowMs();
    final ordered = [...strokes]..sort(Stroke.paintOrder);
    final orderedElements = [...elements]..sort(SurfaceElement.paintOrder);
    final z = ElementOrder.pasted(
      orderedElements,
      top: _model.topZ,
      topBelowInk: _model.topBelowInkZ,
    );
    final newStrokes = [
      for (var i = 0; i < ordered.length; i++)
        _onSurface(TransformItems.stroke(ordered[i], t, id: clock.newId()), now + i),
    ];
    final newElements = [
      for (var i = 0; i < orderedElements.length; i++)
        TransformItems.element(
          orderedElements[i],
          t,
        ).copyWith(id: clock.newId(), surfaceId: _model.surfaceId, z: z[i], createdAt: now),
    ];
    final plan = SelectionPlan(_model);
    for (final s in newStrokes) {
      plan.addStroke(s, to: _target(s.bounds.center, null, transfer: true));
    }
    for (final e in newElements) {
      plan.addElement(e, to: _target(e.rect.center, null, transfer: true));
    }
    _apply(plan);
  }

  Stroke _onSurface(Stroke s, int createdAt) => Stroke(
    id: s.id,
    surfaceId: _model.surfaceId,
    tool: s.tool,
    color: s.color,
    width: s.width,
    points: s.points,
    createdAt: createdAt,
    style: s.style,
  );

  /// Replaces the selected items with [strokes] (one per selected stroke,
  /// in order; or the very same list to keep them) and [elements] (matched
  /// by id) as one undoable edit, each on the surface it was stored on —
  /// or, with [transfer], on the page under its centre.
  void _replace(
    List<Stroke> strokes,
    List<SurfaceElement> elements, {
    SelectionFrame? frame,
    bool transfer = false,
  }) {
    final plan = SelectionPlan(_model);
    final same = identical(strokes, _strokes);
    for (var i = 0; i < _strokes.length; i++) {
      final source = _sources[_strokes[i].id];
      same ? plan.keepStroke(_strokes[i], source) : plan.removeStroke(_strokes[i], source);
    }
    if (!same) {
      for (var i = 0; i < strokes.length; i++) {
        final from = i < _strokes.length ? _sources[_strokes[i].id] : null;
        plan.addStroke(strokes[i], to: _target(strokes[i].bounds.center, from, transfer: transfer));
      }
    }
    for (final e in _elements) {
      plan.removeElement(e, _sources[e.id]);
    }
    for (final e in elements) {
      final from = _sources[e.id];
      plan.addElement(
        e,
        to: _target(e.rect.center, from, transfer: transfer),
        from: from,
      );
    }
    _apply(plan, frame: frame);
  }

  /// Where an item centred on [centre] goes: with [transfer] the page under
  /// it, else (or when it is on no page) the surface it came [from].
  ShiftedSurface? _target(Offset centre, SelectionSource? from, {required bool transfer}) {
    final here = transfer ? surfaces?.at(_model, centre) : null;
    return here ?? from?.surface;
  }

  /// Commits [plan] and selects what it leaves selected.
  void _apply(SelectionPlan plan, {SelectionFrame? frame}) {
    _commit(plan);
    select(plan.strokes, plan.elements, frame: frame, sources: plan.sources);
  }

  /// Commits [plan] (one undo step) without the change listener dropping
  /// the selection.
  void _commit(SelectionPlan plan) {
    _editing = true;
    try {
      plan.commit(surfaces?.batch ?? (edits) => edits());
    } finally {
      _editing = false;
    }
  }

  /// Drops the selection when its content changes underneath it (undo,
  /// redo, erasing, a sync reload).
  void _onModelChanged() {
    if (_editing || isEmpty) return;
    final stale =
        _strokes.any((s) => !_stored(s.id, s, (m) => m.strokeById(s.id))) ||
        _elements.any((e) => !_stored(e.id, e, (m) => m.elementById(e.id)));
    if (stale) clear();
  }

  /// Whether selected item [item] is still what its surface stores.
  bool _stored(String id, Object item, Object? Function(SurfaceModel) lookup) {
    final source = _sources[id];
    return identical(lookup(source?.surface.model ?? _model), source?.original ?? item);
  }

  ui.Picture _record() {
    final recorder = ui.PictureRecorder();
    ContentPainter.paint(
      Canvas(recorder),
      _strokes,
      _elements,
      images: _model.images,
      pixelScale: pixelScale,
    );
    return recorder.endRecording();
  }

  /// A new selection's frame: around a single element it follows the
  /// element's rotation (so handles sit on its edges), otherwise it is the
  /// axis-aligned bounds.
  SelectionFrame _frameAround(List<Stroke> strokes, List<SurfaceElement> elements) {
    if (strokes.isEmpty && elements.length == 1) {
      final e = elements.single;
      return SelectionFrame(e.rect.inflate(framePadding), e.rotation);
    }
    return SelectionFrame(SelectionController.boundsOf(strokes, elements).inflate(framePadding));
  }

  @override
  void dispose() {
    _model.removeListener(_onModelChanged);
    for (final model in _others) {
      model.removeListener(_onModelChanged);
    }
    unawaited(_imageChanges?.cancel());
    _picture?.dispose();
    super.dispose();
  }
}
