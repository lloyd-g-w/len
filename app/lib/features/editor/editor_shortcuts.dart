import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ink/tool_settings.dart';
import '../search/editor/editor_search_controller.dart';
import '../search/editor/editor_search_layer.dart';
import '../settings/keyboard_shortcuts.dart';
import 'canvas/canvas_shortcuts.dart';
import 'document/document_shortcuts.dart';
import 'editor_session.dart';
import 'pdf/pdf_layer.dart';
import 'tabs/open_notebooks.dart';
import 'tools/content_shortcuts.dart';

/// Whether a text field (or a text box being edited) has the keyboard.
bool isTyping() {
  // The focus node belongs to a Focus widget inside the EditableText.
  final focused = FocusManager.instance.primaryFocus?.context;
  return focused != null &&
      (focused.widget is EditableText ||
          focused.findAncestorWidgetOfExactType<EditableText>() != null);
}

/// Wraps a single-key shortcut so it doesn't fire while text is edited.
VoidCallback unlessTyping(VoidCallback action) => () {
  if (!isTyping()) action();
};

/// Whether [event] types a character into the text being edited (no
/// Ctrl, Alt or ⌘): the editor lets it through to the platform's text
/// input untouched, as Flutter does for Space, instead of letting a
/// single-key shortcut swallow it.
bool typesCharacter(KeyEvent event) => isTyping() && typedCharacter(event) != null;

/// The printable character [event] types (no Ctrl, Alt or ⌘), if any.
String? typedCharacter(KeyEvent event) {
  if (event is KeyUpEvent) return null;
  final character = event.character;
  if (character == null || character.isEmpty || character.codeUnitAt(0) < 0x20) return null;
  if (character.codeUnitAt(0) == 0x7f) return null;
  final keyboard = HardwareKeyboard.instance;
  if (keyboard.isControlPressed || keyboard.isAltPressed || keyboard.isMetaPressed) return null;
  return character;
}

const _digitKeys = [
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4,
  LogicalKeyboardKey.digit5,
];

/// The editor's keyboard shortcuts: undo/redo, tools, quick colours and
/// widths, selection (Ctrl/⌘+A selects all on the page or in view; arrows
/// nudge a selection 1 pt, Shift+arrows 10 pt), focus mode and tabs, plus
/// canvas navigation ([canvasShortcuts]) or page navigation
/// ([documentShortcuts]), whose arrows apply when nothing is selected.

/// How far an arrow key nudges a selection (world units: points on a page),
/// and with Shift.
const double nudgeStep = 1, nudgeStepLarge = 10;
Map<ShortcutActivator, VoidCallback> editorShortcuts(
  EditorSession session, {
  required VoidCallback toggleFocus,
  VoidCallback? nextTab,
  VoidCallback? previousTab,
  VoidCallback? closeTab,
  VoidCallback? paste,
  VoidCallback? pastePlain,
}) {
  final undo = session.undo;
  final prefs = session.services.preferences;
  final tools = session.tools;
  final selection = session.content.selection;
  final doc = session.doc;
  void selectAll() =>
      session.content.selectAllIn(doc?.pageViewport.contentBounds ?? session.viewport.visibleWorld);
  final nav = <ShortcutActivator, VoidCallback>{
    if (session.canvasNav case final canvas?)
      ...canvasShortcuts(
        canvas,
        unlessTyping,
        toggleMinimap: () => prefs.canvasMinimap = !prefs.canvasMinimap,
      ),
    if (doc != null) ...documentShortcuts(doc, session.docAnimator!, unlessTyping),
  };
  final arrows = {
    LogicalKeyboardKey.arrowLeft: const Offset(-1, 0),
    LogicalKeyboardKey.arrowRight: const Offset(1, 0),
    LogicalKeyboardKey.arrowUp: const Offset(0, -1),
    LogicalKeyboardKey.arrowDown: const Offset(0, 1),
  };
  bool isArrow(ShortcutActivator a, {bool? large}) => switch (a) {
    SingleActivator(:final trigger, :final shift) =>
      arrows.containsKey(trigger) && (large == null || shift == large),
    _ => false,
  };
  // Arrows nudge the selection, else navigate as [nav] binds them
  // (activators have no value equality, so look them up by key).
  VoidCallback arrow(LogicalKeyboardKey key, Offset direction, {required bool large}) {
    final fallback = nav.entries
        .where((e) => isArrow(e.key, large: large) && (e.key as SingleActivator).trigger == key)
        .map((e) => e.value)
        .firstOrNull;
    return unlessTyping(() {
      if (!selection.isEmpty) {
        selection.nudge(direction * (large ? nudgeStepLarge : nudgeStep));
      } else {
        fallback?.call();
      }
    });
  }

  return {
    for (final mod in [(control: true, meta: false), (control: false, meta: true)]) ...{
      SingleActivator(LogicalKeyboardKey.keyZ, control: mod.control, meta: mod.meta): undo.undo,
      SingleActivator(LogicalKeyboardKey.keyZ, control: mod.control, meta: mod.meta, shift: true):
          undo.redo,
      SingleActivator(LogicalKeyboardKey.period, control: mod.control, meta: mod.meta): toggleFocus,
      SingleActivator(LogicalKeyboardKey.keyW, control: mod.control, meta: mod.meta): ?closeTab,
      SingleActivator(LogicalKeyboardKey.keyA, control: mod.control, meta: mod.meta): unlessTyping(
        selectAll,
      ),
    },
    const SingleActivator(LogicalKeyboardKey.keyY, control: true): undo.redo,
    const SingleActivator(LogicalKeyboardKey.f11): toggleFocus,
    const SingleActivator(LogicalKeyboardKey.tab, control: true): ?nextTab,
    const SingleActivator(LogicalKeyboardKey.tab, control: true, shift: true): ?previousTab,
    const SingleActivator(LogicalKeyboardKey.keyP): unlessTyping(() => tools.pick(EditorTool.pen)),
    const SingleActivator(LogicalKeyboardKey.keyH): unlessTyping(
      () => tools.pick(EditorTool.highlighter),
    ),
    const SingleActivator(LogicalKeyboardKey.keyE): unlessTyping(
      () => tools.pick(EditorTool.eraser),
    ),
    const SingleActivator(LogicalKeyboardKey.keyM): unlessTyping(session.toggleZoomWindow),
    // 1–5: quick colours of the pen / highlighter; [ and ]: thinner / thicker.
    // (Shift+1 and 0 belong to the canvas shortcuts.)
    for (final (i, key) in _digitKeys.indexed)
      SingleActivator(key): unlessTyping(() => tools.selectColor(i)),
    const SingleActivator(LogicalKeyboardKey.bracketLeft): unlessTyping(() => tools.stepWidth(-1)),
    const SingleActivator(LogicalKeyboardKey.bracketRight): unlessTyping(() => tools.stepWidth(1)),
    ...contentShortcuts(session.content, tools, unlessTyping, paste: paste, pastePlain: pastePlain),
    for (final e in nav.entries)
      if (!isArrow(e.key)) e.key: e.value,
    for (final MapEntry(:key, value: direction) in arrows.entries) ...{
      SingleActivator(key): arrow(key, direction, large: false),
      SingleActivator(key, shift: true): arrow(key, direction, large: true),
    },
  };
}

