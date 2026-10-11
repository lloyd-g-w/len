import 'package:flutter/material.dart';

import '../../../domain/link_target.dart';
import '../../../domain/stickers/sticker.dart';
import '../../../ink/tool_settings.dart';
import '../../../ui/messages.dart';
import '../../stickers/save_sticker_dialog.dart';
import '../../stickers/sticker_library.dart';
import '../editor_session.dart';
import '../tools/selection_menu.dart';

/// Stickers in one open notebook: the panel's visibility, inserting a
/// sticker (selected, ready to move) and saving the lasso selection as one.
class EditorStickers {
  EditorStickers(this.session);

  final EditorSession session;

  /// Whether the sticker panel is shown.
  final ValueNotifier<bool> open = ValueNotifier(false);

  StickerLibrary? _library;

  /// The library, loaded when first needed.
  StickerLibrary get library =>
      _library ??= StickerLibrary(session.services.stickers, sync: session.services.sync);

  void toggle() => open.value = !open.value;

  /// Puts a copy of [sticker] centred on [screen] (default: the middle of
  /// the screen) as one undoable edit and selects it with the lasso.
  void insert(Sticker sticker, {Offset? screen}) {
    final content = session.content;
    final c = sticker.content;
    session.tools.tool = EditorTool.lasso;
    final Offset world;
    if (screen != null) {
      session.doc?.activateAt(screen);
      world = session.viewport.toWorld(screen);
    } else {
      content.beforePasteAtCentre?.call();
      world = session.viewport.visibleWorld.center;
    }
    content.selection.place(c.strokes, c.elements, c.bounds, world);
  }

  /// Asks for a name and category and saves the lasso selection (without
  /// its links) as a sticker.
  Future<void> saveSelection(BuildContext context) async {
    final selection = session.content.selection;
    final elements = [...selection.elements.where((e) => !LinkElements.isLink(e))];
    if (selection.strokes.isEmpty && elements.isEmpty) return;
    final content = StickerContent.normalized(selection.strokes, elements);
    final details = await showSaveStickerDialog(
      context,
      content: content,
      categories: library.userCategories,
      images: session.services.images,
    );
    if (details == null || !context.mounted) return;
    library.save(name: details.name, category: details.category, content: content);
    showMessage(
      context,
      'Saved “${details.name}” to stickers',
      action: open.value ? null : SnackBarAction(label: 'Show', onPressed: () => open.value = true),
    );
  }

  /// The selection menu's "Save as sticker…".
  SelectionExtraAction saveAction(BuildContext context) => SelectionExtraAction(
    'Save as sticker…',
    Icons.interests_outlined,
    (_) => saveSelection(context),
  );

  void dispose() {
    _library?.dispose();
    open.dispose();
  }
}
