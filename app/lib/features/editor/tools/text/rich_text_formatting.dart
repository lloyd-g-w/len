part of 'rich_text_controller.dart';

/// Formatting commands of a [RichTextController]: character formats act on
/// the selection (or, with a collapsed caret, on what is typed next),
/// paragraph formats on the selected lines.
mixin _RichTextFormatting on _RichTextState {
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

  /// The direction of the caret's paragraph.
  TextDirection get caretDirection => ParagraphDirection.of(_buffer.text)[caretLine];

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
