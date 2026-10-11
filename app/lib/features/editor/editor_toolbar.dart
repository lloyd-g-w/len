import 'package:flutter/material.dart';

import '../../ink/tool_settings.dart';
import '../../ui/floating_panel.dart';
import 'editor_tools.dart';
import 'tool_switcher.dart';
import 'toolbar/favourite_pens.dart';
import 'toolbar/toolbar_config.dart';
import 'toolbar_buttons.dart';

/// The floating tool palette (GoodNotes style), in groups: the tools (in
/// the user's order, without hidden ones: [config]), favourite pens, the
/// active tool's quick controls (for inks: a colour row and, in a recessed
/// track, a width row), then its settings and palm rejection.
///
/// One row when it fits (optionally with tool names under the icons).
/// Otherwise — phones — a compact row: the active tool (tap it for a tool
/// switcher with settings and palm rejection) and its quick controls.
class EditorToolbar extends StatelessWidget {
  const EditorToolbar({
    super.key,
    required this.tools,
    required this.onStylusOnlyChanged,
    this.showLabels = false,
    this.config = const ToolbarConfig(),
  });

  final ToolSettings tools;

  /// Order and visibility of the tools, and the favourite pens.
  final ToolbarConfig config;
  final ValueChanged<bool> onStylusOnlyChanged;

  /// Tool names under the icons (when the full row fits).
  final bool showLabels;

  static const double _toolSize = 44;
  static const double _dividerWidth = 13;
  static const double _buttonWidth = 40;

  /// The [FloatingPanel]'s horizontal padding.
  static const double _padding = 12;

  static double _toolWidth(bool labels) => labels ? ToolButton.labelledWidth : _toolSize;

  /// Width of the one-row toolbar for [descriptor] as the active tool,
  /// including the panel's padding.
  static double _oneRowWidth(
    List<ToolDescriptor> descriptors,
    ToolDescriptor descriptor, {
    bool labels = false,
    int favourites = 0,
  }) {
    final hasStrip = descriptor.strip != null;
    return descriptors.length * _toolWidth(labels) +
        (favourites > 0 ? _dividerWidth + FavouritePens.widthFor(favourites) : 0) +
        (hasStrip ? _dividerWidth + (descriptor.stripWidth?.call() ?? 0) : 0) +
        _dividerWidth +
        (descriptor.options == null ? 1 : 2) * _buttonWidth +
        _padding;
  }

  /// The width the toolbar needs to stay on one row whichever tool is
  /// active (for the current quick colours and widths).
  static double oneRowWidth(
    ToolSettings tools, {
    bool labels = false,
    ToolbarConfig config = const ToolbarConfig(),
  }) {
    final all = editorTools(tools);
    var widest = 0.0;
    for (final d in all) {
      // The active tool is shown even when hidden.
      final descriptors = config.arrange(all, (d) => d.tool, keep: d.tool);
      final favourites = config.favourites.length;
      final w = _oneRowWidth(descriptors, d, labels: labels, favourites: favourites);
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
    final all = editorTools(tools);
    final descriptors = config.arrange(all, (d) => d.tool, keep: tools.tool);
    final active = descriptors.firstWhere(
      (d) => d.tool == tools.tool,
      orElse: () => descriptors.first,
    );
    final available = constraints.maxWidth - _padding;
    final favourites = config.favourites.length;
    double width(bool labels) =>
        _oneRowWidth(descriptors, active, labels: labels, favourites: favourites) - _padding;
    var labels = showLabels;
    if (labels && width(true) > available) {
      labels = false; // Names only when they fit.
    }
    if (width(labels) <= available) {
      return _oneRow(context, descriptors, active, labels: labels);
    }
    return _compact(context, descriptors, active, available);
  }

  Widget _switching(ToolDescriptor active, Widget child) => AnimatedSwitcher(
    duration: const Duration(milliseconds: 150),
    child: KeyedSubtree(key: ValueKey(active.tool), child: child),
  );

  Widget _oneRow(
    BuildContext context,
    List<ToolDescriptor> descriptors,
    ToolDescriptor active, {
    required bool labels,
  }) {
    final strip = active.strip;
    return FloatingPanel(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final d in descriptors)
              ToolButton(
                descriptor: d,
                selected: d == active,
                onSelect: () => tools.tool = d.tool,
                size: _toolSize,
                showLabel: labels,
              ),
            if (config.favourites.isNotEmpty) ...[
              const ToolbarDivider(),
              FavouritePens(tools: tools, favourites: config.favourites),
            ],
            if (strip != null) ...[const ToolbarDivider(), _switching(active, strip(context))],
            const ToolbarDivider(),
            if (active.options != null) SettingsButton(descriptor: active),
            PalmRejectionButton(enabled: tools.stylusOnly ?? false, onChanged: onStylusOnlyChanged),
          ],
        ),
      ),
    );
  }

  /// One short row: the tool switcher and the active tool's quick
  /// controls (without "+" when short of room; they scroll if still too
  /// wide). Tools without quick controls show their settings button.
  Widget _compact(
    BuildContext context,
    List<ToolDescriptor> descriptors,
    ToolDescriptor active,
    double available,
  ) {
    final room = available - ToolSwitcherButton.width - _dividerWidth;
    final full = active.stripWidth?.call() ?? 0;
    final builder = full <= room || active.compactStrip == null
        ? active.strip
        : active.compactStrip;
    return FloatingPanel(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ToolSwitcherButton(
            descriptors: descriptors,
            active: active,
            tools: tools,
            favourites: config.favourites,
            onStylusOnlyChanged: onStylusOnlyChanged,
          ),
          const ToolbarDivider(),
          if (builder != null)
            Flexible(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: _switching(active, builder(context)),
              ),
            )
          else if (active.options != null)
            SettingsButton(descriptor: active)
          else
            PalmRejectionButton(enabled: tools.stylusOnly ?? false, onChanged: onStylusOnlyChanged),
        ],
      ),
    );
  }
}
