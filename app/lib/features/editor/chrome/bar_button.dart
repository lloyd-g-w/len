import 'package:flutter/material.dart';

/// An icon button of the editor's top bar: quiet by default, tinted when
/// [selected].
class BarButton extends StatelessWidget {
  const BarButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
    this.selectedIcon,
  });

  final IconData icon;
  final IconData? selectedIcon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      isSelected: selected,
      iconSize: 22,
      style: IconButton.styleFrom(
        foregroundColor: selected ? scheme.primary : scheme.onSurfaceVariant,
        minimumSize: const Size(40, 40),
        fixedSize: const Size(40, 40),
        padding: EdgeInsets.zero,
      ),
      icon: Icon(icon),
      selectedIcon: Icon(selectedIcon ?? icon),
    );
  }
}

/// A thin vertical separator between groups of [BarButton]s.
class BarDivider extends StatelessWidget {
  const BarDivider({super.key});

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 20,
    margin: const EdgeInsets.symmetric(horizontal: 6),
    color: Theme.of(context).colorScheme.outlineVariant,
  );
}
