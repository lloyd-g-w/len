import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'app_theme.dart';
import 'hit_overhang.dart';

/// The header of a task sheet or dialog (REDESIGN §5): a left-aligned
/// Heading ([TextTheme.titleMedium]) title, an optional Caption [subtitle]
/// and, for task sheets, a ✕ that closes it ([onClose]), centred on the
/// title's first line.
class SheetHeader extends StatelessWidget {
  const SheetHeader({super.key, required this.title, this.subtitle, this.onClose, this.trailing});

  final String title;
  final String? subtitle;

  /// Shows a ✕ button calling this (usually `Navigator.pop`).
  final VoidCallback? onClose;

  /// Extra controls before the ✕.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final buttons = onClose != null || trailing != null;
    // The title's first line and the buttons share one band, centred on
    // each other whether or not a subtitle follows (the ✕ belongs to the
    // title, not to title plus subtitle).
    final hit = Targets.barHit(context);
    final heading = text.titleMedium;
    final line =
        MediaQuery.textScalerOf(context).scale(heading?.fontSize ?? 18) * (heading?.height ?? 1);
    final band = buttons ? (line > hit ? line : hit) : line;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(top: (band - line) / 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  header: true,
                  child: Text(title, style: heading, maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
                if (subtitle case final s?) ...[
                  const SizedBox(height: Gaps.xxs),
                  Text(s, style: text.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ],
            ),
          ),
        ),
        if (buttons)
          Padding(
            padding: EdgeInsets.only(top: (band - hit) / 2),
            child: SizedBox(
              height: hit,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [?trailing, if (onClose != null) _close(context, onClose!)],
              ),
            ),
          ),
      ],
    );
  }

  /// The ✕, its glyph on the content's right edge (the button's padding
  /// hangs into the sheet's margin), wherever the header sits.
  static Widget _close(BuildContext context, VoidCallback onClose) {
    final hit = Targets.barHit(context);
    return HitOverhang(
      overhang: EdgeInsetsDirectional.only(end: (hit - Glyphs.bar) / 2),
      child: SizedBox.square(
        dimension: hit,
        child: IconButton(
          tooltip: 'Close',
          icon: const Icon(Symbols.close_sharp),
          onPressed: onClose,
        ),
      ),
    );
  }
}

/// The footer of a task sheet or a Confirm (REDESIGN §5): Cancel as a text
/// button and one filled [primary], right-aligned; on phones ([stacked])
/// both are full width, primary on top, Cancel still quiet.
class SheetActions extends StatelessWidget {
  const SheetActions({
    super.key,
    required this.primary,
    this.onCancel,
    this.cancelLabel = 'Cancel',
    this.stacked = false,
  });

  /// The primary command, usually a [FilledButton].
  final Widget primary;

  /// Shows Cancel calling this.
  final VoidCallback? onCancel;
  final String cancelLabel;

  /// Full width and stacked (phones), rather than a right-aligned row.
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final cancel = onCancel == null
        ? null
        : TextButton(onPressed: onCancel, child: Text(cancelLabel));
    if (stacked) {
      // Full width; Cancel stays quiet, as in dialogs (`DialogActions`).
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: Targets.touch, child: primary),
          if (cancel != null) ...[
            const SizedBox(height: Gaps.xs),
            SizedBox(height: Targets.touch, child: cancel),
          ],
        ],
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (cancel != null) ...[cancel, const SizedBox(width: Gaps.sm)],
        primary,
      ],
    );
  }
}
