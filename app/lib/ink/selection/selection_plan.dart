import 'dart:ui';

import '../../domain/stroke.dart';
import '../../domain/surface_element.dart';
import '../../domain/text/text_data.dart';
import '../elements/text_flow_chains.dart';
import '../elements/text_layout.dart';
import '../surface_model.dart';
import '../undo_history.dart';
import 'selection_surfaces.dart';

/// The edits of one selection change, possibly spread over several
/// surfaces (pages): which stored items go, which come (in each surface's
/// own coordinates) and what the selection holds afterwards (in the
/// selection's coordinates, with the [sources] of items on other surfaces).
///
/// Items are given in the selection's coordinates; [add] converts them into
/// the target surface's. An element moving to another surface keeps its id:
/// it is removed from its old surface before it is saved on the new one
/// (every removal is committed before any arrival), so storage and sync
/// see it re-parented, and undo (in reverse order) puts it back.
class SelectionPlan {
  SelectionPlan(this.primary);

  /// The selection's own surface.
  final SurfaceModel primary;

  late final ShiftedSurface _home = (model: primary, shift: Offset.zero);

  final Map<SurfaceModel, _Edit> _first = {};
  final Map<SurfaceModel, _Edit> _arrivals = {};

  /// The selection after the change (selection coordinates).
  final List<Stroke> strokes = [];
  final List<SurfaceElement> elements = [];
  final Map<String, SelectionSource> sources = {};

  ShiftedSurface _surfaceOf(SelectionSource? source) => source?.surface ?? _home;

  /// Removes stored stroke [s] (selection coordinates), from [source].
  void removeStroke(Stroke s, SelectionSource? source) {
    final surface = _surfaceOf(source);
    _edit(_first, surface.model).removed.add((source?.original as Stroke?) ?? s);
  }

  /// Removes stored element [e] (selection coordinates), from [source].
  void removeElement(SurfaceElement e, SelectionSource? source) {
    final surface = _surfaceOf(source);
    _edit(_first, surface.model).removedElements.add((source?.original as SurfaceElement?) ?? e);
  }

  /// Keeps stroke [s] selected as it is.
  void keepStroke(Stroke s, SelectionSource? source) {
    strokes.add(s);
    if (source != null) sources[s.id] = source;
  }

  /// Keeps element [e] selected as it is.
  void keepElement(SurfaceElement e, SelectionSource? source) {
    elements.add(e);
    if (source != null) sources[e.id] = source;
  }

  /// Adds stroke [s] (selection coordinates) to surface [to] (default: the
  /// selection's own) and selects it.
  void addStroke(Stroke s, {ShiftedSurface? to}) {
    final target = to ?? _home;
    final stored = _strokeOn(s, target);
    _edit(_first, target.model).added.add(stored);
    final selected = target.model == primary
        ? stored
        : _strokeOn(s, (model: target.model, shift: Offset.zero));
    keepStroke(selected, target.model == primary ? null : SelectionSource(target, stored));
  }

  /// Replaces stored stroke [old] on [model] with [stroke] (both in that
  /// surface's coordinates) without selecting it: a connector following
  /// the shape it is attached to.
  void replaceUnselected(SurfaceModel model, Stroke old, Stroke stroke) {
    final edit = _edit(_first, model);
    edit.removed.add(old);
    edit.added.add(stroke);
  }

  /// Adds element [e] (selection coordinates) to surface [to] (default: the
  /// selection's own) and selects it. [from] is the surface it was stored
  /// on, if it replaces a stored element with the same id.
  void addElement(SurfaceElement e, {ShiftedSurface? to, SelectionSource? from}) {
    final target = to ?? _home;
    final home = target.model == primary;
    final id = target.model.surfaceId;
    final stored = home && e.surfaceId == id
        ? e
        : e.copyWith(rect: e.rect.shift(-target.shift), surfaceId: id);
    final moving = _surfaceOf(from).model != target.model;
    _edit(moving ? _arrivals : _first, target.model).addedElements.add(stored);
    keepElement(
      home ? stored : e.copyWith(surfaceId: id),
      home ? null : SelectionSource(target, stored),
    );
  }

  /// Whether the plan adds or removes text boxes.
  bool get touchesText => [..._first.values, ..._arrivals.values].any(
    (e) => [...e.addedElements, ...e.removedElements].any((x) => x.knownType == ElementType.text),
  );

