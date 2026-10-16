import 'dart:math' as math;

import 'package:flutter/material.dart';
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
import 'text/text_box_reveal.dart';
import 'text_format_bar.dart';

part 'text_box_editor_handles.dart';

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
  final FocusNode _focus = FocusNode(debugLabel: 'TextBoxEditor');
  final GlobalKey _dockedBar = GlobalKey(debugLabel: 'docked format bar');
  final TextBoxReveal _reveal = TextBoxReveal();
  String? _editingId;

  TextEditSession get _session => widget.session;

  @override
  void initState() {
    super.initState();
    _text
      ..onDataChanged = _push
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
    _text.addListener(_onSelection);
    _onSession();
  }

  /// The field's text and formatting → the session.
  void _push() => _session.setData(_text.data);

  @override
  void dispose() {
    _session.removeListener(_onSession);
    if (identical(_session.boxHistory, _text)) _session.boxHistory = null;
    _text.dispose();
    _focus.dispose();
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
    _text.load(_session.data);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _editingId != null) _focus.requestFocus();
    });
  }

  /// The caret moved (arrows, a tap): keep it in view.
  void _onSelection() {
    final element = _session.current;
    if (element == null || !mounted || _text.selection == _revealedSelection) return;
    _scheduleReveal(element, _screenBounds(element));
  }

  TextSelection? _revealedSelection;

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
    final field = _focus.context?.findAncestorStateOfType<EditableTextState>();
    final editable = field?.renderEditable;
    if (editable == null || !editable.attached || !editable.hasSize) return null;
    final selection = _text.selection;
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

  Widget _editor(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_session, widget.viewport]),
      builder: (context, _) {
        final element = _session.current;
        if (element == null) return const SizedBox.shrink();
        final bounds = _screenBounds(element);
        _scheduleReveal(element, bounds);
        final scale = widget.viewport.scale;
        // The box sits on the paper, not the chrome: ink blue in both themes
        // (like the selection handles).
        const accent = AppTheme.seed;
        // The outline sits a few pixels outside the text, which is laid out
        // exactly as it renders.
        final pad = 6 / scale;
        final cursor = 2 / scale;
        final box = SizedBox(
          width: element.rect.width + RichTextField.caretMargin(cursor),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: -pad,
                top: -pad,
                right: -pad,
                bottom: -pad,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: accent.withValues(alpha: 0.7), width: 1.5 / scale),
                      borderRadius: BorderRadius.circular(4 / scale),
                    ),
                  ),
                ),
              ),
              TextSelectionTheme(
                data: TextSelectionThemeData(
                  selectionColor: accent.withValues(alpha: 0.25),
                  selectionHandleColor: accent,
                ),
                child: DefaultTextEditingShortcuts(
                  child: RichTextField(
                    controller: _text,
                    focusNode: _focus,
                    cursorWidth: cursor,
                    cursorColor: accent,
                    onDone: _session.end,
                    // Past the box's start, Ctrl+Z undoes the page's edits.
                    onUndo: _session.undo,
                    onRedo: _session.redo,
                  ),
                ),
              ),
            ],
          ),
        );
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 0,
              top: 0,
              child: Transform(
                transform: _matrix(element),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    box,
                    _grip(
                      scale,
                      accent,
                      pad: pad,
                      alignment: Alignment.topLeft,
                      icon: Symbols.open_with_sharp,
                      tooltip: 'Move',
                      onDrag: (d) => _session.setRect(_session.current!.rect.shift(d)),
                    ),
                    for (final side in [Alignment.centerLeft, Alignment.centerRight])
                      _grip(
                        scale,
                        accent,
                        pad: pad,
                        alignment: side,
                        icon: Symbols.drag_indicator_sharp,
                        tooltip: 'Width',
                        onDrag: (d) => _resize(side.x, d),
                      ),
                  ],
                ),
              ),
            ),
            TextFormatBar(
              anchor: bounds,
              dockedKey: _dockedBar,
              controller: _text,
              tools: widget.tools,
              onBoxChanged: (box) => widget.tools.textStyle = box,
              onDelete: () {
                _session.setData(const TextData());
                _session.end();
              },
              onDone: _session.end,
              refocus: _focus.requestFocus,
            ),
          ],
        );
      },
    );
  }
}
