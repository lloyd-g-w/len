import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../domain/text/text_data.dart';
import '../../../../ink/elements/text_layout.dart';
import 'rich_text_controller.dart';

/// The text field of the box being edited, laid out in world units exactly
/// as the box renders, with formatting shortcuts:
///
/// Ctrl/⌘+B / I / U bold, italic, underline; Ctrl+Shift+X strikethrough;
/// Ctrl+Shift+7 / 8 / 9 numbered list, bullets, checklist; Ctrl+Alt+1 / 2
/// headings, Ctrl+Alt+0 body text; Tab / Shift+Tab indent list items;
/// Ctrl+Enter ticks a checklist item; Esc finishes.
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
    for (final control in [true, false]) {
      SingleActivator key(LogicalKeyboardKey k, {bool shift = false, bool alt = false}) =>
          SingleActivator(k, control: control, meta: !control, shift: shift, alt: alt);
      map.addAll({
        key(LogicalKeyboardKey.keyB): c.toggleBold,
        key(LogicalKeyboardKey.keyI): c.toggleItalic,
        key(LogicalKeyboardKey.keyU): c.toggleUnderline,
        key(LogicalKeyboardKey.keyX, shift: true): c.toggleStrike,
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
      },
      child: CallbackShortcuts(
        bindings: _bindings,
        child: TextField(
          key: const ValueKey('text-box-field'),
          controller: controller,
          focusNode: focusNode,
          maxLines: null,
          strutStyle: StrutStyle.disabled,
          style: TextLayout.baseStyle(data),
          textAlign: TextLayout.alignOf(data),
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
    );
  }
}
