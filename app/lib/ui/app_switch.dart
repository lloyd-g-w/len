import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_theme.dart';

/// The app's switch (DESIGN §6 "Switch"): a flat rectangular track, 44 × 24,
/// with a square thumb of constant size and no glyph. Off is a Rule track
/// with a Graphite thumb, on is ruling blue with a Sheet thumb. The thumb
/// slides in [Motion.fast]; with reduced motion it only changes colour.
///
/// Keyboard: focusable, toggled with Space or Enter (the app's focus ring
/// shows where it is). Hit area: 48 on touch, 44 with a pointer, unless
/// [padded] is false (a row around it is the target, as in [AppSwitchTile]
/// and menu rows).
class AppSwitch extends StatefulWidget {
  const AppSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.padded = true,
    this.semanticLabel,
  });

  final bool value;

  /// Null disables the switch.
  final ValueChanged<bool>? onChanged;

  /// Pads the hit area to the input's target size.
  final bool padded;

  /// What the switch turns on, where no visible label is merged with it.
  final String? semanticLabel;

  /// The track's width.
  static const double trackWidth = 44;

  /// The track's height.
  static const double trackHeight = 24;

  /// The thumb's side.
  static const double thumb = 16;

  @override
  State<AppSwitch> createState() => _AppSwitchState();
}

class _AppSwitchState extends State<AppSwitch> {
  bool _hovered = false;

  bool get _enabled => widget.onChanged != null;

  void _toggle() => widget.onChanged?.call(!widget.value);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final on = widget.value;
    final dark = scheme.brightness == Brightness.dark;
    // An "off" track that still reads on a dark Sheet (as the theme's).
    final off = dark ? const Color(0xFF4A4A4A) : scheme.outlineVariant;
    var track = !_enabled
        ? scheme.onSurface.withValues(alpha: 0.08)
        : on
        ? scheme.primary
        : off;
    if (_hovered && _enabled) track = Color.alphaBlend(Surfaces.pressed(scheme), track);
    final thumb = !_enabled
        ? scheme.onSurface.withValues(alpha: 0.3)
        : on
        ? Surfaces.raised(scheme.brightness)
        : scheme.onSurfaceVariant;
    final slide = Motion.reduced(context) ? Duration.zero : Motion.fast;
    const inset = (AppSwitch.trackHeight - AppSwitch.thumb) / 2;
    final visual = AnimatedContainer(
      duration: Motion.fast,
      curve: Motion.standard,
      width: AppSwitch.trackWidth,
      height: AppSwitch.trackHeight,
      padding: const EdgeInsets.all(inset),
      decoration: BoxDecoration(color: track, borderRadius: BorderRadius.circular(Radii.xs)),
      child: AnimatedAlign(
        duration: slide,
        curve: Motion.standard,
        alignment: on ? Alignment.centerRight : Alignment.centerLeft,
        child: AnimatedContainer(
          duration: Motion.fast,
          width: AppSwitch.thumb,
          height: AppSwitch.thumb,
          decoration: BoxDecoration(color: thumb, borderRadius: BorderRadius.circular(1)),
        ),
      ),
    );
    final hit = Targets.menuRowHeight(context);
    return Semantics(
      toggled: on,
      enabled: _enabled,
      label: widget.semanticLabel,
      onTap: _enabled ? _toggle : null,
      child: FocusableActionDetector(
        enabled: _enabled,
        mouseCursor: _enabled ? SystemMouseCursors.click : MouseCursor.defer,
        onShowHoverHighlight: (v) => setState(() => _hovered = v),
        actions: {ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => _toggle())},
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _enabled ? _toggle : null,
          excludeFromSemantics: true,
          child: widget.padded
              ? SizedBox(
                  width: math.max(hit, AppSwitch.trackWidth),
                  height: hit,
                  child: Center(child: visual),
                )
              : visual,
        ),
      ),
    );
  }
}

/// A row with a title, an optional subtitle and an [AppSwitch] at its end;
/// tapping anywhere on the row toggles it, and it reads as one control.
/// Replaces Material's `SwitchListTile`.
class AppSwitchTile extends StatelessWidget {
  const AppSwitchTile({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.padding = const EdgeInsets.symmetric(horizontal: Gaps.lg),
    this.titleStyle,
  });

  final String title;
  final String? subtitle;
  final bool value;

  /// Null disables the row.
  final ValueChanged<bool>? onChanged;

  /// Around the row's content (the switch keeps the end edge).
  final EdgeInsetsGeometry padding;

  /// The title's style; Body by default.
  final TextStyle? titleStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onChanged != null;
    final disabled = theme.colorScheme.onSurface.withValues(alpha: 0.38);
    return MergeSemantics(
      child: InkWell(
        onTap: enabled ? () => onChanged!(!value) : null,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: Targets.menuRowHeight(context)),
          child: Padding(
            padding: padding,
            child: Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: Gaps.sm),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: (titleStyle ?? theme.textTheme.bodyMedium)?.copyWith(
                            color: enabled ? null : disabled,
                          ),
                        ),
                        if (subtitle case final subtitle?) ...[
                          const SizedBox(height: Gaps.xxs),
                          Text(
                            subtitle,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: enabled ? null : disabled,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: Gaps.md),
                // The row is the target and the focus stop.
                ExcludeFocus(
                  child: AppSwitch(value: value, onChanged: onChanged, padded: false),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