/// Everything the editor screen binds: [editorShortcuts] (with tab
/// switching when it shows [tabs]), F5 [present] (focus mode with the
/// laser), [turnPage] (Space and Shift+Space, in focus mode), Ctrl/⌘+E
/// [export], Ctrl/⌘+P [print], Ctrl/⌘+G [goToPage], search and PDF text (Ctrl/⌘+C then
/// calls [pdfCopied], to say so as the menu's Copy does).
Map<ShortcutActivator, VoidCallback> editorScreenShortcuts(
  EditorSession session, {
  required VoidCallback present,
  ValueChanged<int>? turnPage,
  required EditorSearchController search,
  required VoidCallback toggleFocus,
  required VoidCallback paste,
  VoidCallback? pastePlain,
  OpenNotebooks? tabs,
  VoidCallback? closeTab,
  VoidCallback? export,
  VoidCallback? print,
  VoidCallback? goToPage,
  VoidCallback? pageSidebar,
  VoidCallback? shortcutsHelp,
  VoidCallback? pdfCopied,
}) => _alongside({
  ...editorShortcuts(
    session,
    toggleFocus: toggleFocus,
    nextTab: tabs?.cycle,
    previousTab: tabs == null ? null : () => tabs.cycle(backwards: true),
    closeTab: closeTab,
    paste: paste,
    pastePlain: pastePlain,
  ),
  const SingleActivator(LogicalKeyboardKey.f5): present,
  if (shortcutsHelp != null) ...keyboardShortcutsBinding(shortcutsHelp),
  if (export != null) ...{
    const SingleActivator(LogicalKeyboardKey.keyE, control: true): export,
    const SingleActivator(LogicalKeyboardKey.keyE, meta: true): export,
  },
  if (print != null) ...{
    const SingleActivator(LogicalKeyboardKey.keyP, control: true): print,
    const SingleActivator(LogicalKeyboardKey.keyP, meta: true): print,
  },
  if (goToPage != null) ...{
    const SingleActivator(LogicalKeyboardKey.keyG, control: true): goToPage,
    const SingleActivator(LogicalKeyboardKey.keyG, meta: true): goToPage,
  },
  const SingleActivator(LogicalKeyboardKey.f4): ?pageSidebar,
  if (turnPage != null) ...{
    const SingleActivator(LogicalKeyboardKey.space): unlessTyping(() => turnPage(1)),
    const SingleActivator(LogicalKeyboardKey.space, shift: true): unlessTyping(() => turnPage(-1)),
  },
  ...EditorSearchLayer.shortcuts(search),
}, session.pdf == null ? const {} : pdfShortcuts(session.pdf!, copied: pdfCopied));

/// [base] with [extra] added; a key both bind runs both (in a map literal
/// the later binding would replace the earlier: the PDF's Escape used to
/// replace the lasso's, so Escape never dropped a selection in notebooks).
Map<ShortcutActivator, VoidCallback> _alongside(
  Map<ShortcutActivator, VoidCallback> base,
  Map<ShortcutActivator, VoidCallback> extra,
) {
  final out = {...base};
  extra.forEach((key, action) {
    final first = out[key];
    out[key] = first == null
        ? action
        : () {
            first();
            action();
          };
  });
  return out;
}
