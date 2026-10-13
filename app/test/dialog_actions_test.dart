import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/ui/app_dialogs.dart';
import 'package:len/ui/app_theme.dart';

Future<void> _show(WidgetTester tester, double width, List<Widget> actions) async {
  tester.view
    ..physicalSize = Size(width, 800)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => AppDialog(title: 'Open “Notes”', actions: actions),
            ),
            child: const Text('Show'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Show'));
  await tester.pumpAndSettle();
}

List<Widget> _three() => [
  TextButton(onPressed: () {}, child: const Text('Cancel')),
  TextButton(onPressed: () {}, child: const Text('New notebook')),
  FilledButton(onPressed: () {}, child: const Text('Add to this notebook')),
];

void main() {
  testWidgets('actions that fit sit in one end-aligned row', (tester) async {
    await _show(tester, 1000, _three());
    final cancel = tester.getRect(find.widgetWithText(TextButton, 'Cancel'));
    final primary = tester.getRect(find.widgetWithText(FilledButton, 'Add to this notebook'));
    expect(cancel.center.dy, moreOrLessEquals(primary.center.dy));
    expect(cancel.right, lessThan(primary.left));
  });

  testWidgets('stacked actions are full width, primary on top', (tester) async {
    await _show(tester, 320, _three());
    expect(tester.takeException(), isNull);
    final cancel = tester.getRect(find.widgetWithText(TextButton, 'Cancel'));
    final other = tester.getRect(find.widgetWithText(TextButton, 'New notebook'));
    final primary = tester.getRect(find.widgetWithText(FilledButton, 'Add to this notebook'));
    expect(primary.top, lessThan(other.top));
    expect(other.top, lessThan(cancel.top));
    for (final r in [cancel, other]) {
      expect(r.width, moreOrLessEquals(primary.width));
      expect(r.left, moreOrLessEquals(primary.left));
      expect(r.height, greaterThanOrEqualTo(Targets.touch));
    }
    // The alternative under the primary is outlined; Cancel stays quiet,
    // as everywhere (one outline); in a row nothing is.
    final actions = find.byType(DialogActions);
    expect(
      actions,
      paints..rrect(
        rrect: RRect.fromRectAndRadius(
          other.shift(-tester.getTopLeft(actions)).deflate(0.5),
          const Radius.circular(Radii.sm),
        ),
      ),
    );
    expect(
      actions,
      isNot(
        paints
          ..rrect()
          ..rrect(),
      ),
    );
  });

  testWidgets('a row of actions has no outlines', (tester) async {
    await _show(tester, 1000, _three());
    expect(find.byType(DialogActions), isNot(paints..rrect()));
  });

  testWidgets('at 1.3× text, content and actions share the same edge', (tester) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: MediaQuery(
          data: const MediaQueryData(size: Size(390, 844), textScaler: TextScaler.linear(1.3)),
          child: Builder(
            builder: (context) => AppDialog(
              title: 'Rename',
              content: const TextField(),
              actions: [
                TextButton(onPressed: () {}, child: const Text('Cancel')),
                FilledButton(onPressed: () {}, child: const Text('Rename')),
              ],
            ),
          ),
        ),
      ),
    );
    final field = tester.getRect(find.byType(TextField));
    final title = tester.getRect(find.text('Rename').first);
    final primary = tester.getRect(find.byType(FilledButton));
    expect(field.left, moreOrLessEquals(title.left));
    expect(field.right, moreOrLessEquals(primary.right));
  });
}
