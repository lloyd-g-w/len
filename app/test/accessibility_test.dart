import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/features/editor/editor_screen.dart';
import 'package:len/features/library/library_screen.dart';
import 'package:len/features/settings/settings_screen.dart';
import 'package:len/ui/app_theme.dart';
import 'package:len/ui/group_header.dart';
import 'package:len/ui/hit_overhang.dart';
import 'package:material_symbols_icons/symbols.dart';

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

/// A phone held sideways: the library's phone layout with folders beside
/// the title, the editor's one-row chrome (`Breakpoints.shortHeight`).
const sideways = Size(844, 390);

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
        builder: (context, child) => HitOverhangScope(child: child!),
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
  // Quick slots are 44 dp on touch by design (CONVENTIONS "Targets"); the
  // phone's options sheet repeats them.
  'label: "Colour ': 'quick colour slots, 44 dp',
  'label: "Size ': 'quick size slots, 44 dp',
};

/// Text the contrast check can't measure: set in its own font, which the
/// test can't swap for boxes, so it measures anti-aliased glyph edges.
const Map<String, String> knownContrast = {
  'label: "Sans", tooltip: "Font"': 'the font menu shows the font in itself',
  'label: "Planners"': 'at the template gallery\'s bottom edge, inside its scroll fade',
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
/// every violation found. [contrastHere] adds [knownContrast] entries for
/// this scenario only.
Future<void> expectAccessible(
  WidgetTester tester, {
  required Size size,
  required Scenario scenario,
  Map<String, String> contrastHere = const {},
}) async {
  final failures = <String>[];
  Future<void> check(List<AccessibilityGuideline> guidelines) async {
    final handle = tester.ensureSemantics();
    for (final g in guidelines) {
      final result = await g.evaluate(tester);
      if (result.passed) continue;
      final reason = switch (g) {
        MinimumTapTargetGuideline() => _withoutKnown(result.reason!, knownSmallTargets),
        _ when g == textContrastGuideline => _withoutKnown(result.reason!, {
          ...knownContrast,
          ...contrastHere,
        }),
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
  'lasso tip': () => [find.byTooltip('Lasso (L)')],
  'shape options': () => toolOptions('Shapes (S)'),
  'text options': () => toolOptions('Text (T)'),
  'laser options': () => toolOptions('Laser pointer (K)'),
  'export sheet': () => [find.byTooltip('More options'), find.text('Export…')],
  'page menu': () => [find.byTooltip('More options'), find.text('Page')],
  'change template': () => [
    find.byTooltip('More options'),
    find.text('Page'),
    find.text('Change template…'),
  ],
};

/// The phone's states: the toolbar sits at the bottom, a switcher holds
/// the tools (the active one opens its options), and the quick slots
/// open their editors as sheets.
final Map<String, List<Finder> Function()> phoneEditorStates = {
  'editor': () => [],
  'pen options': () => [find.byTooltip('Pen: tap to switch tools'), find.text('Pen')],
  'colour slot': () => [find.byKey(const ValueKey('color-0'))],
  'size slot': () => [find.byKey(const ValueKey('width-1'))],
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

  // A phone held sideways: short-window chrome, Android's targets.
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    final label = 'phone sideways ${mode.name}';
    testWidgets('library $label', (tester) async {
      await expectAccessible(
        tester,
        size: sideways,
        scenario: (t) => pumpScreen(t, (_) => const LibraryScreen(), size: sideways, mode: mode),
      );
    });

    for (final MapEntry(key: state, value: taps) in phoneEditorStates.entries) {
      testWidgets('$state $label', (tester) async {
        await expectAccessible(
          tester,
          size: sideways,
          // The options sheet scrolls: its next group fades out at the
          // window's bottom edge, by design.
          contrastHere: const {
            'label: "Size"': 'the pen sheet\'s Size group, inside its scroll fade',
            'label: "0.65 mm"': 'the pen sheet\'s size readout, inside its scroll fade',
          },
          scenario: (t) async {
            await pumpScreen(
              t,
              (s) => EditorScreen(notebook: physics(s)),
              size: sideways,
              mode: mode,
            );
            await tapAll(t, taps());
          },
        );
      });
    }
  }

  // Controls whose hit area hangs past their box (HitOverhang): the
  // guideline skips them where they touch a scrollable's edge, so check
  // them here: the full touch target, and taps anywhere on it count.
  group('overhanging hit areas on touch', () {
    testWidgets('Reset and Custom in tool popovers', (tester) async {
      await pumpScreen(tester, (s) => EditorScreen(notebook: physics(s)), size: tablet);
      await tapAll(tester, toolOptions('Eraser (E)'));
      expectTouchTarget(tester, find.widgetWithText(EndTextButton, 'Reset'));
      await tester.tapAt(const Offset(1, 1)); // Closes the popover.
      await settle(tester);
      await tapAll(tester, toolOptions('Pen (P)'));
      expectTouchTarget(tester, find.widgetWithText(EndTextButton, 'Reset'));
      final custom = find.widgetWithText(EndTextButton, 'Custom');
      final plate = expectTouchTarget(tester, custom);
      // The header keeps the button's visual height.
      expect(tester.getSize(custom).height, plate.height);
      final hit = tester.getRect(_buttonIn(custom));
      // A tap on the overhang, above the plate and past the content edge.
      await tester.tapAt(hit.topRight + const Offset(-1, 1));
      await settle(tester);
      expect(find.byIcon(Symbols.expand_less_sharp), findsOneWidget);
    });

    testWidgets('a sheet’s ✕ past the content edge', (tester) async {
      await pumpScreen(tester, (_) => const LibraryScreen(), size: phone);
      await tapAll(tester, [find.bySemanticsLabel('New notebook')]);
      final close = find.byTooltip('Close');
      final rect = tester.getRect(close);
      expect(rect.width, greaterThanOrEqualTo(Targets.touch));
      expect(rect.height, greaterThanOrEqualTo(Targets.touch));
      await tester.tapAt(rect.centerRight - const Offset(1, 0));
      await settle(tester);
      expect(close, findsNothing);
    });
  });

  // Large text (the largest Android font size is 2×): nothing overflows,
  // and the guidelines still hold.
  for (final (name, size) in [('phone', phone), ('phone sideways', sideways), ('tablet', tablet)]) {
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

/// Checks that [button] (an [EndTextButton]) is [Targets.touch] square to a
/// finger while its plate keeps the button's visual height; returns the
/// plate.
Rect expectTouchTarget(WidgetTester tester, Finder button) {
  final hit = tester.getRect(_buttonIn(button));
  expect(hit.width, greaterThanOrEqualTo(Targets.touch));
  expect(hit.height, greaterThanOrEqualTo(Targets.touch));
  final semantics = tester.getSemantics(_buttonIn(button));
  expect(semantics.rect.height, greaterThanOrEqualTo(Targets.touch));
  final plate = tester.getRect(find.descendant(of: button, matching: find.byType(Material)).first);
  expect(plate.height, EndTextButton.height);
  return plate;
}

/// The button (padded to its hit area) inside [finder].
Finder _buttonIn(Finder finder) =>
    find.descendant(of: finder, matching: find.byWidgetPredicate((w) => w is TextButton));
