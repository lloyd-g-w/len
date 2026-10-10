import 'package:flutter/material.dart';

import '../../ink/tool_settings.dart';
import '../../ui/floating_panel.dart';
import 'editor_tools.dart';
import 'toolbar_buttons.dart';

/// The floating tool palette (GoodNotes style): the tools, the active
/// tool's quick controls (for inks: independent colour and width slots),
/// its settings and palm rejection.
///
/// Laid out on one row when it fits, else on two (tools above, quick
/// controls below) — e.g. on phones.
class EditorToolbar extends StatelessWidget {
  const EditorToolbar({super.key, required this.tools, required this.onStylusOnlyChanged});

  final ToolSettings tools;
  final ValueChanged<bool> onStylusOnlyChanged;

  static const double _toolSize = 44;

  /// Tool size on the two-row (compact) toolbar.
  static const double _compactToolSize = 40;
  static const double _dividerWidth = 13;
  static const double _buttonWidth = 40;

  /// The [FloatingPanel]'s horizontal padding.
  static const double _padding = 12;

  /// Width of the one-row toolbar for [descriptor] as the active tool,
  /// including the panel's padding.
  static double _oneRowWidth(List<ToolDescriptor> descriptors, ToolDescriptor descriptor) {
    final hasStrip = descriptor.strip != null;
    return descriptors.length * _toolSize +
        (hasStrip ? _dividerWidth + (descriptor.stripWidth?.call() ?? 0) : 0) +
        _dividerWidth +
        (descriptor.options == null ? 1 : 2) * _buttonWidth +
        _padding;
  }

  /// The width the toolbar needs to stay on one row whichever tool is
  /// active (for the current quick colours and widths).
  static double oneRowWidth(ToolSettings tools) {
    final descriptors = editorTools(tools);
    var widest = 0.0;
    for (final d in descriptors) {
      final w = _oneRowWidth(descriptors, d);
      if (w > widest) widest = w;
    }
    return widest;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: tools,
      builder: (context, _) => LayoutBuilder(builder: _build),
    );
  }

  Widget _build(BuildContext context, BoxConstraints constraints) {
    final descriptors = editorTools(tools);
    final active = descriptors.firstWhere(
      (d) => d.tool == tools.tool,
      orElse: () => descriptors.first,
    );
    List<Widget> toolButtons(double size) => [
      for (final d in descriptors)
        ToolButton(
          descriptor: d,
          selected: d == active,
          onSelect: () => tools.tool = d.tool,
          size: size,
        ),
    ];
    final strip = active.strip == null
        ? null
        : AnimatedSwitcher(
            duration: const Duration(milliseconds: 150),
            child: KeyedSubtree(key: ValueKey(active.tool), child: active.strip!(context)),
          );
    final stripWidth = strip == null ? 0.0 : active.stripWidth?.call() ?? 0.0;
    final settings = active.options == null ? null : SettingsButton(descriptor: active);
    final palm = PalmRejectionButton(
      enabled: tools.stylusOnly ?? false,
      onChanged: onStylusOnlyChanged,
    );
    final available = constraints.maxWidth - _padding;
    final oneRow = _oneRowWidth(descriptors, active) - _padding;
    if (oneRow <= available) {
      return FloatingPanel(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ...toolButtons(_toolSize),
              if (strip != null) ...[const ToolbarDivider(), strip],
              const ToolbarDivider(),
              ?settings,
              palm,
            ],
          ),
        ),
      );
    }

    // Two rows: the tools and palm rejection above, the quick controls and
    // settings below. The settings button is left out when it doesn't fit
    // (tapping the active tool opens its settings, too); each row scrolls on
    // very narrow screens rather than overflowing.
    final toolRow = descriptors.length * _compactToolSize + _dividerWidth + _buttonWidth;
    final settingsAbove = settings != null && toolRow + _buttonWidth <= available;
    final settingsBelow =
        settings != null &&
        !settingsAbove &&
        (strip == null || stripWidth + _dividerWidth + _buttonWidth <= available);
    Widget row(List<Widget> children) => SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
    return FloatingPanel(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          row([
            ...toolButtons(_compactToolSize),
            const ToolbarDivider(),
            if (settingsAbove) settings,
            palm,
          ]),
          if (strip != null || settingsBelow)
            row([
              ?strip,
              if (settingsBelow) ...[if (strip != null) const ToolbarDivider(), settings],
            ]),
        ],
      ),
    );
  }
}
