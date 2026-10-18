part of 'rich_text_controller.dart';

/// Copying, cutting and pasting in a [RichTextController]: plain text, HTML
/// for other apps, and Len's own formatting for text copied from a box here.
mixin _RichTextClipboard on _RichTextState, _RichTextFormatting, _RichTextTables {
  /// Copies the selected text — plain, and as HTML for other apps — and
  /// remembers its formatting; [cut] also deletes it.
  Future<void> copySelection({bool cut = false}) async {
    final copied = copyNow(cut: cut);
    if (copied != null) await writeRichClipboard(copied.plain, copied.html);
  }

  /// The selected text, plain and as HTML, for a browser's copy or cut
  /// event (which the field's own text, with its layout inserts, must not
  /// answer); remembers its formatting, and [cut] deletes it. Null when
  /// nothing is selected.
  ({String plain, String html})? copyNow({bool cut = false}) {
    final TextData clip;
    if (_range != null) {
      // A block of cells: a table of them; cutting empties them.
      final block = rangeData;
      if (block == null) return null;
      clip = RichTextController._clip = block;
      if (cut) clearCells();
    } else {
      final r = modelSelection;
      if (r.isCollapsed) return null;
      clip = RichTextController._clip = _buffer.slice(r.start, r.end, _box);
      if (cut) _cut(r);
    }
    return (plain: TextTables.plainText(clip.text, clip.paras), html: htmlFromText(clip));
  }

  void _cut(TextRange r) {
    _buffer.replace(r.start, r.end, '', SpanStyle.plain);
    _pending = null;
    _changedKeeping(TextRange.collapsed(r.start));
  }

  /// The formatted text of a browser paste (web) that inserted [inserted].
  TextData? _pastedRich(String inserted) {
    final clip = richPastedAs(inserted);
    return clip == null ? null : richTextOf(clip, _box);
  }

  /// Pastes formatted text from another app over the selection.
  void pasteRich(TextData fragment) {
    final r = modelSelection;
    if (TextTables.any(fragment.paras)) {
      // Tables go in as whole lines.
      final after = _buffer.insertFragment(r.start, r.end, fragment);
      _pending = null;
      return _changedKeeping(TextRange.collapsed(after));
    }
    _buffer.insertRich(r.start, r.end, fragment, _buffer.styleAt(r.start));
    _pending = null;
    _changedKeeping(TextRange.collapsed(r.start + fragment.text.length));
  }

  /// Pastes [text] without formatting over the selection (it takes the
  /// caret's style).
  void pastePlain(String text) {
    final r = modelSelection;
    final clean = RichTextController._clean(text);
    _buffer.replace(r.start, r.end, clean, currentStyle);
    _pending = null;
    _changedKeeping(TextRange.collapsed(r.start + clean.length));
  }
}
