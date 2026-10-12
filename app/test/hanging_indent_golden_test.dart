import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/features/editor/tools/text/list_marker_view.dart';
import 'package:len/features/editor/tools/text/rich_text_controller.dart';
import 'package:len/features/editor/tools/text/rich_text_field.dart';
import 'package:len/ink/elements/text_layout.dart';

import 'hanging_indent_test.dart' show wrappedList, wrappedListWidth;

/// The box as the canvas paints it.
class _Painted extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final layout = TextLayout.layout(wrappedList, wrappedListWidth);
    layout.paint(canvas, Offset.zero);
    layout.dispose();
  }

  @override
  bool shouldRepaint(_Painted old) => false;
}

Future<Uint8List> _pixels(WidgetTester tester, Key key) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
  return (await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return bytes!.buffer.asUint8List();
  }))!;
}

void main() {
  testWidgets('text: wrapped list items hang the same painted and in the editing field', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(600, 400));
    final height = TextLayout.heightOf(wrappedList, wrappedListWidth);
    final controller = RichTextController(wrappedList)..wrapWidth = wrappedListWidth;
    controller.markerBuilder = (m) => ListMarkerView(marker: m);
    const painted = ValueKey('painted'), field = ValueKey('field');
    Widget panel(Key key, Widget child) => RepaintBoundary(
      key: key,
      child: ColoredBox(
        color: Colors.white,
        child: SizedBox(width: wrappedListWidth, child: child),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: const Color(0xFFE5E7EB),
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                panel(
                  painted,
                  SizedBox(
                    height: height,
                    child: CustomPaint(painter: _Painted()),
                  ),
                ),
                const SizedBox(width: 40),
                panel(
                  field,
                  OverflowBox(
                    alignment: Alignment.topLeft,
                    fit: OverflowBoxFit.deferToChild,
                    maxWidth: wrappedListWidth + RichTextField.caretMargin(2),
                    child: RichTextField(
                      controller: controller,
                      focusNode: FocusNode(),
                      cursorWidth: 2,
                      cursorColor: Colors.blue,
                      onDone: () {},
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(find.byType(Scaffold), matchesGoldenFile('goldens/text_hanging_indent.png'));
    // The field lays out and draws the text exactly as the box paints it.
    expect(tester.getSize(find.byKey(field)).height, closeTo(height, 0.5));
    final a = await _pixels(tester, painted), b = await _pixels(tester, field);
    expect(a.length, b.length);
    var differing = 0;
    for (var i = 0; i < a.length; i++) {
      if ((a[i] - b[i]).abs() > 24) differing++;
    }
    expect(differing / a.length, lessThan(0.002));
    controller.dispose();
  });
}
