import 'package:flutter_test/flutter_test.dart';
import 'package:len/features/editor/editor_canvas.dart';

/// Pumps frames while real asynchronous work runs (PDFium's worker, image
/// decoding, files, isolates), until [done] holds after [stable] frames in a
/// row. Waits on the condition, not for a fixed time, so a busy machine only
/// makes it slower; fails after [timeout] of real time.
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  int stable = 1,
  Duration timeout = const Duration(seconds: 60),
  String reason = 'a condition',
}) async {
  final watch = Stopwatch()..start();
  var held = 0;
  while (held < stable) {
    if (watch.elapsed > timeout) fail('timed out after $timeout waiting for $reason');
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
    held = done() ? held + 1 : 0;
  }
}

/// Pumps until the open editor's PDF backgrounds are rendered: nothing
/// queued or rendering over a few frames (a render can ask for a sharper
/// one, or for the next page).
Future<void> pumpUntilPdfRendered(WidgetTester tester) => pumpUntil(
  tester,
  () => find.byType(EditorCanvas).evaluate().every((e) {
    final backgrounds = (e.widget as EditorCanvas).session.backgrounds;
    return backgrounds == null || !backgrounds.isBusy;
  }),
  stable: 3,
  reason: 'PDF pages to render',
);
