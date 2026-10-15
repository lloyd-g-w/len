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
import '../shapes/shape_builder.dart';
import '../shapes/shape_handles.dart';
import '../surface_model.dart';
import '../undo_history.dart';
import 'ink_clipboard.dart';
import 'lasso.dart';
import 'selection_frame.dart';
import 'selection_plan.dart';
import 'selection_reach.dart';
import 'selection_surfaces.dart';
import 'transform_items.dart';

part 'selection_controller_commits.dart';
part 'selection_controller_actions.dart';

/// The state of a [SelectionController]: what is selected, where it is
/// stored, the gesture preview and the commit machinery (the commits in
/// `selection_controller_commits.dart`). The actions live
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
      _picture = _record(_reshaped == null ? _strokes : [_reshaped!]);
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

  /// The selected stroke when it is a single shape stored here, whose
  /// points can be dragged ([reshape]).
  Stroke? get shapeStroke {
    if (_strokes.length != 1 || _elements.isNotEmpty || _sources.isNotEmpty) return null;
    return _strokes.single.shape == null ? null : _strokes.single;
  }

  /// The geometry of [shapeStroke] as shown (with a reshape, move, resize
  /// or rotation in progress); null when no single shape is selected.
  ShapeGeometry? get shape => _reshaped?.shape ?? shapeStroke?.shape?.map(_preview.apply);

  /// Whether a gesture is changing the selection (its menu steps aside).
  bool get isChanging => _reshaped != null || !_preview.isIdentity;

  /// [shapeStroke] reshaped by the drag in progress.
  Stroke? _reshaped;

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
    _reshaped = null;
    _picture?.dispose();
    _picture = null;
    _frame = isEmpty ? null : frame ?? _frameAround(_strokes, _elements);
    if (!isEmpty) _picture = _record(_strokes);
    _hide();
    // Other views of this surface (split view) draw the selection from
    // here instead of a hole where it was.
    _model.setLifted(this, isEmpty ? null : _paintLifted);
    notifyListeners();
  }

  /// Draws the selected content as shown (with the gesture in progress),
  /// in the selection surface's coordinates.
  void _paintLifted(Canvas canvas) {
    final picture = _picture;
    if (picture == null) return;
    canvas
      ..save()
      ..transform(_preview.matrix4)
      ..drawPicture(picture)
      ..restore();
  }

  @override
  void notifyListeners() {
    super.notifyListeners();
    _model.liftedChanged(this); // Moved, resized, recoloured…
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

  /// Shows [shapeStroke] reshaped to [shape] (a handle being dragged)
  /// without committing anything.
  void reshape(ShapeGeometry shape) {
    final stroke = shapeStroke;
    if (stroke == null) return;
    final reshaped = _reshaped = ShapeBuilder.reshaped(stroke, shape, id: stroke.id);
    _picture?.dispose();
    _picture = _record([reshaped]);
    _previewFrame = _frameAround([reshaped], const []);
    notifyListeners();
  }

  /// Commits the shape [reshape] showed as one undoable edit (its fill and
  /// look kept), and keeps it selected.
  void commitReshape() {
    final reshaped = _reshaped;
    if (reshaped == null) return;
    final frame = _previewFrame;
    _reshaped = null;
    if (reshaped.shape == _strokes.single.shape) return cancelReshape();
    _replace(
      [reshaped.withPoints(reshaped.points, id: clock.newId(), shape: reshaped.shape)],
      const [],
      frame: frame,
    );
  }

  /// Drops the shape [reshape] showed.
  void cancelReshape() {
    final wasReshaped = _reshaped != null || _previewFrame != null;
    _reshaped = null;
    if (!wasReshaped || isEmpty) return;
    _picture?.dispose();
    _picture = _record(_strokes);
    _previewFrame = null;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Internals

  /// The surface edited by the last commit when it was the only one, and a
  /// surface whose previous undo step the next commit joins (see `nudge`).
  SurfaceModel? _committedTo, _mergeInto;

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

  ui.Picture _record(List<Stroke> strokes) {
    final recorder = ui.PictureRecorder();
    ContentPainter.paint(
      Canvas(recorder),
      strokes,
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
    // A single shape: turned with it, so its handles sit on the frame.
    if (strokes.length == 1 && elements.isEmpty && strokes.single.shape != null) {
      final s = strokes.single;
      final angle = ShapeHandles.angleOf(s.shape!);
      return SelectionFrame.around(
        [for (final p in s.points) p.offset],
        angle,
        framePadding + s.width / 2,
      );
    }
    return SelectionFrame(SelectionController.boundsOf(strokes, elements).inflate(framePadding));
  }

  @override
  void dispose() {
    // The surfaces outlive the editor (another view of the notebook): what
    // this selection hid there shows again.
    _model
      ..removeListener(_onModelChanged)
      ..setLifted(this, null)
      ..setHidden(const {}, owner: this);
    for (final model in _others) {
      model
        ..removeListener(_onModelChanged)
        ..setHidden(const {}, owner: this);
    }
    unawaited(_imageChanges?.cancel());
    _picture?.dispose();
    super.dispose();
  }
}
