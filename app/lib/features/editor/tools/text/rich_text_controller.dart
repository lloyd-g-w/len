import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../../../domain/text/html_text.dart';
import '../../../../domain/text/html_writer.dart';
import '../../../../domain/text/rich_text_buffer.dart';
import '../../../../domain/text/text_data.dart';
import '../../../../ink/elements/text_edit_session.dart' show BoxHistory;
import '../../../../ink/elements/text_layout.dart';
import '../../../../platform/clipboard_html.dart';
import '../../clipboard/rich_clipboard.dart';

part 'rich_text_formatting.dart';
part 'rich_text_history.dart';
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
class RichTextController extends _RichTextState with _RichTextFormatting implements BoxHistory {
  RichTextController(super.data);

  /// Text copied from a box here, with its formatting (Len's own clipboard
  /// format): pasting the same plain text keeps the formatting.
  static TextData? _clip;

  /// Whether [text] was last copied from a box here (pasting it keeps
  /// that formatting, so it wins over the clipboard's HTML).
  static bool isOwnClip(String text) => _clip?.text == _clean(text);

  /// [text] without marker placeholders and bidi isolates (the layout's,
  /// in text a browser copied from the field), its line breaks all \n.
  static String _clean(String text) => text
      .replaceAll(RegExp('[\uFFFC\u2066-\u2069]'), '')
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n');

  /// [text] from the clipboard as a new box formatted like [box]; text
  /// last copied from a box here keeps its formatting.
  static TextData pasted(String text, TextData box) {
    final clean = _clean(text);
    final clip = _clip;
    final base = box.copyWith(text: clean);
    if (clip == null || clip.text != clean) return base;
    return base.withFormatting(spans: clip.spans, paras: clip.paras);
  }

  @override
  set value(TextEditingValue next) {
    final old = super.value;
    if (next.text == old.text) {
      final sel = _normalize(next.selection, old.selection);
      if (sel != old.selection) _pending = null;
      super.value = next.copyWith(selection: sel);
      if (sel.isValid) _history.select(_modelSelection(sel));
      return;
    }
    _applyEdit(old, next);
  }

