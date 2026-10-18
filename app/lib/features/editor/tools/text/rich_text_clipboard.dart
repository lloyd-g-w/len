part of 'rich_text_controller.dart';

/// Copying, cutting and pasting in a [RichTextController]: plain text, HTML
/// for other apps, and Len's own formatting for text copied from a box here.
mixin _RichTextClipboard on _RichTextState, _RichTextFormatting {
  /// Copies the selected text — plain, and as HTML for other apps — and
  /// remembers its formatting; [cut] also deletes it.
  Future<void> copySelection({bool cut = false}) async {
    final r = modelSelection;
    if (r.isCollapsed) return;
    final clip = RichTextController._clip = _buffer.slice(r.start, r.end, _box);
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
    final clip = RichTextController._clip = _buffer.slice(r.start, r.end, _box);
    if (cut) _cut(r);
    return (plain: clip.text, html: htmlFromText(clip));
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
