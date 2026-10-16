import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/features/editor/document/document_scroller.dart';
import 'package:len/ink/navigation/viewport_animator.dart';
import 'package:len/ink/viewport.dart';
import 'package:len/ui/app_theme.dart';

/// Reduced motion (DESIGN §5: fades only, UX_AUDIT R23-4). Flutter runs
/// `AnimationController`s at 5 % of their duration then (routes, sheets,
/// implicit animations); what Len drives itself — page travel, zooms,
/// scrolling to a control — jumps.
void main() {
  void reduce(WidgetTester tester) {
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
      disableAnimations: true,
    );
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  }

  testWidgets('Motion.moving is zero when reduced; fades keep theirs', (tester) async {
    late BuildContext context;
    Future<void> pump() => tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );
    await pump();
    expect(Motion.moving(context, Motion.slow), Motion.slow);
    reduce(tester);
    await pump();
    expect(Motion.moving(context, Motion.slow), Duration.zero);
  });

  testWidgets('zooms and page travel jump to their view', (tester) async {
    reduce(tester);
    final viewport = ViewportController()..setSize(const Size(800, 600));
    final animator = ViewportAnimator(viewport);
    addTearDown(animator.dispose);
    animator.animateTo(scale: 2, offset: const Offset(-100, -50));
    expect(animator.isAnimating, isFalse);
    expect(viewport.scale, 2);
    expect(viewport.offset, const Offset(-100, -50));

    var done = false;
    final scroller = DocumentScroller(
      viewport,
      apply: (s, o) => viewport.setView(scale: s, offset: o),
    );
    scroller.animateTo(1, const Offset(0, -3000), onDone: () => done = true);
    expect(done, isTrue);
    expect(viewport.offset, const Offset(0, -3000));
  });
}
