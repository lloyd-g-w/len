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
    selection: selection.isValid
        ? _modelSelection(selection)
        : TextSelection.collapsed(offset: _buffer.length),
  );

  TextData _box;
  RichTextBuffer _buffer;
  late MarkerOffsets _offsets;
  List<int> _wraps = const [];
  List<FlowBreak> _breaks = const [];
  double _wrapWidth = double.infinity;
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
    notifyListeners(); // Same text, other placeholders: build the spans again.
  }

  /// Display offset of the room placeholder of page break [b].
  int? roomOffset(FlowBreak b) => _offsets.roomOf(b.at);

  /// The formatted text with the box's defaults.
  TextData get data => _data ??= _buffer.toData(_box);

  bool get isEmpty => _buffer.length == 0;

  /// The width the box wraps at (its world width), for hanging indents.
  double get wrapWidth => _wrapWidth;
  set wrapWidth(double width) {
    _wrapWidth = width;
    refreshLayout();
  }

  /// Lays the text out again if its wraps or page breaks changed, keeping
  /// the selection and an IME composition.
  void refreshLayout() {
    final breaks = breaksOf?.call(data) ?? const <FlowBreak>[];
    if (listEquals(_wrapsOf(data), _wraps) && listEquals(breaks, _breaks)) return;
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

  TextSelection _modelSelection(TextSelection s) => s.copyWith(
    baseOffset: _offsets.toModel(s.baseOffset),
    extentOffset: _offsets.toModel(s.extentOffset),
  );

  /// The display offsets of [data] at [wrapWidth].
  MarkerOffsets _offsetsOf(TextData data) {
    _wraps = _wrapsOf(data);
    _breaks = breaksOf?.call(data) ?? const [];
    return MarkerOffsets(data, _wraps, _breaks);
  }

  /// Auto-width boxes grow instead of wrapping.
  List<int> _wrapsOf(TextData data) => data.autoWidth ? const [] : TextWraps.of(data, _wrapWidth);

  /// Replaces everything (a new box started), the caret at [caret] (model
  /// offset; the end by default).
  void load(TextData data, {int? caret}) {
    _box = data;
    _buffer = RichTextBuffer(data);
    _pending = null;
    _sync(TextSelection.collapsed(offset: (caret ?? data.text.length).clamp(0, data.text.length)));
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
    _offsets = _offsetsOf(data);
    super.value = TextEditingValue(
      text: _offsets.display(_buffer.text),
      selection: model.copyWith(
        baseOffset: _offsets.toDisplay(model.baseOffset),
        extentOffset: _offsets.toDisplay(model.extentOffset),
      ),
    );
    if (!changed) return;
    _history.changed(_snapshot);
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