  /// Keeps the caret off the spot before a list marker (and inside a wrap's
  /// or an isolate's insert): it steps over it in the direction it was
  /// moving, or to the nearest spot after a jump.
  TextSelection _normalize(TextSelection s, TextSelection old) {
    if (!s.isValid || _offsets.isEmpty) return s;
    int fix(int d, int was) {
      if (!_offsets.isHidden(d)) return d;
      final step = was == d + 1 ? -1 : (was == d - 1 ? 1 : 0);
      return _offsets.allowedNear(d, text.length, step: step);
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
    if (inserted.isEmpty && start == end && removedEnd > p && unlisted.isEmpty) {
      // Only inserted characters deleted (a wrap's break or gap, an
      // isolate, padding): delete the character before (backspace at a
      // line's start) or after (delete at its end) instead.
      final back = was.isValid && was.isCollapsed
          ? was.extentOffset >= removedEnd
          : o.codeUnitAt(removedEnd - 1) == PlaceholderSpan.placeholderCodeUnit;
      if (back) {
        if (start > 0) start--;
      } else if (end < _buffer.length) {
        end++;
      }
    }
    // A run of typed (or backspaced) characters is one undo step.
    final typed = inserted.length == 1 && start == end && inserted != '\n';
    final backspaced = inserted.isEmpty && end == start + 1;
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
    final clip = _clip;
    final style = _pending != null && _pendingAt == start
        ? _pending!
        : end > start && _buffer.text.codeUnitAt(start) != 0x0A
        ? _buffer.charStyle(start)
        : _buffer.styleAt(start);
    // Text copied from a box here keeps its formatting; a browser paste
    // (web) of HTML from another app is formatted.
    final rich = inserted.isEmpty
        ? null
        : clip?.text == inserted
        ? clip
        : _pastedHtml(inserted);
    if (rich != null) {
      _buffer.insertRich(start, end, rich, style);
      inserted = rich.text;
    } else {
      _buffer.replace(start, end, inserted, style);
    }
    for (final l in unlisted) {
      _buffer.updateParas(l, l, (p) => p.copyWith(list: ListKind.none));
    }
    _pending = null;
    _data = null;
    final plan = _planOf(data);
    final offsets = plan.offsets;
    final display = offsets.display(_buffer.text);
    _plan = plan;
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
    _history.changed(
      _snapshot,
      runFrom: typed && rich == null ? start : (backspaced ? end : -1),
      runTo: typed && rich == null && inserted.trim().isNotEmpty
          ? start + 1
          : (backspaced ? start : -1),
      deletes: backspaced,
      composing: next.composing.isValid && !next.composing.isCollapsed,
    );
    onDataChanged?.call();
    if (typed && inserted == ' ' && rich == null) _autoList(start);
  }

  /// What typed at a plain line's start, before a space, starts a list.
  static const Map<String, ListKind> listPrefixes = {
    '-': ListKind.bullet,
    '*': ListKind.bullet,
    '•': ListKind.bullet,
    '1.': ListKind.number,
    '1)': ListKind.number,
    '[]': ListKind.check,
    '[ ]': ListKind.check,
  };

  /// A space just typed at [space] after one of [listPrefixes] at the start
  /// of a line that is no list: the line becomes that list, the prefix
  /// goes. A step of its own, so undo gives the typed characters back.
  void _autoList(int space) {
    final line = _buffer.lineOf(space);
    if (_buffer.para(line).isList) return;
    final from = _buffer.lineStart(line);
    final kind = listPrefixes[_buffer.text.substring(from, space)];
    if (kind == null) return;
    _buffer
      ..replace(from, space + 1, '', _buffer.styleAt(from))
      ..updateParas(line, line, (p) => p.copyWith(list: kind));
    _pending = null;
    _changedKeeping(TextRange.collapsed(from));
  }

  @override
  bool get canUndo => _history.canUndo;

  @override
  bool get canRedo => _history.canRedo;

  /// Undoes the last change in the box, formatting included; false when
  /// there is none.
  @override
  bool undo() => _restore(_history.undo(_snapshot));

  /// Redoes the change undone last; false when there is none.
  @override
  bool redo() => _restore(_history.redo(_snapshot));

  bool _restore(_Snapshot? state) {
    if (state == null) return false;
    // Auto width is the session's (it ends when the box is resized).
    _box = state.data.copyWith(autoWidth: _box.autoWidth);
    _buffer = RichTextBuffer(state.data);
    _pending = null;
    _sync(state.selection);
    onDataChanged?.call();
    return true;
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
      _plan,
      underlined: composing,
      marker: (m) => WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: build == null ? SizedBox.fromSize(size: m.size) : build(m),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Clipboard.

  /// Copies the selected text — plain, and as HTML for other apps — and
  /// remembers its formatting; [cut] also deletes it.
  Future<void> copySelection({bool cut = false}) async {
    final r = modelSelection;
    if (r.isCollapsed) return;
    final clip = _clip = _buffer.slice(r.start, r.end, _box);
    await writeRichClipboard(clip.text, htmlFromText(clip));
    if (cut) _cut(r);
  }

  /// The selected text, plain and as HTML, for a browser's copy or cut
  /// event (which the field's own text, with its layout inserts, must not
  /// answer); remembers its formatting, and [cut] deletes it. Null when
  /// nothing is selected.
  ({String plain, String html})? copyNow({bool cut = false}) {
    final r = modelSelection;
    if (r.isCollapsed) return null;
    final clip = _clip = _buffer.slice(r.start, r.end, _box);
    if (cut) _cut(r);
    return (plain: clip.text, html: htmlFromText(clip));
  }

  void _cut(TextRange r) {
    _buffer.replace(r.start, r.end, '', SpanStyle.plain);
    _pending = null;
    _changedKeeping(TextRange.collapsed(r.start));
  }

  @override
  void dispose() {
    releaseFieldCopies(this);
    super.dispose();
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
