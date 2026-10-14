import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../ui/app_theme.dart';
import '../../../ui/labelled_action.dart';
import '../../../ui/segment_label.dart';
import 'scan_page_strip.dart';
import 'scan_session.dart';

/// The scan screen's foot: the pages (flattened previews, the current one
/// ringed, then +), the current page's commands (Preview, Rotate, Whole
/// photo, Retake, Remove) and the look of all pages (Colour / Greyscale / B&W).
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
                  ScanPageStrip(session: session, busy: busy, onAdd: onAdd),
                  const SizedBox(height: Gaps.sm),
                  if (oneRow)
                    Row(children: [commands, const Spacer(), look])
                  else ...[
                    Center(child: ShrinkToFit(child: commands)),
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
        // The page as it will be stored, or its corners to adjust.
        Semantics(
          toggled: session.showsResult,
          child: LabelledAction(
            icon: Symbols.visibility_sharp,
            label: 'Preview',
            filled: session.showsResult,
            onPressed: session.toggleResult,
          ),
        ),
        LabelledAction(
          icon: Symbols.rotate_right_sharp,
          label: 'Rotate',
          onPressed: session.rotate,
        ),
        Semantics(
          toggled: whole,
          child: LabelledAction(
            icon: Symbols.crop_free_sharp,
            label: 'Whole photo',
            filled: whole,
            // Nothing to go back to when no page was found.
            onPressed: whole && (found == null || found == page.photo.bounds)
                ? null
                : session.toggleWholePhoto,
          ),
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
