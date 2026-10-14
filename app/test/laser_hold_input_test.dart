import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/features/editor/editor_toolbar.dart';
import 'package:len/features/editor/tools/laser_overlay.dart';
import 'package:len/ink/tool_settings.dart';
import 'package:len/ink/tools/laser.dart';

import 'document_editor_test.dart' show closeEditor, pumpEditor;

/// The laser's "When I stop" fade end to end: presenting (F5), written with
/// a mouse, a pen or a finger, the trail stays between strokes and goes
/// together once the writing stops.
void main() {
  for (final kind in [PointerDeviceKind.mouse, PointerDeviceKind.stylus, PointerDeviceKind.touch]) {
    testWidgets('presenting, a held laser trail by ${kind.name} stays while writing', (
      tester,
    ) async {
      final (s, _) = await pumpEditor(tester, size: const Size(1280, 900));
      s.preferences.stylusOnly = false; // A finger writes too.
      final tools = tester.widget<EditorToolbar>(find.byType(EditorToolbar)).tools;
      tools.laser = tools.laser.copyWith(fade: LaserFade.pause);
      await tester.sendKeyEvent(LogicalKeyboardKey.f5);
      await tester.pumpAndSettle();
      expect(tools.tool, EditorTool.laser);

      Future<void> write(Offset from) async {
        final g = await tester.startGesture(from, kind: kind);
        for (var i = 1; i <= 6; i++) {
          await g.moveTo(from + Offset(i * 12.0, i * 3.0));
          await tester.pump(const Duration(milliseconds: 16));
        }
        await g.up();
        await tester.pump(const Duration(milliseconds: 16));
      }

      LaserTrail trail() => tester
          .widgetList<LaserOverlay>(find.byType(LaserOverlay))
          .map((o) => o.trail)
          .firstWhere((t) => t.length > 0);

      await write(const Offset(500, 300));
      await tester.pump(const Duration(milliseconds: 1500));
      await write(const Offset(500, 360));
      await tester.pump(const Duration(milliseconds: 1500));
      final held = trail();
      expect(held.length, greaterThanOrEqualTo(12), reason: 'both strokes are kept');
      expect(held.alphaAt(0), 1, reason: 'the first stroke still shows in full');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(LaserTrail.holdFade);
      await tester.pump(const Duration(milliseconds: 16));
      expect(held.length, 0, reason: 'it all went together');
      await closeEditor(tester);
    });
  }
}
