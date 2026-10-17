import 'dart:async';
import 'dart:ui' as ui;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../core/clock.dart';
import '../../domain/stroke.dart';
import '../../domain/surface_element.dart';
import '../../domain/text/text_data.dart';
import '../elements/element_order.dart';
import '../elements/text_flow_chains.dart';
import '../elements/text_layout.dart';
import '../geometry/affine.dart';
import '../render/content_painter.dart';
import '../shapes/shape_anchors.dart';
import '../shapes/shape_builder.dart';
import '../shapes/shape_handles.dart';
import '../surface_model.dart';
import '../undo_history.dart';
import 'connectors.dart';
import 'ink_clipboard.dart';
import 'lasso.dart';
import 'selection_frame.dart';
import 'selection_plan.dart';
import 'selection_reach.dart';
import 'selection_surfaces.dart';
import 'stroke_order.dart';
import 'transform_items.dart';

part 'selection_controller_commits.dart';
part 'selection_controller_connectors.dart';
part 'selection_controller_framing.dart';
part 'selection_controller_actions.dart';
part 'selection_controller_gestures.dart';

/// The state of a [SelectionController]: what is selected, where it is
/// stored, the gesture preview and the commit machinery (the commits in
/// `selection_controller_commits.dart`). The actions live
/// in `selection_controller_actions.dart`, the gestures' previews in
/// `selection_controller_gestures.dart`.
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

  /// Text boxes flowing across pages (paged notebooks): a box continuing
  /// another is not selected on its own (it follows its chain's first box,
  /// which carries the chain along).
  TextFlowChains? flows;

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

  /// The shape a line's end being dragged (a handle, the Shape tool)
  /// would attach to, shown with the selection's chrome.
  AttachHint? get attachHint => _attachHint;
  AttachHint? _attachHint;
  set attachHint(AttachHint? hint) {
    if (hint?.target.id == _attachHint?.target.id && hint?.at == _attachHint?.at) return;
    _attachHint = hint;
    notifyListeners();
  }

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
    final chains = flows;
    _elements = List.unmodifiable(
      chains == null ? elements : elements.where((e) => !_continues(chains, e)),
    );
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

  /// Whether [e] continues a box on the page before (in a chain that holds).
  static bool _continues(TextFlowChains chains, SurfaceElement e) =>
      TextFlowChains.flowOf(e) != null && chains.headOf(e.surfaceId, e) != null;

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
