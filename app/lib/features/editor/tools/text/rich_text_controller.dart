import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../../domain/text/html_text.dart';
import '../../../../domain/text/rich_text_buffer.dart';
import '../../../../domain/text/text_data.dart';
import '../../../../ink/elements/text_layout.dart';
import '../../../../platform/clipboard_html.dart';

part 'rich_text_formatting.dart';
part 'rich_text_state.dart';

/// The text field controller of a text box being edited: keeps the
/// formatted text in a [RichTextBuffer] and renders it with
/// [TextLayout.spanOf], exactly like the canvas does.
///
/// The field's text is the *display* text: the box's text with one
/// placeholder character before each list line, where the marker widget
/// sits, and a break plus an indent gap where a list item wraps at
/// [wrapWidth] (hanging indents, see [MarkerOffsets] and [TextWraps]).
/// Edits the field makes are mapped back onto the buffer; formatting
/// commands act on the selection (or, with a collapsed caret, on what is
/// typed next, see [_RichTextFormatting]).
class RichTextController extends _RichTextState with _RichTextFormatting {
  RichTextController(super.data);

  /// Text copied from a box here, with its formatting: pasting the same
  /// plain text keeps the formatting.
  static ({String text, List<SpanStyle> styles})? _richClip;

  /// Whether [text] was last copied from a box here (pasting it keeps
  /// that formatting, so it wins over the clipboard's HTML).
  static bool isOwnClip(String text) => _richClip?.text == _clean(text);

  /// [text] without marker placeholders, its line breaks all \n.
  static String _clean(String text) =>
      text.replaceAll('\uFFFC', '').replaceAll('\r\n', '\n').replaceAll('\r', '\n');

  /// [text] from the clipboard as a new box formatted like [box]; text
  /// last copied from a box here keeps its formatting.
  static TextData pasted(String text, TextData box) {
    final clean = _clean(text);
    final clip = _richClip;
    final base = box.copyWith(text: clean);
    if (clip == null || clip.text != clean) return base;
    return base.withFormatting(spans: TextData.compact(clip.styles));
  }

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
    // Text typed or pasted over the selection replaces all of it, even where
    // it starts or ends like the selection (a paste must match the clip).
    final was = old.selection;
    if (was.isValid && !was.isCollapsed && caret >= was.start && _replaces(o, n, was, caret)) {
      p = was.start;
      s = o.length - was.end;
    }
    final removedEnd = o.length - s;
    var inserted = _clean(n.substring(p, n.length - s));
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
    // A browser paste (web) of HTML from another app: formatted.
    final rich = inserted.isEmpty || clip?.text == inserted ? null : _pastedHtml(inserted);
    if (rich != null) {
      _buffer.insertRich(start, end, rich, style);
      inserted = rich.text;
    } else {
      _buffer.replace(start, end, inserted, style);
    }
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

  /// Whether [n] is [o] with its [selection] replaced by the text up to
  /// [caret].
  static bool _replaces(String o, String n, TextSelection selection, int caret) {
    final tail = o.length - selection.end;
    return n.length - caret == tail &&
        n.startsWith(o.substring(0, selection.start)) &&
        n.endsWith(o.substring(selection.end));
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

  TextData? _pastedHtml(String inserted) {
    final html = htmlPastedAs(inserted);
    return html == null ? null : textFromHtml(html, _box);
  }

  /// Pastes formatted text from another app over the selection.
  void pasteRich(TextData fragment) {
    final r = modelSelection;
    _buffer.insertRich(r.start, r.end, fragment, _buffer.styleAt(r.start));
    _pending = null;
    _changedKeeping(TextRange.collapsed(r.start + fragment.text.length));
  }

  /// Pastes [text] without formatting over the selection (it takes the
  /// caret's style).
  void pastePlain(String text) {
    final r = modelSelection;
    final clean = _clean(text);
    _buffer.replace(r.start, r.end, clean, currentStyle);
    _pending = null;
    _changedKeeping(TextRange.collapsed(r.start + clean.length));
  }
}
