import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../../domain/text/rich_text_buffer.dart';
import '../../../../domain/text/text_data.dart';
import '../../../../ink/elements/text_layout.dart';

/// The text field controller of a text box being edited: keeps the
/// formatted text in a [RichTextBuffer] and renders it with
/// [TextLayout.spanOf], exactly like the canvas does.
///
/// The field's text is the *display* text: the box's text with one
/// placeholder character before each list line, where the marker widget
/// sits, and a break plus an indent gap where a list item wraps at
/// [wrapWidth] (hanging indents, see [MarkerOffsets] and [TextWraps]). Edits the field makes are mapped back onto
/// the buffer; formatting commands act on the selection (or, with a
/// collapsed caret, on what is typed next).
class RichTextController extends TextEditingController {
  RichTextController(TextData data) : _box = data, _buffer = RichTextBuffer(data) {
    _sync(const TextSelection.collapsed(offset: 0));
  }

  TextData _box;
  RichTextBuffer _buffer;
  late MarkerOffsets _offsets;
  List<int> _wraps = const [];
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

  /// Text copied from a box here, with its formatting: pasting the same
  /// plain text keeps the formatting.
  static ({String text, List<SpanStyle> styles})? _richClip;

  /// [text] from the clipboard as a new box formatted like [box]; text
  /// last copied from a box here keeps its formatting.
  static TextData pasted(String text, TextData box) {
    final clean = text.replaceAll('\uFFFC', '').replaceAll('\r\n', '\n');
    final clip = _richClip;
    final base = box.copyWith(text: clean);
    if (clip == null || clip.text != clean) return base;
    return base.withFormatting(spans: TextData.compact(clip.styles));
  }

  /// The formatted text with the box's defaults.
  TextData get data => _data ??= _buffer.toData(_box);

  bool get isEmpty => _buffer.length == 0;

  /// The width the box wraps at (its world width), for hanging indents.
  double get wrapWidth => _wrapWidth;
  set wrapWidth(double width) {
    _wrapWidth = width;
    if (listEquals(_wrapsOf(data), _wraps)) return;
    _sync(
      selection.isValid ? _modelSelection(selection) : const TextSelection.collapsed(offset: 0),
    );
  }

  TextSelection _modelSelection(TextSelection s) => s.copyWith(
    baseOffset: _offsets.toModel(s.baseOffset),
    extentOffset: _offsets.toModel(s.extentOffset),
  );

  /// The display offsets of [data] at [wrapWidth].
  MarkerOffsets _offsetsOf(TextData data) {
    _wraps = _wrapsOf(data);
    return MarkerOffsets(data, _wraps);
  }

  /// Auto-width boxes grow instead of wrapping.
  List<int> _wrapsOf(TextData data) => data.autoWidth ? const [] : TextWraps.of(data, _wrapWidth);

  /// Replaces everything (a new box started).
  void load(TextData data) {
    _box = data;
    _buffer = RichTextBuffer(data);
    _pending = null;
    _sync(TextSelection.collapsed(offset: data.text.length));
  }

