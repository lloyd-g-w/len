import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/features/editor/editor_screen.dart';
import 'package:len/features/library/library_screen.dart';
import 'package:len/features/settings/settings_screen.dart';
import 'package:len/ui/app_theme.dart';

import 'screenshots/screenshot_harness.dart';

// Guards Flutter's accessibility guidelines on the main screens: tap
// targets, a label on everything tappable, and text contrast (WCAG AA).
//
// Each scenario runs twice. With the app's fonts it checks targets and
// labels. Then with the test font (solid boxes) it checks contrast, so the
// check measures the text colour against its background rather than the
// anti-aliased edges of 11–12 px glyphs, which read lighter than they are.
//
// Tap targets: Android's 48 dp on phones; elsewhere the app's own floor of
// 44 dp (iOS), what it gives quick slots and menu rows on tablets
// (CONVENTIONS "Targets").

const phone = Size(390, 844);
const tablet = Size(1280, 800);

/// A screen state to check: pumps it (see [pumpScreen]) and opens what it
/// needs to.
typedef Scenario = Future<void> Function(WidgetTester tester);

bool _boxFont = false;

ThemeData _theme(ThemeData t) => !_boxFont
    ? t
    : t.copyWith(
        // Boxes about as wide as Inter's letters, so layouts stay close.
        textTheme: t.textTheme.apply(fontFamily: 'FlutterTest', fontSizeFactor: 0.6),
      );

/// Pumps [home] with fresh seeded services at [size].
Future<AppServices> pumpScreen(
  WidgetTester tester,
  Widget Function(AppServices s) home, {
  required Size size,
  ThemeMode mode = ThemeMode.light,
  double textScale = 1,
}) async {
  setWindow(tester, size);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final services = seededServices();
  addTearDown(services.dispose);
  await tester.pumpWidget(
    AppScope(
      key: UniqueKey(),
      services: services,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _theme(AppTheme.light()),
        darkTheme: _theme(AppTheme.dark()),
        themeMode: mode,
        home: home(services),
      ),
    ),
  );
  await settle(tester);
  return services;
}

/// Small tap targets known and owned elsewhere: a pattern in the failing
/// semantics node's description, and why it is still allowed. Remove an
/// entry once its fix lands.
const Map<String, String> knownSmallTargets = {
  // fix/library-r4 makes the card ⋯ 48 dp on touch (UX_AUDIT P2-23).
  'tooltip: "More"': 'card ⋯, P2-23',
  // The library sidebar on tablets: 40-dp rows, New folder, the footer's
  // Settings and Sync, and the 40-dp search field (UX_AUDIT A11Y-1).
  'Size(223.0, 42.0)': 'sidebar rows, A11Y-1',
  'tooltip: "New folder"': 'sidebar New folder, A11Y-1',
  'label: "Settings"': 'sidebar footer, A11Y-1',
  'label: "Sync off"': 'sidebar footer, A11Y-1',
  'label: "Search"': 'search field, A11Y-1',
  // Quick slots are 44 dp on touch by design (CONVENTIONS "Targets"); the
  // phone's options sheet repeats them.
  'label: "Colour ': 'quick colour slots, 44 dp',
  'label: "Size ': 'quick size slots, 44 dp',
  // Settings on phones: segmented buttons shrink to fit (ShrinkToFit),
  // so their 48-dp height scales down (UX_AUDIT A11Y-2).
  'isInMutuallyExclusiveGroup': 'shrunk segmented buttons, A11Y-2',
};

/// Text the contrast check can't measure: set in its own font, which the
/// test can't swap for boxes, so it measures anti-aliased glyph edges.
const Map<String, String> knownContrast = {
  'label: "Sans", tooltip: "Font"': 'the font menu shows the font in itself',
  // At 2× text the library sidebar's footer (Settings beside the sync
  // caption) squeezes the Settings label away (UX_AUDIT A11Y-1).
  'label: "Settings"': 'sidebar footer at 2× text, A11Y-1',
};

/// [reason] without the nodes [known] allows; null if none is left.
String? _withoutKnown(String reason, Map<String, String> known) {
  final kept = <String>[];
  for (final entry in reason.split(RegExp(r'\n(?=SemanticsNode#)'))) {
    if (!known.keys.any(entry.contains)) kept.add(entry);
  }
  return kept.isEmpty ? null : kept.join('\n');
}

