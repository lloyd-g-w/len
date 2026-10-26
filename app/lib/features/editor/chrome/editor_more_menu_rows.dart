part of 'editor_more_menu.dart';

/// The rows of [EditorMoreMenu]: commands, switches and choices, with
/// their shortcut hints.
extension _MoreMenuRows on _EditorMoreMenuState {
  /// A page menu row; holding it down (or right-clicking it) runs its
  /// [PageCommand.alternate] ("Add page after": with a template).
  Widget _command(PageCommand c) {
    final run = actions.onPageCommand;
    final bookmarked = actions.bookmarked;
    Widget row({Map<CustomSemanticsAction, VoidCallback>? semanticsActions}) => _item(
      c.iconFor(bookmarked: bookmarked),
      c.labelFor(bookmarked: bookmarked),
      run == null ? null : () => run(c),
      destructive: c.destructive,
      semanticsActions: semanticsActions,
    );
    final alternate = c.alternate;
    if (run == null || alternate == null) return row();
    return Builder(
      builder: (context) {
        void choose() {
          if (MenuController.maybeOf(context) case final menu?) {
            DismissMenuAction(controller: menu).invoke(const DismissIntent());
          }
          // Once the menu has handed focus back, so that what opens (a
          // dialog) keeps it.
          WidgetsBinding.instance
            ..addPostFrameCallback((_) => run(alternate))
            ..scheduleFrame();
        }

        // Pointer gestures only: the row stays one button for screen readers,
        // which offer the alternate as a custom action on it.
        return GestureDetector(
          excludeFromSemantics: true,
          onLongPress: choose,
          onSecondaryTap: choose,
          child: alternateHintTooltip(
            c.alternateHint,
            row(semanticsActions: {CustomSemanticsAction(label: c.alternateAction!): choose}),
          ),
        );
      },
    );
  }

  /// A menu row; [shortcut] hints only where a keyboard is likely;
  /// [semanticsActions] are merged into the row's one semantics node.
  Widget _item(
    IconData icon,
    String label,
    VoidCallback? onPressed, {
    MenuSerializableShortcut? shortcut,
    String? shortcutLabel,
    bool destructive = false,
    Map<CustomSemanticsAction, VoidCallback>? semanticsActions,
  }) => Builder(
    builder: (context) {
      final theme = Theme.of(context);
      final error = theme.colorScheme.error;
      final hints = !Targets.touchFirst;
      return MenuItemButton(
        style: destructive
            ? MenuItemButton.styleFrom(foregroundColor: error, iconColor: error)
            : null,
        leadingIcon: Icon(icon),
        shortcut: hints ? shortcut : null,
        trailingIcon: hints && shortcutLabel != null
            ? Text(
                shortcutLabel,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            : null,
        onPressed: onPressed,
        child: Semantics(customSemanticsActions: semanticsActions, child: Text(label)),
      );
    },
  );

  /// An on/off row: the row toggles its switch; [shortcut] hints only
  /// where a keyboard is likely.
  Widget _switch(
    IconData icon,
    String label,
    bool value,
    VoidCallback? onPressed, {
    MenuSerializableShortcut? shortcut,
  }) => MenuItemButton(
    leadingIcon: Icon(icon),
    trailingIcon: _MenuSwitch(value: value),
    shortcut: Targets.touchFirst ? null : shortcut,
    onPressed: onPressed,
    child: Text(label),
  );

  /// A choice in a group: checked in the accent, like a checked menu row.
  Widget _radio(bool selected, String label, VoidCallback onPressed, {SingleActivator? shortcut}) =>
      Builder(
        builder: (context) => MenuItemButton(
          leadingIcon: Icon(
            selected
                ? Symbols.radio_button_checked_rounded
                : Symbols.radio_button_unchecked_rounded,
            fill: selected ? 1 : 0,
            color: selected ? Theme.of(context).colorScheme.primary : null,
          ),
          shortcut: Targets.touchFirst ? null : shortcut,
          onPressed: onPressed,
          child: Text(label),
        ),
      );
}

/// A switch shown in a menu row; the row itself toggles it.
class _MenuSwitch extends StatelessWidget {
  const _MenuSwitch({required this.value});

  final bool value;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ExcludeFocus(
      child: AppSwitch(value: value, onChanged: (_) {}, padded: false),
    ),
  );
}
