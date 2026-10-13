import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'section_label.dart';

/// The heading of a group inside a popover or sheet (DESIGN §6.2:
/// "Colour … Custom", "Size … 0.66 mm"): a [SectionLabel], then, flush
/// with the content's end edge, a [value] readout in tabular figures or a
/// [trailing] control (an [EndTextButton]).
class GroupHeader extends StatelessWidget {
  const GroupHeader(this.label, {super.key, this.value, this.trailing, this.enabled = true});

  final String label;

  /// A readout of the group's value ("0.66 mm"), in tabular figures.
  final String? value;

  /// A quiet action at the end ([EndTextButton]).
  final Widget? trailing;

  /// False fades the heading with its disabled control.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final faded = enabled ? null : theme.colorScheme.onSurface.withValues(alpha: 0.38);
    return Row(
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SectionLabel.style(context)?.copyWith(color: faded),
            ),
          ),
        ),
        if (value case final value?)
          Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              color: faded,
              fontFeatures: AppTheme.tabularFigures,
            ),
          ),
        ?trailing,
      ],
    );
  }
}

/// A quiet text button at the end of a row (a popover's Reset, a group's
/// Custom): its label sits flush with the content's end edge, the padding
/// of its hover plate hanging past it, like a value readout's. It is
/// [height] tall whatever the input, so rows holding one keep one height
/// (a title's baseline doesn't move with or without it).
class EndTextButton extends StatelessWidget {
  const EndTextButton({super.key, required this.label, required this.onPressed, this.icon});

  final String label;
  final IconData? icon;

  /// Null disables the button.
  final VoidCallback? onPressed;

  /// The button's (and its row's) height: a button's 40 dp on touch, the
  /// compact 32 with a pointer.
  static double get height => Targets.touchFirst ? Targets.bar : _compact;

  static const double _compact = 32;

  /// The plate's padding at each side.
  static const double _pad = Gaps.sm;

  @override
  Widget build(BuildContext context) {
    final style = TextButton.styleFrom(
      minimumSize: Size(0, height),
      maximumSize: Size(double.infinity, height),
      padding: const EdgeInsets.symmetric(horizontal: _pad),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.standard,
    );
    final button = switch (icon) {
      final icon? => TextButton.icon(
        onPressed: onPressed,
        style: style,
        icon: Icon(icon, size: Glyphs.menu),
        label: Text(label),
      ),
      null => TextButton(onPressed: onPressed, style: style, child: Text(label)),
    };
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return Transform.translate(offset: Offset(rtl ? -_pad : _pad, 0), child: button);
  }
}

/// A row's trailing chevron ([Glyphs.bar]), nudged so its glyph, not the
/// glyph's empty margin, meets the content's end edge.
class EndChevron extends StatelessWidget {
  const EndChevron({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return Transform.translate(offset: Offset(rtl ? -Gaps.xs : Gaps.xs, 0), child: child);
  }
}
