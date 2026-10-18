import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../../domain/text/text_data.dart';
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
    if (await pasteClipboardFormatted(controller)) return;
    fallback?.invoke(intent);
  }
}

/// Ctrl+V's paste into [controller] but for plain text of one line (false:
/// the caller pastes it, see [RichPasteAction]): HTML or RTF formatted; in
/// a table cell, cells copied here and rows of tab-separated text fill
/// cells.
Future<bool> pasteClipboardFormatted(RichTextController controller) async {
  if (await pasteClipboardRich(controller)) return true;
  final text = controller is TableCellController ? await _clipboardText() : null;
  final own = text == null ? null : RichTextController.ownClip(text);
  if (own != null && TextTables.any(own.paras)) {
    controller.pasteRich(own);
    return true;
  }
  if (text != null && (text.contains('\t') || text.trimRight().contains('\n'))) {
    controller.pastePlain(text);
    return true;
  }
  return false;
}

/// Ctrl+V (Ctrl+Shift+V: [plain]) with a block of cells selected: the
/// clipboard replaces its top left cell, which [cell] then edits, and goes
/// on rightwards and down as a paste into that cell does.
Future<void> pasteIntoCells(TableCellController cell, {bool plain = false}) async {
  final box = cell.owner;
  final r = box.cellRange;
  final t = r == null ? null : box.tableAt(r.table);
  if (r == null || t == null) return;
  box.enterCell(t.lineOf(r.top, r.left));
  if (cell.line == null) return;
  cell.selection = TextSelection(baseOffset: 0, extentOffset: cell.text.length);
  if (!plain && await pasteClipboardFormatted(cell)) return;
  await pasteClipboardPlain(cell);
}
