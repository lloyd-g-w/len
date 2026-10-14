import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../ui/app_theme.dart';
import '../../../ui/labelled_action.dart';
import '../../../ui/segment_label.dart';
import 'scan_session.dart';

/// The scan screen's foot: the pages (flattened previews, the current one
/// ringed, then +), the current page's commands (Rotate, Whole photo,
/// Retake, Remove) and the look of all pages (Colour / Greyscale / B&W).
class ScanControls extends StatelessWidget {
  const ScanControls({
    super.key,
    required this.session,
    required this.busy,
    required this.retakeLabel,
    required this.onRetake,
    required this.onAdd,
  });

  final ScanSession session;

  /// Photos are being read: commands that add or replace one wait.
  final bool busy;
  final String retakeLabel;
  final VoidCallback onRetake;

  /// Adds pages; gets the + tile's context to anchor a menu on.
  final void Function(BuildContext anchor) onAdd;

  /// The height of the page strip's thumbnails.
  static const double thumbHeight = 72;

  /// Narrower than this, the look goes on its own row.
  static const double _oneRow = 720;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Surfaces.chrome(scheme),
        border: Border(top: Surfaces.chromeEdge(scheme)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Gaps.lg, Gaps.md, Gaps.lg, Gaps.sm),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final commands = _commands(context);
              final look = _look();
              final oneRow = constraints.maxWidth >= _oneRow;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _PageStrip(session: session, busy: busy, onAdd: onAdd),
                  const SizedBox(height: Gaps.sm),
                  if (oneRow)
                    Row(children: [commands, const Spacer(), look])
                  else ...[
                    Center(child: commands),
                    const SizedBox(height: Gaps.xs),
                    Center(child: ShrinkToFit(child: look)),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _commands(BuildContext context) {
    final page = session.current!;
    final whole = session.isWholePhoto;
    final found = page.photo.detected;
    // Named commands: a bare glyph is a guess on touch, where tooltips
    // need a long press.
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: Gaps.sm,
      children: [
        LabelledAction(
          icon: Symbols.rotate_right_sharp,
          label: 'Rotate',
          onPressed: session.rotate,
        ),
        LabelledAction(
          icon: Symbols.crop_free_sharp,
          label: 'Whole photo',
          filled: whole,
          // Nothing to go back to when no page was found.
          onPressed: whole && (found == null || found == page.photo.bounds)
              ? null
              : session.toggleWholePhoto,
        ),
        LabelledAction(
          icon: Symbols.replay_sharp,
          label: retakeLabel,
          onPressed: busy ? null : onRetake,
        ),
        LabelledAction(
          icon: Symbols.delete_sharp,
          label: 'Remove',
          onPressed: session.removeCurrent,
        ),
      ],
    );
  }

  Widget _look() => SegmentedButton<ScanFilter>(
    key: const ValueKey('scan-filter'),
    showSelectedIcon: false,
    style: const ButtonStyle(visualDensity: VisualDensity.compact),
    segments: const [
      ButtonSegment(value: ScanFilter.colour, label: SegmentLabel('Colour')),
      ButtonSegment(value: ScanFilter.greyscale, label: SegmentLabel('Greyscale')),
      ButtonSegment(value: ScanFilter.blackWhite, label: SegmentLabel('B&W')),
    ],
    selected: {session.filter},
    onSelectionChanged: (s) => session.filter = s.single,
  );
}

/// The pages as their flattened previews in a row that scrolls, the
/// current one ringed; + at the end adds more.
class _PageStrip extends StatelessWidget {
  const _PageStrip({required this.session, required this.busy, required this.onAdd});

  final ScanSession session;
  final bool busy;
  final void Function(BuildContext anchor) onAdd;

  @override
  Widget build(BuildContext context) {
    final pages = session.pages;
    return SizedBox(
      height: ScanControls.thumbHeight + 2 * (Hairline.rule + Gaps.xxs),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: pages.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: Gaps.sm),
        itemBuilder: (context, i) => i == pages.length
            ? _AddTile(enabled: !busy, onAdd: onAdd)
            : _Thumb(
                key: ObjectKey(pages[i]),
                page: pages[i],
                number: i + 1,
                current: i == session.index,
                onTap: () => session.select(i),
              ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({
    super.key,
    required this.page,
    required this.number,
    required this.current,
    required this.onTap,
  });

  final ScanPageDraft page;
  final int number;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = page.preview;
    // Until the preview is in, a page of the outline's turned shape.
    final aspect = preview == null
        ? (page.turns.isOdd ? 1 / _aspect(page) : _aspect(page))
        : preview.width / preview.height;
    return Semantics(
      button: true,
      selected: current,
      label: 'Page $number',
      child: GestureDetector(
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: AnimatedContainer(
            duration: Motion.fast,
            padding: const EdgeInsets.all(Hairline.rule + Gaps.xxs),
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
                height: ScanControls.thumbHeight,
                width: ScanControls.thumbHeight * aspect.clamp(0.4, 2.5),
                child: preview == null ? null : RawImage(image: preview, fit: BoxFit.fill),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Width over height of the outline (its top and left sides).
  static double _aspect(ScanPageDraft page) {
    final q = page.quad;
    final w = (q.topRight - q.topLeft).distance, h = (q.bottomLeft - q.topLeft).distance;
    return h <= 0 ? 1 : w / h;
  }
}

class _AddTile extends StatelessWidget {
  const _AddTile({required this.enabled, required this.onAdd});

  final bool enabled;
  final void Function(BuildContext anchor) onAdd;

  @override
  Widget build(BuildContext context) => Center(
    child: Builder(
      builder: (context) => IconButton(
        tooltip: 'Add page',
        icon: const Icon(Symbols.add_sharp),
        iconSize: Glyphs.bar,
        onPressed: enabled ? () => onAdd(context) : null,
      ),
    ),
  );
}

/// The scan screen before the first page: take a photo (with a camera) or
/// choose photos.
class ScanEmptyState extends StatelessWidget {
  const ScanEmptyState({super.key, required this.busy, required this.onPick, this.onCamera});

  /// A photo is being read: the choices wait.
  final bool busy;
  final VoidCallback onPick;

  /// Takes a photo; null without a camera.
  final VoidCallback? onCamera;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final camera = onCamera;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Gaps.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Symbols.document_scanner_sharp,
              size: Glyphs.empty,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: Gaps.md),
            Text(
              busy ? 'Finding the page…' : 'Photograph a page on a contrasting surface',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Gaps.xl),
            if (camera != null) ...[
              FilledButton.icon(
                onPressed: busy ? null : camera,
                icon: const Icon(Symbols.photo_camera_sharp),
                label: const Text('Take photo'),
              ),
              const SizedBox(height: Gaps.sm),
            ],
            if (camera == null)
              FilledButton.icon(
                onPressed: busy ? null : onPick,
                icon: const Icon(Symbols.image_sharp),
                label: const Text('Choose photos…'),
              )
            else
              OutlinedButton.icon(
                onPressed: busy ? null : onPick,
                icon: const Icon(Symbols.image_sharp),
                label: const Text('Choose photos…'),
              ),
          ],
        ),
      ),
    );
  }
}
