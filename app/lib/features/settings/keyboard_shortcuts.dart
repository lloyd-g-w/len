import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ui/app_theme.dart';
import '../../ui/dialog_or_sheet.dart';
import '../../ui/section_label.dart';
import '../../ui/sheet_parts.dart';

/// One line of the shortcut reference: what it does and the keys that do
/// it (alternatives shown with "or"). [shown] replaces the keys' text where
/// one entry stands for several bindings ("1 – 6").
class ShortcutHelp {
  const ShortcutHelp(this.label, this.keys, {this.shown});

  final String label;

  /// The bindings, written with `control: true` for Ctrl / ⌘.
  final List<SingleActivator> keys;
  final String? shown;
}

/// A titled group of [ShortcutHelp]s.
class ShortcutGroup {
  const ShortcutGroup(this.title, this.items);

  final String title;
  final List<ShortcutHelp> items;
}

SingleActivator _ctrl(LogicalKeyboardKey key, {bool shift = false}) =>
    SingleActivator(key, control: true, shift: shift);

/// Every keyboard shortcut, grouped as a user looks for them. Kept next to
/// the bindings by `keyboard_shortcuts_test.dart`, which checks each one
/// here is bound.
final List<ShortcutGroup> shortcutGroups = [
  ShortcutGroup('General', [
    ShortcutHelp('Undo', [_ctrl(LogicalKeyboardKey.keyZ)]),
    ShortcutHelp('Redo', [
      _ctrl(LogicalKeyboardKey.keyZ, shift: true),
      _ctrl(LogicalKeyboardKey.keyY),
    ]),
    ShortcutHelp('Search in notebook', [_ctrl(LogicalKeyboardKey.keyF)]),
    const ShortcutHelp('Next / previous match', [
      SingleActivator(LogicalKeyboardKey.f3),
      SingleActivator(LogicalKeyboardKey.f3, shift: true),
    ], shown: 'F3 / Shift+F3'),
    ShortcutHelp('Go to page', [_ctrl(LogicalKeyboardKey.keyG)]),
    ShortcutHelp('Export', [_ctrl(LogicalKeyboardKey.keyE)]),
    ShortcutHelp('Focus mode', [
      const SingleActivator(LogicalKeyboardKey.f11),
      _ctrl(LogicalKeyboardKey.period),
    ]),
    const ShortcutHelp('Present (focus mode with the laser)', [
      SingleActivator(LogicalKeyboardKey.f5),
    ]),
    const ShortcutHelp('Turn pages in focus mode', [
      SingleActivator(LogicalKeyboardKey.space),
      SingleActivator(LogicalKeyboardKey.space, shift: true),
    ], shown: 'Space / Shift+Space'),
    const ShortcutHelp('Next / previous notebook', [
      SingleActivator(LogicalKeyboardKey.tab, control: true),
      SingleActivator(LogicalKeyboardKey.tab, control: true, shift: true),
    ], shown: 'Ctrl+Tab / Ctrl+Shift+Tab'),
    ShortcutHelp('Close notebook tab', [_ctrl(LogicalKeyboardKey.keyW)]),
    ShortcutHelp('Keyboard shortcuts', [_ctrl(LogicalKeyboardKey.slash)]),
  ]),
  const ShortcutGroup('Tools', [
    ShortcutHelp('Pen', [SingleActivator(LogicalKeyboardKey.keyP)]),
    ShortcutHelp('Highlighter', [SingleActivator(LogicalKeyboardKey.keyH)]),
    ShortcutHelp('Eraser', [SingleActivator(LogicalKeyboardKey.keyE)]),
    ShortcutHelp('Lasso', [SingleActivator(LogicalKeyboardKey.keyL)]),
    ShortcutHelp('Shapes', [SingleActivator(LogicalKeyboardKey.keyS)]),
    ShortcutHelp('Text', [SingleActivator(LogicalKeyboardKey.keyT)]),
    ShortcutHelp('Laser pointer', [SingleActivator(LogicalKeyboardKey.keyK)]),
    ShortcutHelp('Quick colour', [
      SingleActivator(LogicalKeyboardKey.digit1),
      SingleActivator(LogicalKeyboardKey.digit6),
    ], shown: '1 – 6'),
    ShortcutHelp('Thinner / thicker', [
      SingleActivator(LogicalKeyboardKey.bracketLeft),
      SingleActivator(LogicalKeyboardKey.bracketRight),
    ], shown: '[ / ]'),
  ]),
  ShortcutGroup('Selection', [
    ShortcutHelp('Select all on the page (or in view)', [_ctrl(LogicalKeyboardKey.keyA)]),
    const ShortcutHelp('Nudge 1 pt / 10 pt', [
      SingleActivator(LogicalKeyboardKey.arrowLeft),
      SingleActivator(LogicalKeyboardKey.arrowUp),
      SingleActivator(LogicalKeyboardKey.arrowRight, shift: true),
      SingleActivator(LogicalKeyboardKey.arrowDown, shift: true),
    ], shown: 'Arrows / Shift+arrows'),
    ShortcutHelp('Copy', [_ctrl(LogicalKeyboardKey.keyC)]),
    ShortcutHelp('Cut', [_ctrl(LogicalKeyboardKey.keyX)]),
    ShortcutHelp('Paste', [_ctrl(LogicalKeyboardKey.keyV)]),
    ShortcutHelp('Paste without formatting', [_ctrl(LogicalKeyboardKey.keyV, shift: true)]),
    ShortcutHelp('Duplicate', [_ctrl(LogicalKeyboardKey.keyD)]),
    const ShortcutHelp('Delete', [
      SingleActivator(LogicalKeyboardKey.delete),
      SingleActivator(LogicalKeyboardKey.backspace),
    ]),
    const ShortcutHelp('Deselect', [SingleActivator(LogicalKeyboardKey.escape)]),
  ]),
  ShortcutGroup('Pages', [
    const ShortcutHelp('Next page', [
      SingleActivator(LogicalKeyboardKey.arrowRight),
      SingleActivator(LogicalKeyboardKey.pageDown),
    ]),
    const ShortcutHelp('Previous page', [
      SingleActivator(LogicalKeyboardKey.arrowLeft),
      SingleActivator(LogicalKeyboardKey.pageUp),
    ]),
    const ShortcutHelp('First / last page', [
      SingleActivator(LogicalKeyboardKey.home),
      SingleActivator(LogicalKeyboardKey.end),
    ], shown: 'Home / End'),
    ShortcutHelp('Zoom in / out', [
      const SingleActivator(LogicalKeyboardKey.equal),
      const SingleActivator(LogicalKeyboardKey.minus),
      _ctrl(LogicalKeyboardKey.equal),
      _ctrl(LogicalKeyboardKey.minus),
    ], shown: '+ / −'),
    ShortcutHelp('Automatic zoom', [
      const SingleActivator(LogicalKeyboardKey.digit0),
      _ctrl(LogicalKeyboardKey.digit0),
    ]),
    const ShortcutHelp('Whole page', [SingleActivator(LogicalKeyboardKey.digit1, shift: true)]),
    const ShortcutHelp('Page width', [SingleActivator(LogicalKeyboardKey.digit2, shift: true)]),
  ]),
  ShortcutGroup('Canvas', [
    ShortcutHelp('Zoom in / out', const [
      SingleActivator(LogicalKeyboardKey.equal),
      SingleActivator(LogicalKeyboardKey.minus),
    ], shown: '+ / −'),
    const ShortcutHelp('100 %', [SingleActivator(LogicalKeyboardKey.digit0)]),
    const ShortcutHelp('Fit the content', [
      SingleActivator(LogicalKeyboardKey.digit1, shift: true),
    ]),
    const ShortcutHelp('Back to the start', [SingleActivator(LogicalKeyboardKey.home)]),
  ]),
  ShortcutGroup('Text boxes', [
    ShortcutHelp('Bold / italic / underline', [
      _ctrl(LogicalKeyboardKey.keyB),
      _ctrl(LogicalKeyboardKey.keyI),
      _ctrl(LogicalKeyboardKey.keyU),
    ], shown: '${modifierLabel()}+B / I / U'),
    ShortcutHelp('Strikethrough', [_ctrl(LogicalKeyboardKey.keyX, shift: true)]),
    ShortcutHelp('Heading 1 / 2 / normal', const [
      SingleActivator(LogicalKeyboardKey.digit1, control: true, alt: true),
      SingleActivator(LogicalKeyboardKey.digit2, control: true, alt: true),
      SingleActivator(LogicalKeyboardKey.digit0, control: true, alt: true),
    ], shown: '${modifierLabel()}+Alt+1 / 2 / 0'),
    ShortcutHelp('Numbered / bulleted / checklist', [
      _ctrl(LogicalKeyboardKey.digit7, shift: true),
      _ctrl(LogicalKeyboardKey.digit8, shift: true),
      _ctrl(LogicalKeyboardKey.digit9, shift: true),
    ], shown: '${modifierLabel()}+Shift+7 / 8 / 9'),
    const ShortcutHelp('Indent / outdent a list item', [
      SingleActivator(LogicalKeyboardKey.tab),
      SingleActivator(LogicalKeyboardKey.tab, shift: true),
    ], shown: 'Tab / Shift+Tab'),
    const ShortcutHelp('Done', [SingleActivator(LogicalKeyboardKey.escape)]),
  ]),
  ShortcutGroup('Library', [
    ShortcutHelp('New notebook', [_ctrl(LogicalKeyboardKey.keyN)]),
    ShortcutHelp('New folder', [_ctrl(LogicalKeyboardKey.keyN, shift: true)]),
    ShortcutHelp('Search', [_ctrl(LogicalKeyboardKey.keyF)]),
    ShortcutHelp('Select all', [_ctrl(LogicalKeyboardKey.keyA)]),
    const ShortcutHelp('Rename', [SingleActivator(LogicalKeyboardKey.f2)]),
    const ShortcutHelp('Move to trash', [SingleActivator(LogicalKeyboardKey.delete)]),
  ]),
];

