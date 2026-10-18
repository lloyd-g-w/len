import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OrdinalSortKey;
import 'package:material_symbols_icons/symbols.dart';

import '../../../domain/surface_element.dart';
import '../../../domain/text/text_data.dart';
import '../../../ink/elements/text_edit_session.dart';
import '../../../ink/elements/text_layout.dart';
import '../../../ink/tool_settings.dart';
import '../../../ink/viewport.dart';
import '../../../ui/app_theme.dart';
import 'text/list_marker_view.dart';
import 'text/rich_text_controller.dart';
import 'text/rich_text_field.dart';
import 'text/table_editor_layer.dart';
import 'text/text_box_reveal.dart';
import 'text_format_bar.dart';

part 'text_box_editor_handles.dart';
part 'text_box_editor_layout.dart';

/// Edits the session's text box in place: a real text field laid out in
/// world units (exactly as the box will render) and transformed by the
/// viewport, a grip to move it, grips on both sides to change its width,
/// and a formatting bar above it.
class TextBoxEditor extends StatefulWidget {
  const TextBoxEditor({
    super.key,
    required this.session,
    required this.viewport,
    required this.tools,
  });

  final TextEditSession session;
  final ViewportController viewport;
  final ToolSettings tools;

  @override
  State<TextBoxEditor> createState() => _TextBoxEditorState();
}

class _TextBoxEditorState extends State<TextBoxEditor> {
  final RichTextController _text = RichTextController(const TextData());
  late final TableCellController _cell = TableCellController(_text);
  final FocusNode _focus = FocusNode(debugLabel: 'TextBoxEditor');
  final FocusNode _cellFocus = FocusNode(debugLabel: 'TextBoxEditor cell');
  final FocusNode _rangeFocus = FocusNode(debugLabel: 'TextBoxEditor cells');
  final GlobalKey _dockedBar = GlobalKey(debugLabel: 'docked format bar');
  final TextBoxReveal _reveal = TextBoxReveal();
  String? _editingId;

  TextEditSession get _session => widget.session;

  @override
  void initState() {
    super.initState();
    _text
      ..onDataChanged = _push
      ..breaksOf = _session.breaksFor
      ..markerBuilder = (m) => ListMarkerView(
        marker: m,
        onToggle: () {
          _text.toggleChecked(m.line);
          _focus.requestFocus();
        },
      );
    _session
      ..boxHistory = _text
      ..addListener(_onSession);
    _text
      ..addListener(_onSelection)
      ..addListener(_onTable);
    _onSession();
  }

  /// The controller formatting acts on: the edited cell's, else the box's.
  RichTextController get _formatted => _text.activeCell != null ? _cell : _text;

  /// The focus of what is edited: a table cell, a block of cells, the box.
  FocusNode get _editing => _text.activeCell != null
      ? _cellFocus
      : _text.cellRange != null
      ? _rangeFocus
      : _focus;

  /// Gives the field being edited its focus (after a menu or sheet).
  void _refocus() => _editing.requestFocus();