  // ---------------------------------------------------------------------
  // Offsets and selection.

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
    if (changed) onDataChanged?.call();
  }

  void _changedKeeping(TextRange model) =>
      _sync(TextSelection(baseOffset: model.start, extentOffset: model.end), changed: true);

  @override
  set value(TextEditingValue next) {
    final old = super.value;
    if (next.text == old.text) {
      final sel = _normalize(next.selection, old.selection);
      if (sel != old.selection) _pending = null;
      super.value = next.copyWith(selection: sel);
      return;
    }
    _applyEdit(old, next);
  }

  /// Keeps the caret off the spot before a list marker (and inside a wrap's
  /// insert): it steps over it in the direction it was moving.
  TextSelection _normalize(TextSelection s, TextSelection old) {
    if (!s.isValid || _offsets.isEmpty) return s;
    int fix(int d, int was) {
      if (!_offsets.isHidden(d)) return d;
      return was == d + 1 && d > 0 ? d - 1 : d + 1;
    }

    return s.copyWith(
      baseOffset: fix(s.baseOffset, old.baseOffset),
      extentOffset: fix(s.extentOffset, old.extentOffset),
    );
  }

  /// Maps the field's edit (old → next display text) onto the buffer.
  void _applyEdit(TextEditingValue old, TextEditingValue next) {
    final o = old.text, n = next.text;
    var p = 0;
    final shorter = math.min(o.length, n.length);
    while (p < shorter && o.codeUnitAt(p) == n.codeUnitAt(p)) {
      p++;
    }
    // Repeated characters make the edit ambiguous; an insertion ends at
    // the new caret.
    final caret = next.selection.isValid ? next.selection.extentOffset : -1;
    if (caret >= 0) p = math.min(p, math.max(0, caret - math.max(0, n.length - o.length)));
    var s = 0;
    while (s < o.length - p &&
        s < n.length - p &&
        o.codeUnitAt(o.length - 1 - s) == n.codeUnitAt(n.length - 1 - s)) {
      s++;
    }
    final removedEnd = o.length - s;
    final inserted = n.substring(p, n.length - s).replaceAll('\uFFFC', '');
    var start = _offsets.toModel(p), end = _offsets.toModel(removedEnd);
    final composing = _composing(next.composing, p, n.length - s, start);
    final line = _buffer.lineOf(start);
    // Markers deleted on their own (backspace at a list line's start).
    final unlisted = <int>{
      for (var d = p; d < removedEnd; d++)
        if (_offsets.isMarker(d) && _offsets.toModel(d) == start) line,
    };
    if (inserted.isEmpty && start == end && removedEnd > p && _offsets.isWrap(p)) {
      // Only a wrap's break or gap deleted: delete the character before
      // (backspace at a continuation line's start) or after it.
      if (o.codeUnitAt(removedEnd - 1) == PlaceholderSpan.placeholderCodeUnit) {
        if (start > 0) start--;
      } else if (end < _buffer.length) {
        end++;
      }
    }
    final para = _buffer.para(line);
    if (inserted == '\n' &&
        start == end &&
        para.isList &&
        _buffer.lineStart(line) == _buffer.lineEnd(line)) {
      // Enter on an empty list item ends the list.
      _buffer.updateParas(line, line, (p) => p.copyWith(list: ListKind.none));
      _pending = null;
      _changedKeeping(TextRange.collapsed(start));
      return;
    }
    final clip = _richClip;
    final style = _pending != null && _pendingAt == start
        ? _pending!
        : end > start && _buffer.text.codeUnitAt(start) != 0x0A
        ? _buffer.charStyle(start)
        : _buffer.styleAt(start);
    _buffer.replace(start, end, inserted, style);
    if (clip != null && clip.text == inserted && inserted.isNotEmpty) {
      for (var i = 0; i < inserted.length; i++) {
        _buffer.updateChars(start + i, start + i + 1, (_) => clip.styles[i]);
      }
    }
    for (final l in unlisted) {
      _buffer.updateParas(l, l, (p) => p.copyWith(list: ListKind.none));
    }
    _pending = null;
    _data = null;
    final offsets = _offsetsOf(data);
    final display = offsets.display(_buffer.text);
    _offsets = offsets;
    if (display == n) {
      super.value = next.copyWith(selection: _normalize(next.selection, old.selection));
    } else {
      final at = offsets.toDisplay(start + inserted.length);
      super.value = TextEditingValue(
        text: display,
        selection: TextSelection.collapsed(offset: at),
        composing: composing == null
            ? TextRange.empty
            : TextRange(
                start: offsets.toDisplay(composing.start),
                end: offsets.toDisplay(composing.end),
              ),
      );
    }
    onDataChanged?.call();
  }

  /// The IME composing range [c] of an edit (field text replaced in
  /// [p, editEnd), starting at model offset [start]) in model offsets, so
  /// it survives a re-layout of the display text (e.g. a new wrap).
  TextRange? _composing(TextRange c, int p, int editEnd, int start) {
    if (!c.isValid || c.isCollapsed || c.start > p || c.end < p || c.end > editEnd) return null;
    return TextRange(start: _offsets.toModel(c.start), end: start + c.end - p);
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final c = value.composing;
    final composing = withComposing && value.isComposingRangeValid
        ? TextRange(start: _offsets.toModel(c.start), end: _offsets.toModel(c.end))
        : TextRange.empty;
    final build = markerBuilder;
    return TextLayout.spanOf(
      data,
      underlined: composing,
      wraps: _wraps,
      marker: (m) => WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: build == null ? SizedBox.fromSize(size: m.size) : build(m),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Clipboard.

  /// Copies the selected text (and remembers its formatting); [cut] also
  /// deletes it.
  Future<void> copySelection({bool cut = false}) async {
    final r = modelSelection;
    if (r.isCollapsed) return;
    final text = _buffer.text.substring(r.start, r.end);
    _richClip = (text: text, styles: [for (var i = r.start; i < r.end; i++) _buffer.charStyle(i)]);
    await Clipboard.setData(ClipboardData(text: text));
    if (cut) {
      _buffer.replace(r.start, r.end, '', SpanStyle.plain);
      _pending = null;
      _changedKeeping(TextRange.collapsed(r.start));
    }
  }

  // ---------------------------------------------------------------------
  // Character formatting.

  /// The format at the caret (or of the selection's first character), as
  /// the toolbar shows it.
  SpanStyle get currentStyle {
    final r = modelSelection;
    if (r.isCollapsed) {
      if (_pending != null && _pendingAt == r.start) return _pending!;
      return _buffer.styleAt(r.start);
    }
    for (var i = r.start; i < r.end; i++) {
      if (_buffer.text.codeUnitAt(i) != 0x0A) return _buffer.charStyle(i);
    }
    return _buffer.styleAt(r.start);
  }

  /// The line of the caret (the selection's start).
  int get caretLine => _buffer.lineOf(modelSelection.start);

  /// The paragraph format of the caret's line.
  ParaStyle get currentPara => _buffer.para(caretLine);

  /// Font size at the caret, in world units.
  double get currentSize => TextLayout.sizeOf(_box, currentStyle, currentPara);

  /// Whether the selection (or the caret's typing style) passes [test].
  bool selectionHas(bool Function(SpanStyle) test) {
    final r = modelSelection;
    if (r.isCollapsed) return test(currentStyle);
    return _buffer.everyChar(r.start, r.end, test);
  }

  /// Applies [update] to the selected characters, or to what is typed next.
  void updateStyle(SpanStyle Function(SpanStyle) update) {
    final r = modelSelection;
    if (r.isCollapsed) {
      _pending = update(currentStyle);
      _pendingAt = r.start;
      notifyListeners();
      return;
    }
    _buffer.updateChars(r.start, r.end, update);
    _changedKeeping(r);
  }

  void toggleBold() {
    final on = !selectionHas((s) => s.bold);
    updateStyle((s) => s.copyWith(bold: on));
  }

  void toggleItalic() {
    final on = !selectionHas((s) => s.italic);
    updateStyle((s) => s.copyWith(italic: on));
  }

  void toggleUnderline() {
    final on = !selectionHas((s) => s.underline);
    updateStyle((s) => s.copyWith(underline: on));
  }

  void toggleStrike() {
    final on = !selectionHas((s) => s.strike);
    updateStyle((s) => s.copyWith(strike: on));
  }

  /// Text colour; in an empty box this sets the box colour.
  void setColor(int argb) {
    if (isEmpty) return setBox(_box.copyWith(color: argb));
    updateStyle((s) => s.withColor(argb == _box.color ? null : argb));
  }

  /// Highlight (background) colour, null for none.
  void setHighlight(int? argb) => updateStyle((s) => s.withHighlight(argb));

  /// Font size; in an empty box this sets the box size.
  void setSize(double size) {
    final v = size.clamp(TextData.minFontSize, TextData.maxFontSize).toDouble();
    if (isEmpty) return setBox(_box.copyWith(fontSize: v));
    updateStyle((s) => s.withSize(v));
  }

  /// Font; in an empty box this sets the box font.
  void setFont(TextFont font) {
    if (isEmpty) return setBox(_box.copyWith(font: font));
    updateStyle((s) => s.withFont(font == _box.font ? null : font));
  }

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

  // ---------------------------------------------------------------------
  // Paragraph formatting.

  ({int first, int last}) get _lines {
    final r = modelSelection;
    var last = _buffer.lineOf(r.end);
    // A selection ending at a line's start does not include that line.
    if (r.end > r.start && r.end == _buffer.lineStart(last) && last > 0) last--;
    return (first: _buffer.lineOf(r.start), last: last);
  }

  bool _allLines(bool Function(ParaStyle) test) {
    final (:first, :last) = _lines;
    for (var l = first; l <= last; l++) {
      if (!test(_buffer.para(l))) return false;
    }
    return true;
  }

  void _updateLines(ParaStyle Function(ParaStyle) update) {
    final (:first, :last) = _lines;
    final keep = modelSelection;
    _buffer.updateParas(first, last, update);
    _changedKeeping(keep);
  }

  /// Heading [level] (1, 2) for the selected lines; again → body text.
  void toggleHeading(int level) {
    final off = _allLines((p) => p.heading == level);
    _updateLines((p) => p.copyWith(heading: off ? 0 : level));
  }

  /// Sets heading [level] (0 = body text) for the selected lines.
  void setHeading(int level) => _updateLines((p) => p.copyWith(heading: level));

  /// Makes the selected lines a [kind] list; again → no list.
  void toggleList(ListKind kind) {
    final off = _allLines((p) => p.list == kind);
    _updateLines((p) => p.copyWith(list: off ? ListKind.none : kind));
  }

  /// Indents (or outdents, [delta] < 0) the selected list lines; false
  /// if none of them is a list item.
  bool indent(int delta) {
    if (_allLines((p) => !p.isList)) return false;
    _updateLines((p) => p.isList ? p.copyWith(indent: p.indent + delta) : p);
    return true;
  }

  /// Ticks or unticks the checklist item on [line].
  void toggleChecked(int line) {
    if (line < 0 || line >= _buffer.lineCount) return;
    final keep = modelSelection;
    _buffer.updateParas(line, line, (p) => p.copyWith(checked: !p.checked));
    _changedKeeping(keep);
  }
}
