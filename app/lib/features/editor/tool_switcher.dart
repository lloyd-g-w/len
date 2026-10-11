import 'package:flutter/material.dart';

import '../../ink/tool_settings.dart';
import '../../ui/adaptive_popover.dart';
import '../../ui/app_theme.dart';
import '../../ui/section_label.dart';
import 'editor_tools.dart';
import 'toolbar/favourite_pens.dart';
import 'toolbar/toolbar_config.dart';
import 'toolbar_buttons.dart';

/// The compact (phone) toolbar's tool button: shows the active tool with
/// its ink colour and a small chevron; tapping it opens the
/// [ToolSwitcherPanel] right above or below the toolbar.
class ToolSwitcherButton extends StatelessWidget {
  const ToolSwitcherButton({
    super.key,
    required this.descriptors,
    required this.active,
    required this.tools,
    required this.onStylusOnlyChanged,
    this.favourites = const [],
  });

  final List<ToolDescriptor> descriptors;
  final ToolDescriptor active;
  final ToolSettings tools;
  final ValueChanged<bool> onStylusOnlyChanged;

  /// Favourite pens, offered in the panel.
  final List<FavouritePen> favourites;

  /// Width of the button (tool glyph plus chevron).
  static const double width = 56;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: '${active.label} — tap to switch tools',
      child: Semantics(
        button: true,
        label: 'Tool: ${active.label}. Switch tools',
        child: Material(
          color: scheme.secondaryContainer,
          borderRadius: BorderRadius.circular(Radii.pill),
          child: InkWell(
            borderRadius: BorderRadius.circular(Radii.pill),
            onTap: () => _open(context),
            onLongPress: () => active.openOptions(context),
            child: SizedBox(
              width: width,
              height: 40,
              child: IconTheme.merge(
                data: IconThemeData(color: scheme.onSecondaryContainer),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ToolGlyph(descriptor: active),
                    const Icon(Icons.expand_more_rounded, size: 16),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _open(BuildContext context) => showAdaptivePopover<void>(
    context: context,
    width: 344,
    sheetOnPhones: false,
    builder: (popover) => ToolSwitcherPanel(
      descriptors: descriptors,
      tools: tools,
      favourites: favourites,
      onStylusOnlyChanged: onStylusOnlyChanged,
      anchor: context,
    ),
  );
}

/// Every tool as a labelled tile (one tap switches and closes), the
/// favourite pens, then the active tool's settings and palm rejection.
class ToolSwitcherPanel extends StatelessWidget {
  const ToolSwitcherPanel({
    super.key,
    required this.descriptors,
    required this.tools,
    required this.onStylusOnlyChanged,
    required this.anchor,
    this.favourites = const [],
  });

  final List<ToolDescriptor> descriptors;
  final ToolSettings tools;
  final ValueChanged<bool> onStylusOnlyChanged;
  final List<FavouritePen> favourites;

  /// Where settings popovers opened from here are anchored (the toolbar).
  final BuildContext anchor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListenableBuilder(
      listenable: tools,
      builder: (context, _) {
        final active = descriptors.firstWhere(
          (d) => d.tool == tools.tool,
          orElse: () => descriptors.first,
        );
        final stylusOnly = tools.stylusOnly ?? false;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: Gaps.xs,
              runSpacing: Gaps.xs,
              alignment: WrapAlignment.center,
              children: [
                for (final d in descriptors)
                  _ToolTile(
                    descriptor: d,
                    selected: d == active,
                    onTap: () {
                      tools.tool = d.tool;
                      Navigator.of(context).pop();
                    },
                  ),
              ],
            ),
            if (favourites.isNotEmpty) ...[
              const SizedBox(height: Gaps.sm),
              Divider(height: 1, color: scheme.outlineVariant),
              const SizedBox(height: Gaps.xs),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: Gaps.sm, vertical: Gaps.xs),
                child: SectionLabel('Favourites'),
              ),
              Center(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: FavouritePens(
                    tools: tools,
                    favourites: favourites,
                    // Picking a favourite closes the panel, like a tool.
                    onPicked: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
            ],
            const SizedBox(height: Gaps.sm),
            Divider(height: 1, color: scheme.outlineVariant),
            const SizedBox(height: Gaps.xs),
            if (active.options != null)
              ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: Gaps.sm),
                leading: const Icon(Icons.tune_rounded),
                title: Text('${active.label} settings'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  Navigator.of(context).pop();
                  active.openOptions(anchor);
                },
              ),
            SwitchListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: Gaps.sm),
              secondary: Icon(stylusOnly ? Icons.do_not_touch_outlined : Icons.touch_app_outlined),
              title: const Text('Draw with stylus only'),
              subtitle: const Text('Fingers pan and zoom'),
              value: stylusOnly,
              onChanged: onStylusOnlyChanged,
            ),
          ],
        );
      },
    );
  }
}

class _ToolTile extends StatelessWidget {
  const _ToolTile({required this.descriptor, required this.selected, required this.onTap});

  final ToolDescriptor descriptor;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fg = selected ? scheme.onSecondaryContainer : scheme.onSurfaceVariant;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? scheme.secondaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(Radii.control),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.control),
          onTap: onTap,
          child: SizedBox(
            width: 72,
            height: 64,
            child: IconTheme.merge(
              data: IconThemeData(color: fg),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ToolGlyph(descriptor: descriptor),
                  const SizedBox(height: Gaps.xs),
                  Text(
                    descriptor.shortLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(color: fg),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
