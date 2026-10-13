import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/ui/app_switch.dart';
import 'package:len/ui/app_theme.dart';

void main() {
  Future<List<bool>> pump(
    WidgetTester tester,
    Widget Function(bool, ValueChanged<bool>) build,
  ) async {
    final changes = <bool>[];
    var value = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Center(
            child: StatefulBuilder(
              builder: (context, setState) => build(value, (v) {
                changes.add(v);
                setState(() => value = v);
              }),
            ),
          ),
        ),
      ),
    );
    return changes;
  }

  testWidgets('AppSwitch toggles by tap and by keyboard, and reads as a toggle', (tester) async {
    final semantics = tester.ensureSemantics();
    final changes = await pump(
      tester,
      (value, onChanged) => AppSwitch(value: value, onChanged: onChanged, semanticLabel: 'Sync'),
    );
    // 44 × 24 visually, padded to a full target.
    expect(tester.getSize(find.byType(AppSwitch)).height, greaterThanOrEqualTo(44));
    expect(
      tester.getSemantics(find.byType(AppSwitch)),
      matchesSemantics(
        label: 'Sync',
        hasToggledState: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );

    await tester.tap(find.byType(AppSwitch));
    await tester.pumpAndSettle();
    expect(changes, [true]);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(changes, [true, false]);
    semantics.dispose();
  });

  testWidgets('AppSwitchTile toggles from anywhere on the row; disabled does nothing', (
    tester,
  ) async {
    final changes = await pump(
      tester,
      (value, onChanged) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppSwitchTile(title: 'Page templates', value: value, onChanged: onChanged),
          const AppSwitchTile(title: 'Off', value: false, onChanged: null),
        ],
      ),
    );
    await tester.tap(find.text('Page templates'));
    await tester.pumpAndSettle();
    expect(changes, [true]);
    await tester.tap(find.text('Off'));
    await tester.pumpAndSettle();
    expect(changes, [true]);
  });
}
