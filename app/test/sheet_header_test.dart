import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/ui/app_theme.dart';
import 'package:len/ui/sheet_parts.dart';

/// The ✕ of a sheet header sits on the title's line, with or without a
/// subtitle, and the title doesn't move when a subtitle is added.
void main() {
  Future<void> pump(WidgetTester tester, SheetHeader header) => tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: 360, child: header),
        ),
      ),
    ),
  );

  Rect closeGlyph(WidgetTester tester) =>
      tester.getRect(find.descendant(of: find.byTooltip('Close'), matching: find.byType(Icon)));

  for (final subtitle in [null, 'Biology lecture']) {
    testWidgets('the ✕ centres on the title line (subtitle: $subtitle)', (tester) async {
      await pump(tester, SheetHeader(title: 'Export', subtitle: subtitle, onClose: () {}));
      final title = tester.getRect(find.text('Export'));
      expect(closeGlyph(tester).center.dy, moreOrLessEquals(title.center.dy, epsilon: 0.5));
    });
  }

  testWidgets('a subtitle neither moves the title nor the ✕', (tester) async {
    await pump(tester, SheetHeader(title: 'Export', onClose: () {}));
    final title = tester.getRect(find.text('Export'));
    final close = closeGlyph(tester);
    await pump(tester, SheetHeader(title: 'Export', subtitle: 'Biology', onClose: () {}));
    expect(tester.getRect(find.text('Export')), title);
    expect(closeGlyph(tester), close);
  });

  testWidgets('a long title wraps under a ✕ that stays on its first line', (tester) async {
    const long = 'Export the whole notebook with every page and recording';
    await pump(tester, SheetHeader(title: long, subtitle: 'Biology', onClose: () {}));
    final title = tester.getRect(find.text(long));
    expect(title.height, greaterThan(30), reason: 'two lines');
    final close = closeGlyph(tester);
    expect(close.center.dy, lessThan(title.top + title.height / 2));
  });
}
