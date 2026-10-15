import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/features/inklab/inklab_screen.dart';
import 'package:len/features/inklab/inklab_stats_bar.dart';
import 'package:len/features/settings/about_settings.dart';
import 'package:len/ink/lab/flicker_log.dart';

/// The figure before [suffix] in the stats bar (e.g. `strokes`).
int _stat(WidgetTester tester, String suffix) {
  final text = find.textContaining(RegExp('^\\d+ $suffix\$'));
  expect(text, findsOneWidget, reason: suffix);
  return int.parse((tester.widget<Text>(text).data!).split(' ').first);
}

void main() {
  testWidgets('7 taps on the version open the Ink Lab; drawing records, commits and replays', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: AboutSettings())),
      ),
    );
    final version = find.text('Len ${AboutSettings.version}');
    for (var i = 0; i < 6; i++) {
      await tester.tap(version);
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(InkLabScreen), findsNothing);
    await tester.tap(version);
    await tester.pump(); // Route pushed; the session opens asynchronously.
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(InkLabScreen), findsOneWidget);
    expect(find.byType(InkLabStatsBar), findsOneWidget);

    final surface = tester.getCenter(find.byType(InkLabStatsBar).first) - const Offset(0, 200);
    final pen = await tester.startGesture(surface, kind: PointerDeviceKind.stylus);
    for (var i = 0; i < 10; i++) {
      await pen.moveBy(const Offset(8, 3));
      await tester.pump(const Duration(milliseconds: 8));
    }
    await pen.up();
    await tester.pump(InkLabStatsBar.period);

    expect(_stat(tester, 'strokes'), 1);
    expect(_stat(tester, 'contacts'), 1);
    expect(_stat(tester, 'entries'), greaterThan(12)); // Pointer events + frames.

    // Replay clears the surface and plays the recording back frame by frame.
    await tester.tap(find.byTooltip('Replay'));
    await tester.pump();
    expect(find.byTooltip('Stop replay'), findsOneWidget);
    for (var i = 0; i < 40 && find.byTooltip('Stop replay').evaluate().isNotEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump(InkLabStatsBar.period);
    expect(find.text('Replayed 1 strokes'), findsOneWidget);
    await tester.pump(InkLabStatsBar.period);
    expect(_stat(tester, 'strokes'), 1);

    await tester.tap(find.byTooltip('Clear'));
    await tester.pump(InkLabStatsBar.period);
    expect(_stat(tester, 'strokes'), 0);
    expect(_stat(tester, 'contacts'), 0);

    // Leave the lab so its timers and recorder are released.
    await tester.pageBack();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(InkLabScreen), findsNothing);
  });

  testWidgets('the flicker log: record, read, clear', (tester) async {
    final log = FlickerLog.instance;
    final was = log.enabled;
    addTearDown(() => log.enabled = was);
    log
      ..enabled = false
      ..clear();
    await tester.pumpWidget(const MaterialApp(home: InkLabScreen()));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byTooltip('Flicker log'));
    await tester.pumpAndSettle();
    expect(find.text('Nothing logged'), findsOneWidget);
    await tester.tap(find.text('Record'));
    await tester.pump();
    expect(log.enabled, isTrue);
    log.retract(3, 1000);
    await tester.pump();
    expect(find.textContaining('predicted tip taken back 3.00 px'), findsOneWidget);
    await tester.tap(find.text('Clear'));
    await tester.pump();
    expect(log.entries, isEmpty);
    expect(find.text('Nothing logged'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 500));
  });
}
