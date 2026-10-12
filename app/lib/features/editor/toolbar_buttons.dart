import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../ui/app_theme.dart';
import 'editor_tools.dart';

/// A tool toggle. Inking tools show their current colour as a small bar
/// under the icon (recolouring the icon itself would be illegible for dark
/// inks in dark mode). Tapping the already active tool, long-pressing or
/// right-clicking it opens its settings. With [showLabel] the tool's name
/// sits under the glyph (wide screens, "Show tool names").
class ToolButton extends StatelessWidget {
  const ToolButton({
    super.key,
    required this.descriptor,
    required this.selected,
    required this.onSelect,
    this.size = 44,
    this.showLabel = false,
  });

  final ToolDescriptor descriptor;
  final bool selected;
  final VoidCallback onSelect;

  /// Width and height of the button (smaller on the compact toolbar).
  final double size;
  final bool showLabel;

  /// Height of a labelled button.
  static const double labelledHeight = 56;

  /// Width of a labelled button.
  static const double labelledWidth = 68;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    void openOptions() => descriptor.openOptions(context);
    final fg = selected ? scheme.onSecondaryContainer : scheme.onSurfaceVariant;
    final glyph = showLabel
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ToolGlyph(descriptor: descriptor),
              const SizedBox(height: 2),
              Text(
                descriptor.shortLabel,
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: theme.textTheme.labelSmall?.copyWith(color: fg, fontSize: 11, height: 1),
              ),
            ],
          )
        : ToolGlyph(descriptor: descriptor);
    return GestureDetector(
      onLongPress: openOptions,
      onSecondaryTap: openOptions,
      child: IconButton(
        tooltip: descriptor.tooltip,
        isSelected: selected,
        constraints: BoxConstraints.tightFor(
          width: showLabel ? labelledWidth : size,
          height: showLabel ? labelledHeight : size,
        ),
        padding: EdgeInsets.zero,
        onPressed: () => selected ? openOptions() : onSelect(),
        style: IconButton.styleFrom(
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          backgroundColor: selected ? scheme.secondaryContainer : null,
          foregroundColor: fg,
          shape: showLabel
              ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.sm))
              : null,
        ),
        icon: glyph,
      ),
    );
  }
}

/// A tool's icon with its ink colour as a small bar underneath.
class ToolGlyph extends StatelessWidget {
  const ToolGlyph({super.key, required this.descriptor});

  final ToolDescriptor descriptor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = descriptor.inkColor?.call();
    return SizedBox.square(
      dimension: 26,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          IconTheme.merge(data: const IconThemeData(size: 20), child: descriptor.icon),
          if (color != null)
            Positioned(
              bottom: 0,
              child: Container(
                width: 16,
                height: 4,
                decoration: BoxDecoration(
                  color: Color(color),
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(color: scheme.outline.withValues(alpha: 0.8), width: 0.5),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Opens the active tool's settings popover.
class SettingsButton extends StatelessWidget {
  const SettingsButton({super.key, required this.descriptor});

  final ToolDescriptor descriptor;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: '${descriptor.label} settings',
      style: IconButton.styleFrom(tapTargetSize: MaterialTapTargetSize.shrinkWrap),
      constraints: const BoxConstraints.tightFor(width: 40, height: 40),
      padding: EdgeInsets.zero,
      onPressed: () => descriptor.openOptions(context),
      icon: const Icon(Symbols.tune_rounded, size: 20),
    );
  }
}

/// Palm rejection: only the stylus draws; fingers pan and zoom.
class PalmRejectionButton extends StatelessWidget {
  const PalmRejectionButton({super.key, required this.enabled, required this.onChanged});

  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: enabled
          ? 'Stylus only: fingers pan & zoom (tap to let fingers draw)'
          : 'Fingers draw (tap for stylus only)',
      isSelected: enabled,
      style: IconButton.styleFrom(tapTargetSize: MaterialTapTargetSize.shrinkWrap),
      constraints: const BoxConstraints.tightFor(width: 40, height: 40),
      padding: EdgeInsets.zero,
      onPressed: () => onChanged(!enabled),
      icon: const Icon(Symbols.touch_app_rounded, size: 20),
      selectedIcon: const Icon(Symbols.do_not_touch_rounded, size: 20, fill: 1),
    );
  }
}

/// A thin vertical separator between toolbar groups.
class ToolbarDivider extends StatelessWidget {
  const ToolbarDivider({super.key});

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 24,
    margin: const EdgeInsets.symmetric(horizontal: 6),
    color: Theme.of(context).colorScheme.outlineVariant,
  );
}