/// Runs [scenario] and checks the guidelines on what it shows; fails with
/// every violation found.
Future<void> expectAccessible(
  WidgetTester tester, {
  required Size size,
  required Scenario scenario,
}) async {
  final failures = <String>[];
  Future<void> check(List<AccessibilityGuideline> guidelines) async {
    final handle = tester.ensureSemantics();
    for (final g in guidelines) {
      final result = await g.evaluate(tester);
      if (result.passed) continue;
      final reason = switch (g) {
        MinimumTapTargetGuideline() => _withoutKnown(result.reason!, knownSmallTargets),
        _ when g == textContrastGuideline => _withoutKnown(result.reason!, knownContrast),
        _ => result.reason,
      };
      if (reason != null) failures.add('${g.description}\n$reason');
    }
    handle.dispose();
  }

  _boxFont = false;
  await scenario(tester);
  await check([
    size.shortestSide < 600 ? androidTapTargetGuideline : iOSTapTargetGuideline,
    labeledTapTargetGuideline,
  ]);
  _boxFont = true;
  try {
    await scenario(tester);
    await check([textContrastGuideline]);
  } finally {
    _boxFont = false;
  }
  if (failures.isNotEmpty) fail(failures.join('\n\n'));
}

Notebook physics(AppServices s) =>
    s.notebooks.list().firstWhere((n) => n.title.startsWith('Physics'));

/// Taps [finders] in turn, letting each settle.
Future<void> tapAll(WidgetTester tester, List<Finder> finders) async {
  for (final f in finders) {
    await tester.tap(f.last);
    await settle(tester);
  }
}

/// Opens a tool's options from the toolbar: selects it, then taps it again.
List<Finder> toolOptions(String tooltip) => [find.byTooltip(tooltip), find.byTooltip(tooltip)];

/// Editor states to check, by name: what to tap after it opens.
final Map<String, List<Finder> Function()> editorStates = {
  'editor': () => [],
  'pen options': () => [find.byTooltip('Pen (P)')],
  'highlighter options': () => toolOptions('Highlighter (H)'),
  'eraser options': () => toolOptions('Eraser (E)'),
  'lasso options': () => toolOptions('Lasso (L)'),
  'shape options': () => toolOptions('Shapes (S)'),
  'text options': () => toolOptions('Text (T)'),
  'laser options': () => toolOptions('Laser pointer (K)'),
  'export sheet': () => [find.byTooltip('More options'), find.text('Export…')],
  'change template': () => [
    find.byTooltip('More options'),
    find.text('Page'),
    find.text('Change template…'),
  ],
};

/// The phone's states: the toolbar sits at the bottom, a switcher holds
/// the tools, and options open from the quick slots as sheets.
final Map<String, List<Finder> Function()> phoneEditorStates = {
  'editor': () => [],
  'pen options': () => [find.byKey(const ValueKey('color-0'))],
  'export sheet': () => [find.byTooltip('More options'), find.text('Export…')],
};

void main() {
  for (final (name, size) in [('phone', phone), ('tablet', tablet)]) {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      final label = '$name ${mode.name}';

      testWidgets('library $label', (tester) async {
        await expectAccessible(
          tester,
          size: size,
          scenario: (t) => pumpScreen(t, (_) => const LibraryScreen(), size: size, mode: mode),
        );
      });

      testWidgets('settings $label', (tester) async {
        await expectAccessible(
          tester,
          size: size,
          scenario: (t) => pumpScreen(t, (_) => const SettingsScreen(), size: size, mode: mode),
        );
      });

      testWidgets('new notebook $label', (tester) async {
        await expectAccessible(
          tester,
          size: size,
          scenario: (t) async {
            await pumpScreen(t, (_) => const LibraryScreen(), size: size, mode: mode);
            await tapAll(t, [find.bySemanticsLabel('New notebook')]);
          },
        );
      });

      final states = size == phone ? phoneEditorStates : editorStates;
      for (final MapEntry(key: state, value: taps) in states.entries) {
        testWidgets('$state $label', (tester) async {
          await expectAccessible(
            tester,
            size: size,
            scenario: (t) async {
              await pumpScreen(
                t,
                (s) => EditorScreen(notebook: physics(s)),
                size: size,
                mode: mode,
              );
              await tapAll(t, taps());
            },
          );
        });
      }
    }
  }

  // Large text (the largest Android font size is 2×): nothing overflows,
  // and the guidelines still hold.
  for (final (name, size) in [('phone', phone), ('tablet', tablet)]) {
    for (final (screen, home) in <(String, Widget Function(AppServices))>[
      ('library', (_) => const LibraryScreen()),
      ('settings', (_) => const SettingsScreen()),
      ('editor', (s) => EditorScreen(notebook: physics(s))),
    ]) {
      testWidgets('$screen $name at 2× text', (tester) async {
        await expectAccessible(
          tester,
          size: size,
          scenario: (t) => pumpScreen(t, home, size: size, textScale: 2),
        );
      });
    }
  }
}
