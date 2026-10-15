import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../domain/text/text_data.dart';
import '../../../../ink/elements/text_layout.dart';
import '../../../../platform/clipboard_html.dart';
import 'rich_paste.dart';
import 'rich_text_controller.dart';

/// The text field of the box being edited, laid out in world units exactly
/// as the box renders, with formatting shortcuts:
///
/// Ctrl/⌘+B / I / U bold, italic, underline; Ctrl+Shift+X strikethrough;
/// Ctrl+V pastes HTML from other apps formatted, Ctrl+Shift+V as plain text;
/// Ctrl+Shift+7 / 8 / 9 numbered list, bullets, checklist; Ctrl+Alt+1 / 2
/// headings, Ctrl+Alt+0 body text; Tab / Shift+Tab indent list items;
/// Ctrl+Enter ticks a checklist item; Esc finishes. Left and right arrows
/// move the caret visually in right-to-left paragraphs too (left is
/// forwards there).
class RichTextField extends StatelessWidget {
  const RichTextField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.cursorWidth,
    required this.cursorColor,
    required this.onDone,
  });

  final RichTextController controller;
  final FocusNode focusNode;
  final double cursorWidth;
  final Color cursorColor;
  final VoidCallback onDone;

  /// Extra width the field needs beyond the text for its caret (see
  /// `RenderEditable`), so it wraps exactly where the box does.
  static double caretMargin(double cursorWidth) => 1 + cursorWidth;

  Map<ShortcutActivator, VoidCallback> get _bindings {
    final c = controller;
    final map = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.escape): onDone,
      const SingleActivator(LogicalKeyboardKey.tab): () => c.indent(1),
      const SingleActivator(LogicalKeyboardKey.tab, shift: true): () => c.indent(-1),
    };
    // (Browsers move the caret in their own text input.)
    if (!kIsWeb) map.addAll(_arrows);
    for (final control in [true, false]) {
      SingleActivator key(LogicalKeyboardKey k, {bool shift = false, bool alt = false}) =>
          SingleActivator(k, control: control, meta: !control, shift: shift, alt: alt);
      map.addAll({
        // The box's own undo: the field's knows no formatting.
        key(LogicalKeyboardKey.keyZ): c.undo,
        key(LogicalKeyboardKey.keyZ, shift: true): c.redo,
        key(LogicalKeyboardKey.keyY): c.redo,
        key(LogicalKeyboardKey.keyB): c.toggleBold,
        key(LogicalKeyboardKey.keyI): c.toggleItalic,
        key(LogicalKeyboardKey.keyU): c.toggleUnderline,
        key(LogicalKeyboardKey.keyX, shift: true): c.toggleStrike,
        // (Browsers paste plain text on their own.)
        if (!kIsWeb) key(LogicalKeyboardKey.keyV, shift: true): () => pasteClipboardPlain(c),
        key(LogicalKeyboardKey.digit7, shift: true): () => c.toggleList(ListKind.number),
        key(LogicalKeyboardKey.digit8, shift: true): () => c.toggleList(ListKind.bullet),
        key(LogicalKeyboardKey.digit9, shift: true): () => c.toggleList(ListKind.check),
        key(LogicalKeyboardKey.digit1, alt: true): () => c.toggleHeading(1),
        key(LogicalKeyboardKey.digit2, alt: true): () => c.toggleHeading(2),
        key(LogicalKeyboardKey.digit0, alt: true): () => c.setHeading(0),
        key(LogicalKeyboardKey.enter): () {
          if (c.currentPara.list == ListKind.check) c.toggleChecked(c.caretLine);
        },
      });
    }
    return map;
  }

  /// Left / right arrows (with Shift extending, with the word modifier by
  /// words), mirrored where the selection's extent is in a right-to-left
  /// paragraph: the field itself moves by logical order.
  Map<ShortcutActivator, VoidCallback> get _arrows {
    final apple = const {TargetPlatform.macOS, TargetPlatform.iOS}.contains(defaultTargetPlatform);
    void move({required bool right, required bool shift, required bool word}) {
      final context = primaryFocus?.context;
      if (context == null) return;
      final forward = right == (controller.extentDirection == TextDirection.ltr);
      final Intent intent = word
          ? ExtendSelectionToNextWordBoundaryIntent(forward: forward, collapseSelection: !shift)
          : ExtendSelectionByCharacterIntent(forward: forward, collapseSelection: !shift);
      Actions.maybeInvoke(context, intent);
    }

    return {
      for (final right in [false, true])
        for (final shift in [false, true])
          for (final word in [false, true])
            SingleActivator(
              right ? LogicalKeyboardKey.arrowRight : LogicalKeyboardKey.arrowLeft,
              shift: shift,
              control: word && !apple,
              alt: word && apple,
            ): () =>
                move(right: right, shift: shift, word: word),
    };
  }

  @override
  Widget build(BuildContext context) {
    final data = controller.data;
    return Actions(
      actions: {
        // Copy the box's text (not the marker placeholders) and remember
        // its formatting for pasting into another box.
        CopySelectionTextIntent: CallbackAction<CopySelectionTextIntent>(
          onInvoke: (intent) => controller.copySelection(cut: intent.collapseSelection),
        ),
        // HTML from other apps pastes formatted.
        PasteTextIntent: RichPasteAction(controller),
      },
      child: CallbackShortcuts(
        bindings: _bindings,
        // The canvas draws the box at its own size whatever the system text
        // size: the field matches it, so it wraps where the box does.
        // A browser copies the field's own text (with isolates and
        // breaks at wraps): while it has focus the box's text answers.
        child: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onFocusChange: (focused) => focused
              ? claimFieldCopies(controller, (cut) => controller.copyNow(cut: cut))
              : releaseFieldCopies(controller),
          child: MediaQuery.withNoTextScaling(
            child: TextField(
              key: const ValueKey('text-box-field'),
              controller: controller,
              focusNode: focusNode,
              maxLines: null,
              strutStyle: TextLayout.strutOf(data),
              style: TextLayout.baseStyle(data),
              textAlign: TextLayout.alignOf(data),
              textDirection: controller.plan.base,
              cursorColor: cursorColor,
              cursorWidth: cursorWidth,
              contextMenuBuilder: (context, state) => AdaptiveTextSelectionToolbar.buttonItems(
                anchors: state.contextMenuAnchors,
                buttonItems: [
                  for (final item in state.contextMenuButtonItems)
                    switch (item.type) {
                      ContextMenuButtonType.copy => item.copyWith(
                        onPressed: () {
                          controller.copySelection();
                          state.hideToolbar();
                        },
                      ),
                      ContextMenuButtonType.paste => item.copyWith(
                        onPressed: () async {
                          if (await pasteClipboardHtml(controller)) {
                            state.hideToolbar();
                          } else {
                            item.onPressed?.call();
                          }
                        },
                      ),
                      ContextMenuButtonType.cut => item.copyWith(
                        onPressed: () {
                          controller.copySelection(cut: true);
                          state.hideToolbar();
                        },
                      ),
                      _ => item,
                    },
                ],
              ),
              // Fully explicit, so the app's input theme (fill, padding, focus
              // outline) cannot shift the text off where the box renders it.
              decoration: const InputDecoration(
                isCollapsed: true,
                filled: false,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
