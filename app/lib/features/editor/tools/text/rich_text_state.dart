part of 'rich_text_controller.dart';

/// The state of a [RichTextController]: the box defaults and its
/// [RichTextBuffer], and the display text derived from them (list marker
/// placeholders, wraps), with offsets mapped between the two.
abstract class _RichTextState extends TextEditingController {
  _RichTextState(TextData data) : _box = data, _buffer = RichTextBuffer(data) {
    watchClipboardPastes();
    _sync(const TextSelection.collapsed(offset: 0));
    _history.reset(_snapshot);
  }

  final _TextHistory _history = _TextHistory();

  /// The text and selection now, for [_history].
  _Snapshot get _snapshot => (
    data: data,
    selection:
        _cellSelection ??
        (selection.isValid
            ? _modelSelection(selection)
            : TextSelection.collapsed(offset: _buffer.length)),
  );

  /// The selection in the table cell being edited (model offsets, inside
  /// one cell), null when the field's own selection is the box's.
  TextSelection? _cellSelection;

  /// The block of table cells selected, if any.
  TableRange? _range;

  /// The model ranges of the cells selected ([_range]).
  List<TextRange> get _rangeTargets {
    final r = _range;
    final t = r == null ? null : _buffer.tableAt(r.table);
    if (r == null || t == null) return const [];
    return [
      for (final line in r.lines(t))
        TextRange(start: _buffer.lineStart(line), end: _buffer.lineEnd(line)),
    ];
  }

  /// What formatting acts on: the cells selected, the selection in the
  /// cell edited, or the field's selection.
  List<TextRange> get _targets {
    if (_range != null) return _rangeTargets;
    final s = _cellSelection;
    return [if (s != null) TextRange(start: s.start, end: s.end) else modelSelection];
  }

  TextData _box;
  RichTextBuffer _buffer;
  late TextPlan _plan;
  List<FlowBreak> _breaks = const [];
  double _wrapWidth = double.infinity;

  MarkerOffsets get _offsets => _plan.offsets;
  TextData? _data;

  /// Style for the next typed text at [_pendingAt] (a toggled format with a
  /// collapsed caret).
  SpanStyle? _pending;
  int _pendingAt = -1;

  /// Called whenever the formatted text (not just the selection) changes.
  VoidCallback? onDataChanged;

  /// Builds the widget shown for a list marker (its size is
  /// [ListMarker.size]).
  Widget Function(ListMarker marker)? markerBuilder;

  /// Where the text, a box flowing across pages, continues on the next
  /// page when it is [TextData] (see [FlowBreak]); none by default. When
  /// that changes for another reason (the box moved), [refreshLayout].
  List<FlowBreak> Function(TextData data)? breaksOf;

  /// The page breaks shown (see [breaksOf]).
  List<FlowBreak> get breaks => _breaks;

  /// How much taller than its placeholder the field lays out the line of
  /// a page break's room (the field's own line metrics; measured by the
  /// editor): the placeholder is made that much shorter, so the next page's
  /// text starts where it will be stored.
  double get roomExtra => _roomExtra;
  double _roomExtra = 0;
  set roomExtra(double value) {
    if (value == _roomExtra) return;
    _roomExtra = value;
    refreshLayout(); // Same text, other placeholders.
  }

  /// Display offset of the room placeholder of page break [b].
  int? roomOffset(FlowBreak b) => _offsets.roomOf(b.at);

  /// The formatted text with the box's defaults.
  TextData get data => _data ??= _buffer.toData(_box);

  bool get isEmpty => _buffer.length == 0;

  /// The width of the box (its world width): list items wrap with
  /// hanging indents and paragraphs against the box's direction align at it.
  double get wrapWidth => _wrapWidth;
  set wrapWidth(double width) {
    if (width == _wrapWidth) return;
    _wrapWidth = width;
    refreshLayout();
  }