/// Ctrl, or ⌘ on Apple platforms (where the bindings take either).
String modifierLabel() => switch (defaultTargetPlatform) {
  TargetPlatform.macOS || TargetPlatform.iOS => '⌘',
  _ => 'Ctrl',
};

/// "Ctrl+Shift+Z", "⌘+G", "→", "Page Down".
String describeShortcut(SingleActivator a) {
  final key = switch (a.trigger) {
    LogicalKeyboardKey.arrowRight => '→',
    LogicalKeyboardKey.arrowLeft => '←',
    LogicalKeyboardKey.arrowUp => '↑',
    LogicalKeyboardKey.arrowDown => '↓',
    LogicalKeyboardKey.period => '.',
    LogicalKeyboardKey.slash => '/',
    LogicalKeyboardKey.delete => 'Del',
    LogicalKeyboardKey.escape => 'Esc',
    LogicalKeyboardKey.space => 'Space',
    final k => k.keyLabel.length == 1 ? k.keyLabel.toUpperCase() : k.keyLabel,
  };
  return [
    if (a.control || a.meta) modifierLabel(),
    if (a.alt) 'Alt',
    if (a.shift) 'Shift',
    key,
  ].join('+');
}

/// The keys of [help] as shown.
String shownKeys(ShortcutHelp help) =>
    help.shown?.replaceAll('Ctrl', modifierLabel()) ?? help.keys.map(describeShortcut).join(' or ');

