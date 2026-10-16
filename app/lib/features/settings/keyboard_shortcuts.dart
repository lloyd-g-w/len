import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

export 'keyboard_shortcuts_sheet.dart';

/// One line of the shortcut reference: what it does and the keys that do
/// it (alternatives shown with "or"). [shown] replaces the keys' text where
/// one entry stands for several bindings ("1 – 5").
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
    ShortcutHelp('Print', [_ctrl(LogicalKeyboardKey.keyP)]),
    ShortcutHelp('Focus mode', [
      const SingleActivator(LogicalKeyboardKey.f11),
      _ctrl(LogicalKeyboardKey.period),
    ]),
    const ShortcutHelp('Zoom window', [SingleActivator(LogicalKeyboardKey.keyM)]),
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
    // ContextMenuKeys: whatever has focus (a card, a tab, the page).
    const ShortcutHelp('Context menu', [
      SingleActivator(LogicalKeyboardKey.contextMenu),
      SingleActivator(LogicalKeyboardKey.f10, shift: true),
    ], shown: 'Menu key or Shift+F10'),
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
      SingleActivator(LogicalKeyboardKey.digit5),
    ], shown: '1 – 5'),
    ShortcutHelp('Thinner / thicker', [
      SingleActivator(LogicalKeyboardKey.bracketLeft),
      SingleActivator(LogicalKeyboardKey.bracketRight),
    ], shown: '[ / ]'),
  ]),
  ShortcutGroup('Selection', [
    ShortcutHelp('Select all on page (or in view)', [_ctrl(LogicalKeyboardKey.keyA)]),
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
    ShortcutHelp('Scroll', [
      SingleActivator(LogicalKeyboardKey.arrowUp),
      SingleActivator(LogicalKeyboardKey.arrowDown),
    ], shown: '↑ / ↓'),
    ShortcutHelp('Zoom in / out', [
      SingleActivator(LogicalKeyboardKey.equal),
      SingleActivator(LogicalKeyboardKey.minus),
      _ctrl(LogicalKeyboardKey.equal),
      _ctrl(LogicalKeyboardKey.minus),
    ], shown: '+ / −'),
    ShortcutHelp('Automatic zoom', [
      SingleActivator(LogicalKeyboardKey.digit0),
      _ctrl(LogicalKeyboardKey.digit0),
    ]),
    ShortcutHelp('Fit page', [SingleActivator(LogicalKeyboardKey.digit1, shift: true)]),
    ShortcutHelp('Fit width', [SingleActivator(LogicalKeyboardKey.digit2, shift: true)]),
    // Bound on a focused page tile (PageTile).
    ShortcutHelp('Move page in the overview', const [
      SingleActivator(LogicalKeyboardKey.arrowLeft, control: true),
      SingleActivator(LogicalKeyboardKey.arrowRight, control: true),
      SingleActivator(LogicalKeyboardKey.arrowUp, control: true),
      SingleActivator(LogicalKeyboardKey.arrowDown, control: true),
    ], shown: 'Ctrl+← → ↑ ↓'),
  ]),
  ShortcutGroup('Canvas', [
    ShortcutHelp('Zoom in / out', const [
      SingleActivator(LogicalKeyboardKey.equal),
      SingleActivator(LogicalKeyboardKey.minus),
    ], shown: '+ / −'),
    const ShortcutHelp('100%', [SingleActivator(LogicalKeyboardKey.digit0)]),
    const ShortcutHelp('Fit content', [SingleActivator(LogicalKeyboardKey.digit1, shift: true)]),
    const ShortcutHelp('Move around', [
      SingleActivator(LogicalKeyboardKey.arrowLeft),
      SingleActivator(LogicalKeyboardKey.arrowUp),
      SingleActivator(LogicalKeyboardKey.arrowRight),
      SingleActivator(LogicalKeyboardKey.arrowDown),
    ], shown: '← ↑ → ↓'),
    const ShortcutHelp('Back to start', [SingleActivator(LogicalKeyboardKey.home)]),
    const ShortcutHelp('Minimap', [SingleActivator(LogicalKeyboardKey.keyM, shift: true)]),
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
    // Handled by the editor's key handler (R19-3).
    const ShortcutHelp('New text box (Text tool)', [], shown: 'Type'),
    const ShortcutHelp('Back to the tool before (Text tool)', [], shown: 'Esc'),
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
