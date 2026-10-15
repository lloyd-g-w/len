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
  late TextPlan _plan;
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

  /// The formatted text with the box's defaults.
  TextData get data => _data ??= _buffer.toData(_box);

  bool get isEmpty => _buffer.length == 0;

  /// The width of the box (its world width): list items wrap with
  /// hanging indents and paragraphs against the box's direction align at it.
  double get wrapWidth => _wrapWidth;
  set wrapWidth(double width) {
    if (width == _wrapWidth) return;
    _wrapWidth = width;
    final plan = _planOf(data);
    if (listEquals(plan.inserts, _plan.inserts)) return;
    if (plan.offsets.display(_buffer.text) == text) {
      // Only padding changed: the same text, laid out anew.
      _plan = plan;
      notifyListeners();
      return;
    }
    _sync(
      selection.isValid ? _modelSelection(selection) : const TextSelection.collapsed(offset: 0),
    );
  }

  /// How the field lays out (see [TextPlan]).
  TextPlan get plan => _plan;

  TextSelection _modelSelection(TextSelection s) => s.copyWith(
    baseOffset: _offsets.toModel(s.baseOffset),
    extentOffset: _offsets.toModel(s.extentOffset),
  );

  /// The plan of [data] at [wrapWidth].
  TextPlan _planOf(TextData data) => TextPlan.of(data, _wrapWidth);

  /// Replaces everything (a new box started).
  void load(TextData data) {
    _box = data;
    _buffer = RichTextBuffer(data);
    _pending = null;
    _sync(TextSelection.collapsed(offset: data.text.length));
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
    _plan = _planOf(data);
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