  /// Lays the text out again if its plan (wraps, padding, page breaks)
  /// changed, keeping the selection and an IME composition.
  void refreshLayout() {
    final breaks = _breaksOf(data);
    final plan = _planOf(data, breaks);
    _breaks = breaks;
    if (listEquals(plan.inserts, _plan.inserts)) return;
    if (plan.offsets.display(_buffer.text) == text) {
      // Only sizes changed (padding, a room): the same text, laid out anew.
      _plan = plan;
      notifyListeners();
      return;
    }
    final c = value.composing;
    final composing = c.isValid && !c.isCollapsed
        ? TextRange(start: _offsets.toModel(c.start), end: _offsets.toModel(c.end))
        : null;
    _sync(
      selection.isValid ? _modelSelection(selection) : const TextSelection.collapsed(offset: 0),
    );
    if (composing != null) {
      super.value = value.copyWith(
        composing: TextRange(
          start: _offsets.toDisplay(composing.start),
          end: _offsets.toDisplay(composing.end),
        ),
      );
    }
  }

  /// How the field lays out (see [TextPlan]).
  TextPlan get plan => _plan;

  TextSelection _modelSelection(TextSelection s) => s.copyWith(
    baseOffset: _offsets.toModel(s.baseOffset),
    extentOffset: _offsets.toModel(s.extentOffset),
  );

  /// The page breaks of [data] (see [breaksOf]).
  List<FlowBreak> _breaksOf(TextData data) => breaksOf?.call(data) ?? const [];

  /// The plan of [data] at [wrapWidth] with [breaks] (by default its own),
  /// their rooms made [roomExtra] shorter.
  TextPlan _planOf(TextData data, [List<FlowBreak>? breaks]) => TextPlan.of(
    data,
    _wrapWidth,
    breaks: [
      for (final b in breaks ?? _breaksOf(data))
        (at: b.at, gap: math.max(0.0, b.gap - _roomExtra), soft: b.soft),
    ],
  );

  /// Replaces everything (a new box started), the caret at [caret] (model
  /// offset; the end by default).
  void load(TextData data, {int? caret}) {
    _box = data;
    _buffer = RichTextBuffer(data);
    _pending = null;
    _cellSelection = null;
    _range = null;
    final at = (caret ?? data.text.length).clamp(0, data.text.length);
    _sync(TextSelection.collapsed(offset: at));
    // A caret in a table edits its cell.
    if (_offsets.isInRow(at)) _cellSelection = TextSelection.collapsed(offset: at);
    _history.reset(_snapshot);
  }

  /// The selection in box-text offsets.
  TextRange get modelSelection {
    final s = selection;
    if (!s.isValid) return TextRange.collapsed(_buffer.length);
    return TextRange(start: _offsets.toModel(s.start), end: _offsets.toModel(s.end));
  }

  /// Rebuilds the display text and selects [model] (box-text offsets).
  void _sync(TextSelection model, {bool changed = false}) {
    _data = null;
    _breaks = _breaksOf(data);
    _plan = _planOf(data, _breaks);
    super.value = TextEditingValue(
      text: _offsets.display(_buffer.text),
      selection: model.copyWith(
        baseOffset: _offsets.toDisplay(model.baseOffset),
        extentOffset: _offsets.toDisplay(model.extentOffset),
      ),
    );
    if (!changed) return;
    _history.changed(_snapshot, command: true);
    onDataChanged?.call();
  }

  void _changedKeeping(TextRange model) =>
      _sync(TextSelection(baseOffset: model.start, extentOffset: model.end), changed: true);

  /// Changes the box defaults (font, size, colour, alignment, auto width).
  void setBox(TextData box) {
    _box = box;
    _changedKeeping(modelSelection);
  }

  TextData get box => _box;

  /// Takes over changed box defaults made elsewhere (e.g. auto width
  /// ended), without reporting a change.
  void adoptBox(TextData box) {
    _box = box;
    _data = null;
  }
}