  /// Lets the text boxes this plan changes flow across pages ([chains]):
  /// the chain of a first box moved, resized or restyled flows again from
  /// where it is now (continuations follow it), one deleted takes its
  /// continuations along, and a box no longer flowing (rotated, a broken
  /// chain's box) holds the whole text. The selection keeps the first boxes
  /// as laid out. Pages it adds need the commit run in
  /// [TextFlowPages.batch].
  void flowText(TextFlowChains chains) {
    final added = <String, (SurfaceModel, SurfaceElement)>{};
    final removed = <String, (SurfaceModel, SurfaceElement)>{};
    for (final edits in [_first, _arrivals]) {
      for (final MapEntry(key: model, value: edit) in edits.entries) {
        for (final e in edit.removedElements) {
          if (e.knownType == ElementType.text) removed[e.id] = (model, e);
        }
        for (final e in edit.addedElements) {
          if (e.knownType == ElementType.text) added[e.id] = (model, e);
        }
      }
    }
    for (final MapEntry(key: id, value: (model, before)) in removed.entries) {
      if (added.containsKey(id) || TextFlowChains.flowOf(before) != null) continue;
      _merge(chains, chains.removing(model.surfaceId, before.id));
    }
    for (final (model, after) in added.values) {
      final before = removed[after.id];
      // A box continuing another could only be selected once its chain
      // broke: it stands alone now.
      final head = TextFlowChains.flowOf(after) == null
          ? after
          : after.copyWith(data: TextData.fromJson(after.data).withFlow(null).toJson(after.data));
      final rest = before == null || TextFlowChains.flowOf(before.$2) != null
          ? const <FlowBox>[]
          : chains.continuationsOf(before.$1.surfaceId, before.$2.id);
      if (rest.isEmpty && identical(head, after) && !chains.canFlow(model.surfaceId, head)) {
        continue;
      }
      final whole = TextFlowChains.wholeOf(head, rest);
      SurfaceElement laid;
      if (chains.canFlow(model.surfaceId, head)) {
        final r = chains.reflow(model.surfaceId, head, whole, rest);
        laid = r.head;
        _merge(chains, r.edits);
      } else {
        final height = TextLayout.heightOf(whole, head.rect.width);
        final r = head.rect;
        laid = head.copyWith(
          rect: Rect.fromLTWH(r.left, r.top, r.width, rest.isEmpty ? r.height : height),
          data: whole.toJson(head.data),
        );
        if (rest.isNotEmpty) {
          _merge(chains, chains.removing(before!.$1.surfaceId, before.$2.id, rest));
        }
      }
      if (identical(laid, after)) continue;
      final edit = (_arrivals[model]?.addedElements.contains(after) ?? false)
          ? _arrivals[model]!
          : _first[model]!;
      edit.addedElements[edit.addedElements.indexOf(after)] = laid;
      _relaid(after, laid);
    }
  }

  /// Adds the edits of other pages [edits] (continuations) to the plan.
  void _merge(TextFlowChains chains, Map<String, InkEdit> edits) {
    for (final MapEntry(key: page, value: edit) in edits.entries) {
      final target = _edit(_first, chains.pages.modelOf(page));
      target.removedElements.addAll(edit.removedElements);
      target.addedElements.addAll(edit.addedElements);
    }
  }

  /// The selection holds [laid] (stored) in place of [stored].
  void _relaid(SurfaceElement stored, SurfaceElement laid) {
    final i = elements.indexWhere((e) => e.id == stored.id);
    if (i == -1) return;
    final shown = elements[i];
    final r = shown.rect;
    elements[i] = shown.copyWith(
      rect: Rect.fromLTWH(r.left, r.top, laid.rect.width, laid.rect.height),
      data: laid.data,
    );
    final source = sources[stored.id];
    if (source != null) sources[stored.id] = SelectionSource(source.surface, laid);
  }

  /// Commits every surface's edits; through [batch] (one undo step) when
  /// more than one commit is needed. With [mergeInto], a change that only
  /// edits that surface joins its previous undo step (a burst of nudges).
  /// Returns the surface when only one was edited.
  SurfaceModel? commit(void Function(void Function() edits) batch, {SurfaceModel? mergeInto}) {
    final edits = [
      for (final e in _first.entries) (e.key, e.value.build()),
      for (final e in _arrivals.entries) (e.key, e.value.build()),
    ].where((e) => !e.$2.isEmpty).toList();
    final merge = edits.length == 1 && edits.single.$1 == mergeInto;
    void run() {
      for (final (model, edit) in edits) {
        model.commit(edit, merge: merge);
      }
    }

    edits.length > 1 ? batch(run) : run();
    return edits.length == 1 ? edits.single.$1 : null;
  }

  static _Edit _edit(Map<SurfaceModel, _Edit> edits, SurfaceModel model) =>
      edits[model] ??= _Edit();

  /// [s] (selection coordinates) as stored on [target].
  static Stroke _strokeOn(Stroke s, ShiftedSurface target) {
    final id = target.model.surfaceId;
    if (target.shift == Offset.zero && s.surfaceId == id) return s;
    final d = -target.shift;
    return Stroke(
      id: s.id,
      surfaceId: id,
      tool: s.tool,
      color: s.color,
      width: s.width,
      points: [for (final p in s.points) StrokePoint(p.x + d.dx, p.y + d.dy, p.pressure)],
      createdAt: s.createdAt,
      style: s.style,
      shape: s.shape?.map((p) => p + d),
    );
  }
}

class _Edit {
  final List<Stroke> added = [];
  final List<Stroke> removed = [];
  final List<SurfaceElement> addedElements = [];
  final List<SurfaceElement> removedElements = [];

  InkEdit build() => InkEdit(
    added: added,
    removed: removed,
    addedElements: addedElements,
    removedElements: removedElements,
  );
}
