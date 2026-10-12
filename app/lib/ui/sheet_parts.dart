import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'app_theme.dart';

/// The header of a task sheet or dialog (REDESIGN §5): a left-aligned
/// Heading ([TextTheme.titleMedium]) title, an optional Caption [subtitle]
/// and, for task sheets, a ✕ that closes it ([onClose]).
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
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                header: true,
                child: Text(
                  title,
                  style: text.titleMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (subtitle case final s?) ...[
                const SizedBox(height: Gaps.xxs),
                Text(s, style: text.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ],
          ),
        ),
        ?trailing,
        if (onClose != null)
          IconButton(
            tooltip: 'Close',
            icon: const Icon(Symbols.close_rounded),
            onPressed: onClose,
          ),
      ],
    );
  }
}

/// The footer of a task sheet or a Confirm (REDESIGN §5): Cancel as a text
/// button and one filled [primary], right-aligned; on phones ([stacked])
/// both are full width, primary on top.
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
