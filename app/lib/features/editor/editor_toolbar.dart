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
  static const double _dividerWidth = 13;
  static const double _padding = 12;

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
    final toolButtons = [
      for (final d in descriptors)
        ToolButton(descriptor: d, selected: d == active, onSelect: () => tools.tool = d.tool),
    ];
    final strip = active.strip == null
        ? null
        : AnimatedSwitcher(
            duration: const Duration(milliseconds: 150),
            child: KeyedSubtree(key: ValueKey(active.tool), child: active.strip!(context)),
          );
    final trailing = [
      if (active.options != null) SettingsButton(descriptor: active),
      PalmRejectionButton(enabled: tools.stylusOnly ?? false, onChanged: onStylusOnlyChanged),
    ];
    final oneRow =
        descriptors.length * _toolSize +
        (strip == null ? 0 : _dividerWidth + (active.stripWidth?.call() ?? 0)) +
        _dividerWidth +
        trailing.length * 40 +
        _padding;
    if (oneRow <= constraints.maxWidth) {
      return FloatingPanel(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ...toolButtons,
              if (strip != null) ...[const ToolbarDivider(), strip],
              const ToolbarDivider(),
              ...trailing,
            ],
          ),
        ),
      );
    }
    return FloatingPanel(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [...toolButtons, const ToolbarDivider(), ...trailing],
          ),
          if (strip != null) SingleChildScrollView(scrollDirection: Axis.horizontal, child: strip),
        ],
      ),
    );
  }
}
