import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/ui/color_picker/color_picker.dart';
import 'package:len/ui/color_picker/gradient_slider.dart';

/// Owns the colour like the pen settings do: opacity never below 10 %.
class _ClampingOwner extends StatefulWidget {
  const _ClampingOwner();

  @override
  State<_ClampingOwner> createState() => _ClampingOwnerState();
}

class _ClampingOwnerState extends State<_ClampingOwner> {
  int color = 0xFF000000;

  @override
  Widget build(BuildContext context) => ColorPicker(
    color: color,
    onChanged: (c) => setState(() {
      final alpha = ((c >>> 24) & 0xFF).clamp(26, 255);
      color = (alpha << 24) | (c & 0xFFFFFF);
    }),
  );
}

void main() {
  GradientSlider slider(WidgetTester tester, String label) => tester.widget<GradientSlider>(
    find.byWidgetPredicate((w) => w is GradientSlider && w.label == label),
  );

  testWidgets('the hue of black survives the owner clamping the opacity', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: _ClampingOwner())),
      ),
    );
    Finder sliderFinder(String label) =>
        find.byWidgetPredicate((w) => w is GradientSlider && w.label == label);

    await tester.tap(sliderFinder('Hue')); // Centre: hue 180°.
    await tester.pump();
    expect(slider(tester, 'Hue').value, closeTo(0.5, 0.02));

    // Drag the opacity to zero; the owner clamps it back up.
    final opacity = tester.getRect(sliderFinder('Opacity'));
    await tester.dragFrom(opacity.centerRight - const Offset(2, 0), Offset(-opacity.width, 0));
    await tester.pump();

    expect(slider(tester, 'Opacity').value, closeTo(26 / 255, 1e-6));
    expect(slider(tester, 'Hue').value, closeTo(0.5, 0.02), reason: 'hue kept');
  });
}
