import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../ui/app_theme.dart';
import 'scan_session.dart';

/// The pages as their flattened previews in a row that scrolls, the
/// current one ringed; + at the end adds more. Pages are dragged into
/// another order (at once with a mouse, after a long press on touch).
class ScanPageStrip extends StatelessWidget {
  const ScanPageStrip({super.key, required this.session, required this.busy, required this.onAdd});

  final ScanSession session;
  final bool busy;
  final void Function(BuildContext anchor) onAdd;

  /// The height of the thumbnails.
  static const double thumbHeight = 72;

  @override
  Widget build(BuildContext context) {
    final pages = session.pages;
    return SizedBox(
      height: thumbHeight + 2 * (Hairline.rule + Gaps.xxs),
      child: ReorderableListView.builder(
        scrollDirection: Axis.horizontal,
        buildDefaultDragHandles: false,
        itemCount: pages.length,
        onReorderItem: session.move,
        // The thumbnail is paper already: no Material lift.
        proxyDecorator: (child, _, _) => Material(type: MaterialType.transparency, child: child),
        footer: _AddTile(enabled: !busy, onAdd: onAdd),
        itemBuilder: (context, i) {
          final current = i == session.index;
          final thumb = Padding(
            padding: const EdgeInsets.only(right: Gaps.sm),
            child: _Thumb(
              page: pages[i],
              number: i + 1,
              current: current,
              hint: !current
                  ? null
                  : session.showsResult
                  ? 'Show the corners'
                  : 'Show the cleaned-up page',
              onTap: () => current ? session.toggleResult() : session.select(i),
            ),
          );
          return Targets.touchFirst
              ? ReorderableDelayedDragStartListener(
                  key: ObjectKey(pages[i]),
                  index: i,
                  child: thumb,
                )
              : ReorderableDragStartListener(key: ObjectKey(pages[i]), index: i, child: thumb);
        },
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({
    required this.page,
    required this.number,
    required this.current,
    required this.hint,
    required this.onTap,
  });

  final ScanPageDraft page;
  final int number;
  final bool current;

  /// What tapping it does (the current page's: switch views), if not
  /// just selecting it.
  final String? hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = page.preview;
    // Until the preview is in, a page of the outline's turned shape.
    final aspect = preview == null ? page.aspect : preview.width / preview.height;
    return Semantics(
      button: true,
      selected: current,
      label: 'Page $number',
      hint: hint,
      child: GestureDetector(
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: _tooltip(
            AnimatedContainer(
              duration: Motion.fast,
              // The ring's width counts as padding too (a Container adds
              // its border's), so the paper keeps thumbHeight inside it.
              padding: const EdgeInsets.all(Gaps.xxs),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Radii.xs),
                border: Border.all(
                  color: current ? theme.colorScheme.primary : Colors.transparent,
                  width: Hairline.rule,
                ),
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Palette.paper,
                  boxShadow: Shadows.low(theme.brightness),
                ),
                child: SizedBox(
                  height: ScanPageStrip.thumbHeight,
                  width: ScanPageStrip.thumbHeight * aspect.clamp(0.4, 2.5),
                  child: preview == null ? null : RawImage(image: preview, fit: BoxFit.fill),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// [child] with [hint] on hover (not on a long press: that drags).
  Widget _tooltip(Widget child) => hint == null
      ? child
      : Tooltip(
          message: hint,
          triggerMode: TooltipTriggerMode.manual,
          excludeFromSemantics: true,
          child: child,
        );
}

/// + at the end of the pages: a page-sized outline, like the overview's
/// Add page and the library's New tile (a Pencil edge, no plate, an Ink +),
/// on the thumbnails' line.
class _AddTile extends StatelessWidget {
  const _AddTile({required this.enabled, required this.onAdd});

  final bool enabled;
  final void Function(BuildContext anchor) onAdd;

  /// An A4 page's width at the thumbnails' height.
  static const double _width = ScanPageStrip.thumbHeight * 210 / 297;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Radii.sm),
      side: BorderSide(color: enabled ? scheme.outline : scheme.outlineVariant),
    );
    return Padding(
      // Where a thumbnail's paper sits inside its ring.
      padding: const EdgeInsets.all(Hairline.rule + Gaps.xxs),
      child: Builder(
        builder: (context) => Tooltip(
          message: 'Add page',
          child: Semantics(
            button: true,
            enabled: enabled,
            child: Material(
              type: MaterialType.transparency,
              shape: shape,
              child: InkWell(
                customBorder: shape,
                onTap: enabled ? () => onAdd(context) : null,
                child: SizedBox(
                  width: _width,
                  height: ScanPageStrip.thumbHeight,
                  child: Icon(
                    Symbols.add_sharp,
                    size: Glyphs.bar,
                    color: enabled ? scheme.onSurface : scheme.onSurface.withValues(alpha: 0.38),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
