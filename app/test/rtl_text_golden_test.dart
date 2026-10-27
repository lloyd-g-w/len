import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/text/text_data.dart';
import 'package:len/features/editor/tools/text/list_marker_view.dart';
import 'package:len/features/editor/tools/text/rich_text_controller.dart';
import 'package:len/features/editor/tools/text/rich_text_field.dart';
import 'package:len/ink/elements/text_layout.dart';

import 'rtl_text_test.dart' show hebrew, mixed, width;

/// An Arabic note: a heading, a numbered list (one item wraps, one nested)
/// and a ticked checklist item with digits and a Latin word.
final TextData arabic = TextData.rich(
  text:
      'خطة الأسبوع\n'
      'مراجعة التقرير الشهري وإرسال الملاحظات إلى الفريق\n'
      'تحديث الجدول\n'
      'حجز قاعة الاجتماعات\n'
      'شراء 3 دفاتر من Muji',
  spans: const [StyledRange(12, 18, SpanStyle(bold: true, color: 0xFFC2255C))],
  paras: const [
    ParaStyle(heading: 1),
    ParaStyle(list: ListKind.number),
    ParaStyle(list: ListKind.number),
    ParaStyle(list: ListKind.number, indent: 1),
    ParaStyle(list: ListKind.check, checked: true),
  ],
  fontSize: 20,
);

/// The box as the canvas paints it.
class _Painted extends CustomPainter {
  _Painted(this.data);

  final TextData data;

  @override
  void paint(Canvas canvas, Size size) {
    final layout = TextLayout.layout(data, width);
    layout.paint(canvas, Offset.zero);
    layout.dispose();
  }

  @override
  bool shouldRepaint(_Painted old) => old.data != data;
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
  testWidgets('text: Hebrew, Arabic and mixed boxes look the same painted and in the field', (
    tester,
  ) async {
    final samples = [
      hebrew,
      arabic,
      mixed,
      mixed.copyWith(align: TextAlignment.center),
      hebrew.copyWith(align: TextAlignment.end),
    ];
    await tester.binding.setSurfaceSize(const Size(1240, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controllers = [
      for (final data in samples)
        RichTextController(data)
          ..wrapWidth = width
          ..markerBuilder = (m) => ListMarkerView(marker: m),
    ];
    Widget panel(Key key, double height, Widget child) => RepaintBoundary(
      key: key,
      child: ColoredBox(
        color: Colors.white,
        child: SizedBox(width: width, height: height, child: child),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: const Color(0xFFE5E7EB),
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: Wrap(
              spacing: 40,
              runSpacing: 20,
              children: [
                for (var i = 0; i < samples.length; i++)
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      panel(
                        ValueKey('painted-$i'),
                        TextLayout.heightOf(samples[i], width),
                        CustomPaint(painter: _Painted(samples[i])),
                      ),
                      const SizedBox(height: 8),
                      panel(
                        ValueKey('field-$i'),
                        TextLayout.heightOf(samples[i], width),
                        OverflowBox(
                          alignment: Alignment.topLeft,
                          fit: OverflowBoxFit.deferToChild,
                          maxWidth: width + RichTextField.caretMargin(2),
                          child: RichTextField(
                            controller: controllers[i],
                            focusNode: FocusNode(),
                            cursorWidth: 2,
                            cursorColor: Colors.blue,
                            onDone: () {},
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(find.byType(Scaffold), matchesGoldenFile('goldens/text_rtl_boxes.png'));
    for (var i = 0; i < samples.length; i++) {
      final field = find.descendant(
        of: find.byKey(ValueKey('field-$i')),
        matching: find.byType(TextField),
      );
      expect(
        tester.getSize(field).height,
        closeTo(TextLayout.heightOf(samples[i], width), 0.5),
        reason: 'sample $i',
      );
      final a = await _pixels(tester, ValueKey('painted-$i'));
      final b = await _pixels(tester, ValueKey('field-$i'));
      expect(a.length, b.length);
      var differing = 0;
      for (var k = 0; k < a.length; k++) {
        if ((a[k] - b[k]).abs() > 24) differing++;
      }
      expect(differing / a.length, lessThan(0.002), reason: 'sample $i');
    }
    for (final c in controllers) {
      c.dispose();
    }
  });
}
