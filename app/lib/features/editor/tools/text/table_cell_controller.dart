part of 'rich_text_controller.dart';

/// The field controller of the table cell being edited: a
/// [RichTextController] over the cell's text alone (one line, the box's
/// defaults), so typing, the IME, inline formatting and shortcuts work as
/// in the box. Every change goes on into [owner] (`setCell`), whose history
/// is the box's; its own history only measures typing runs.
class TableCellController extends RichTextController {
  TableCellController(this.owner) : super(const TextData()) {
    _history.onChanged = _changed;
    addListener(_selected);
  }

  /// The controller of the box the cell is in.
  final RichTextController owner;

  /// The line of the cell edited (null: none).
  int? get line => _line;
  int? _line;

  @override
  RichTextController get boxController => owner;

  /// Edits the cell on [line] of [owner], its selection [selection] (cell
  /// offsets; the start by default), wrapped at [width].
  void edit(int line, {TextSelection? selection, required double width}) {
    _line = null; // Not passed on while loading.
    wrapWidth = width;
    load(owner.cellData(line));
    final s = selection ?? const TextSelection.collapsed(offset: 0);
    final n = _buffer.length;
    _sync(
      s.copyWith(baseOffset: s.baseOffset.clamp(0, n), extentOffset: s.extentOffset.clamp(0, n)),
    );
    _line = line;
  }

  /// Stops passing changes on (the cell is no longer edited).
  void release() => _line = null;

  void _changed(HistoryStep step) {
    final line = _line;
    if (line == null) return;
    final sel = selection.isValid
        ? _modelSelection(selection)
        : TextSelection.collapsed(offset: _buffer.length);
    owner.setCell(line, data, sel, step);
    // A cell holds one line: a pasted break became a space there.
    if (owner.cellData(line).text != _buffer.text) {
      edit(line, selection: sel, width: wrapWidth);
    }
  }

  void _selected() {
    final line = _line;
    if (line == null || !selection.isValid) return;
    // An edit on its way: its selection comes with it (setCell).
    if (owner.cellData(line).text != _buffer.text) return;
    owner.selectInCell(
      _modelSelection(selection),
      composing: value.composing.isValid && !value.composing.isCollapsed,
    );
  }

  /// Undo and redo are the box's.
  @override
  bool undo() => owner.undo();

  @override
  bool redo() => owner.redo();

  @override
  bool get canUndo => owner.canUndo;

  @override
  bool get canRedo => owner.canRedo;

  /// Font, size and colour in an empty cell format what is typed next,
  /// not the box.
  @override
  bool get isEmpty => false;

  /// Alignment and paragraph spacing are the box's.
  @override
  void setBox(TextData box) {
    owner.setBox(owner.box.copyWith(align: box.align, spacing: box.spacing));
    adoptBox(_box.copyWith(align: box.align));
  }

  @override
  void dispose() {
    removeListener(_selected);
    super.dispose();
  }
}
