import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/features/editor/chrome/peeking.dart';
import 'package:len/features/editor/page_navigator.dart';
import 'package:len/ui/app_theme.dart';

void main() {
  testWidgets('the page indicator jumps on tap and opens the overview on long press', (
    tester,
  ) async {
    var jumps = 0;
    var overviews = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Center(
            child: PageNavigator(
              index: 2,
              count: 12,
              bookmarked: true,
              onGoTo: () => jumps++,
              onOverview: () => overviews++,
            ),
          ),
        ),
      ),
    );

    final indicator = find.byKey(const ValueKey('page-indicator'));
    expect(indicator, findsOneWidget);
    expect(find.text('3 / 12'), findsOneWidget);
    expect(tester.getSize(indicator).height, greaterThanOrEqualTo(48));
    await tester.tap(indicator);
    expect((jumps, overviews), (1, 0));
    await tester.longPress(indicator);
    expect((jumps, overviews), (1, 1));
  });

  testWidgets('peeking indicator gives the page back after 1.5 seconds', (tester) async {
    final activity = ValueNotifier<int>(0);
    addTearDown(activity.dispose);
    var jumps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              const ColoredBox(color: Colors.white),
              Peeking(
                activity: activity,
                child: PageNavigator(index: 0, count: 5, onGoTo: () => jumps++, onOverview: () {}),
              ),
            ],
          ),
        ),
      ),
    );
    final indicator = find.byKey(const ValueKey('page-indicator'));
    await tester.pump(const Duration(milliseconds: 1700));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.widget<IgnorePointer>(find.byType(IgnorePointer).last).ignoring, isTrue);
    activity.value++;
    await tester.pump();
    await tester.tap(indicator);
    expect(jumps, 1);
  });
}