/// The ⌘/Ctrl+/ binding that opens [showKeyboardShortcuts].
Map<ShortcutActivator, VoidCallback> keyboardShortcutsBinding(VoidCallback open) => {
  const SingleActivator(LogicalKeyboardKey.slash, control: true): open,
  const SingleActivator(LogicalKeyboardKey.slash, meta: true): open,
};

/// Shows every keyboard shortcut, grouped.
Future<void> showKeyboardShortcuts(BuildContext context) => showDialogOrSheet<void>(
  context: context,
  maxWidth: 560,
  maxHeight: 720,
  sheetHeightFactor: 0.85,
  builder: (context, wide) => _ShortcutsSheet(wide: wide),
);

class _ShortcutsSheet extends StatelessWidget {
  const _ShortcutsSheet({required this.wide});

  final bool wide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(Gaps.xl, wide ? Gaps.lg : 0, Gaps.md, Gaps.sm),
          child: SheetHeader(
            title: 'Keyboard shortcuts',
            onClose: () => Navigator.of(context).pop(),
          ),
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(Gaps.xl, 0, Gaps.xl, Gaps.xl),
            children: [
              for (final group in shortcutGroups) ...[
                Padding(
                  padding: const EdgeInsets.only(top: Gaps.lg, bottom: Gaps.xs),
                  child: SectionLabel(group.title),
                ),
                for (final item in group.items)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: Gaps.xs),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: Text(item.label, style: theme.textTheme.bodyMedium)),
                        const SizedBox(width: Gaps.md),
                        Flexible(
                          child: Text(
                            shownKeys(item),
                            textAlign: TextAlign.end,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