  /// A table cell started or stopped being edited (or changed under it,
  /// as by undo): the cell's field follows, and the focus.
  void _onTable() {
    final line = _text.activeCell;
    if (line == null) {
      if (_cell.line == null) return;
      _cell.release();
    } else {
      final width = _text.cellWrapWidth(line);
      if (_cell.line != line || _cell.data != _text.cellData(line)) {
        _cell.edit(line, selection: _text.cellSelection, width: width);
      } else if (_cell.wrapWidth != width) {
        _cell.wrapWidth = width;
      }
    }
    final target = _editing;
    if (target.hasPrimaryFocus) return;
    if (target.context != null) return target.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _editingId != null && identical(target, _editing)) target.requestFocus();
    });
  }

  /// The field's text and formatting → the session.
  void _push() => _session.setData(_text.data);

  @override
  void dispose() {
    _session.removeListener(_onSession);
    if (identical(_session.boxHistory, _text)) _session.boxHistory = null;
    _cell.dispose();
    _text.dispose();
    _focus.dispose();
    _cellFocus.dispose();
    _rangeFocus.dispose();
    super.dispose();
  }

  /// A new box (or another box) started: load its text and focus it.
  void _onSession() {
    final element = _session.current;
    final id = element?.id;
    if (id == _editingId) {
      // The session may end auto width (box resized or grown to its limit).
      final auto = _session.data.autoWidth;
      if (id != null && _text.box.autoWidth != auto) {
        _text.adoptBox(_text.box.copyWith(autoWidth: auto));
      }
      // List items wrap with hanging indents at the box width.
      if (element != null) _text.wrapWidth = element.rect.width;
      // Not typed in yet: it follows the box changed elsewhere (sync, the
      // other pane).
      if (id != null && !_session.isEdited && _session.data != _text.data) {
        _text.load(_session.data);
      }
      return;
    }
    if (element != null) _text.wrapWidth = element.rect.width;
    _editingId = id;
    if (id == null) return;
    _cell.release();
    _text.load(_session.data, caret: _session.startCaret);
    _onTable();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _editingId != null) _refocus();
    });
  }

  /// The caret moved (arrows, a tap): keep it in view.
  void _onSelection() {
    final element = _session.current;
    if (element == null || !mounted || _text.selection == _revealedSelection) return;
    // Over pages, the format bar goes to the part with the caret.
    final frame = _session.frames.length < 2 ? 0 : _session.frameOf(_text.modelSelection.end);
    if (frame != _caretFrame) setState(() => _caretFrame = frame);
    _scheduleReveal(element, _revealBounds(element));
  }

  /// Measures how tall the field lays out the line of a page break's room
  /// and makes its placeholders that much shorter (see
  /// [RichTextController.roomExtra]), so text on the next page starts at its
  /// top margin, where it is stored.
  void _measureRooms() {
    if (!mounted) return;
    final breaks = _text.breaks;
    if (breaks.isEmpty) return;
    final at = _text.roomOffset(breaks.first);
    final editable = _focus.context?.findAncestorStateOfType<EditableTextState>()?.renderEditable;
    if (at == null || editable == null || !editable.attached || !editable.hasSize) return;
    final boxes = editable.getBoxesForSelection(
      TextSelection(baseOffset: at, extentOffset: at + 1),
    );
    if (boxes.isEmpty) return;
    final used = math.max(0.0, breaks.first.gap - _text.roomExtra);
    if (used == 0) return;
    final extra = boxes.first.bottom - boxes.first.top - used;
    if ((extra - _text.roomExtra).abs() > 0.01 && extra.abs() < used) _text.roomExtra = extra;
  }

  /// The part of the box to keep in view (on screen): where the caret is,
  /// when the text continues on other pages.
  Rect _revealBounds(SurfaceElement element) {
    final frames = _session.frames;
    if (frames.length < 2) return _screenBounds(element);
    final frame = frames[_session.frameOf(_text.modelSelection.end)];
    final v = widget.viewport;
    return Rect.fromPoints(v.toScreen(frame.topLeft), v.toScreen(frame.bottomRight));
  }

  TextSelection? _revealedSelection;

  /// Which of the session's frames the caret is in.
  int _caretFrame = 0;

  /// Keeps the caret clear of the keyboard and the docked bar (after this
  /// frame).
  void _scheduleReveal(SurfaceElement element, Rect bounds) {
    final docked = MediaQuery.sizeOf(context).width < TextFormatBar.dockBelowWidth;
    final padding = MediaQuery.paddingOf(context);
    final selection = _revealedSelection = _text.selection;
    _reveal.schedule(
      host: context,
      viewport: widget.viewport,
      state: (element.id, element.rect, element.rotation, selection),
      box: bounds,
      caret: _caretRect,
      bar: docked ? _dockedBar : null,
      top: padding.top + TextBoxReveal.gap,
      bottom: padding.bottom,
    );
  }

  /// The caret's rect in global coordinates, if the field is laid out.
  Rect? _caretRect() {
    if (!mounted || _session.current == null) return null; // The box ended.
    final inCell = _text.activeCell != null;
    final field = (inCell ? _cellFocus : _focus).context
        ?.findAncestorStateOfType<EditableTextState>();
    final editable = field?.renderEditable;
    if (editable == null || !editable.attached || !editable.hasSize) return null;
    final selection = inCell ? _cell.selection : _text.selection;
    if (!selection.isValid) return null;
    final local = editable.getLocalRectForCaret(selection.extent);
    return MatrixUtils.transformRect(editable.getTransformTo(null), local);
  }

  /// Converts a global pointer position to world coordinates.
  Offset _world(Offset global) {
    final box = context.findRenderObject()! as RenderBox;
    return widget.viewport.toWorld(box.globalToLocal(global));
  }

  @override
  Widget build(BuildContext context) {
    // The view only matters while a box is edited: no rebuild per pan frame
    // otherwise (it would lay out and repaint the editor).
    return ListenableBuilder(
      listenable: _session,
      builder: (context, _) => _session.current == null
          ? const SizedBox.shrink()
          // Back (Android's) finishes the box before it leaves the editor.
          : PopScope(
              canPop: false,
              onPopInvokedWithResult: (didPop, _) {
                if (!didPop) _session.end();
              },
              child: _editor(context),
            ),
    );
  }
}
