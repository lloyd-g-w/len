import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../../platform/clipboard_html.dart';
import 'clipboard_rich_text.dart';
import 'rich_text_controller.dart';

/// Pastes the clipboard's HTML (from a browser, Google Docs, Word, …) or,
/// without HTML, its RTF (WordPad, …) into [controller] as formatted text.
/// False — the caller pastes plain text — when there is neither, or the
/// text was copied from a box here (whose remembered formatting the plain
/// paste restores).
Future<bool> pasteClipboardRich(RichTextController controller) async {
  final text = await _clipboardText();
  if (text != null && RichTextController.isOwnClip(text)) return false;
  final rich = richTextOf(await readClipboardRich(), controller.box);
  if (rich == null) return false;
  controller.pasteRich(rich);
  return true;
}

/// Ctrl+Shift+V: the clipboard's text without any formatting.
Future<void> pasteClipboardPlain(RichTextController controller) async {
  final text = await _clipboardText();
  if (text != null && text.isNotEmpty) controller.pastePlain(text);
}

Future<String?> _clipboardText() async {
  try {
    return (await Clipboard.getData(Clipboard.kTextPlain))?.text;
  } catch (_) {
    return null;
  }
}

/// Overrides the text field's paste ([PasteTextIntent], Ctrl+V): formatted
/// text when the clipboard has HTML or RTF, else the field's own paste.
class RichPasteAction extends Action<PasteTextIntent> {
  RichPasteAction(this.controller);

  final RichTextController controller;

  @override
  bool get isActionEnabled => callingAction?.isActionEnabled ?? true;

  @override
  bool consumesKey(PasteTextIntent intent) => callingAction?.consumesKey(intent) ?? true;

  @override
  Future<void> invoke(PasteTextIntent intent) async {
    // Only set while this runs synchronously.
    final fallback = callingAction;
    if (!await pasteClipboardRich(controller)) fallback?.invoke(intent);
  }
}
