import 'package:flutter/material.dart';

import '../../../domain/stickers/sticker.dart';
import '../../../ui/app_theme.dart';
import '../../stickers/sticker_panel.dart';
import '../chrome/chrome_metrics.dart';
import 'editor_stickers.dart';

/// The sticker panel floating beside the page (a sheet at the bottom on
/// phones), and the drop target that places a sticker dragged out of it.
/// Lies over the whole editor; takes no pointers where it shows nothing.
class StickerLayer extends StatelessWidget {
  const StickerLayer({super.key, required this.stickers, required this.insets});

  final EditorStickers stickers;

  /// Screen edges covered by the editor's chrome.
  final EdgeInsets insets;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: stickers.open,
    builder: (context, open, _) {
      if (!open) return const SizedBox.shrink();
      return LayoutBuilder(
        builder: (context, constraints) {
          final phone = constraints.maxWidth < ChromeMetrics.compactWidth;
          final panel = StickerPanel(
            library: stickers.library,
            images: stickers.session.services.images,
            onInsert: stickers.insert,
            onClose: () => stickers.open.value = false,
          );
          return Stack(
            children: [
              Positioned.fill(
                child: DragTarget<Sticker>(
                  onAcceptWithDetails: (d) {
                    final box = context.findRenderObject()! as RenderBox;
                    stickers.insert(d.data, screen: box.globalToLocal(d.offset));
                  },
                  builder: (context, candidates, _) => const SizedBox.expand(),
                ),
              ),
              if (phone)
                Positioned(
                  left: Gaps.sm,
                  right: Gaps.sm,
                  bottom: insets.bottom + Gaps.md,
                  height: constraints.maxHeight * 0.42,
                  child: panel,
                )
              else
                Positioned(
                  right: Gaps.md,
                  top: insets.top + Gaps.sm,
                  bottom: insets.bottom + Gaps.md,
                  width: 304,
                  child: panel,
                ),
            ],
          );
        },
      );
    },
  );
}
