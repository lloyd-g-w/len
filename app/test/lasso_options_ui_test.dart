import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/features/editor/tools/lasso_options_panel.dart';
import 'package:len/ink/tool_settings.dart';
import 'package:len/ui/adaptive_popover.dart';
import 'package:len/ui/app_theme.dart';

import 'content_golden_test.dart' show loadFonts;

/// The panel as the popover shows it: 320 wide, padded 16, on an overlay
/// surface.
Widget _popover(ToolSettings tools, ThemeData theme) => Theme(
  data: theme,
  child: Builder(
    builder: (context) => Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.all(Gaps.lg),
        child: OverlaySurface(
          child: SizedBox(
            width: popoverWidth,
            child: Padding(
              padding: const EdgeInsets.all(Gaps.lg),
              child: Material(
                type: MaterialType.transparency,
                child: LassoOptionsPanel(tools: tools),
              ),
            ),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('the lasso options set shape, cover and kinds; one kind stays on', (tester) async {
    final tools = ToolSettings();
    addTearDown(tools.dispose);
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light(), home: _popover(tools, AppTheme.light())),
    );
    expect(find.text('Selects items mostly inside the lasso'), findsOneWidget);

    await tester.tap(find.text('Rectangle'));
    await tester.tap(find.text('Touching'));
    await tester.pump();
    expect(tools.lasso.shape, LassoShape.rectangle);
    expect(tools.lasso.cover, LassoCover.touching);
    expect(find.text('Selects whatever the lasso touches'), findsOneWidget);

    for (final kind in ['Text', 'Images', 'Highlighter']) {
      await tester.tap(find.text(kind));
      await tester.pump();
    }
    expect(tools.lasso.kinds, {LassoKind.ink});
    await tester.tap(find.text('Ink')); // The last one: stays on.
    await tester.pump();
    expect(tools.lasso.kinds, {LassoKind.ink});
    await tester.tap(find.text('Text'));
    await tester.pump();
    expect(tools.lasso.kinds, {LassoKind.ink, LassoKind.text});

    await tester.tap(find.text('Reset'));
    await tester.pump();
    expect(tools.lasso, const LassoConfig());
    expect(tester.takeException(), isNull);
  });

  testWidgets('lasso options popover, light and dark', (tester) async {
    await loadFonts();
    tester.view
      ..physicalSize = const Size(740, 400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final light = ToolSettings();
    final dark = ToolSettings()
      ..lasso = const LassoConfig(
        shape: LassoShape.rectangle,
        cover: LassoCover.whole,
        kinds: {LassoKind.ink, LassoKind.text},
      );
    addTearDown(light.dispose);
    addTearDown(dark.dispose);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: Row(
          children: [
            Expanded(
              child: ColoredBox(
                color: AppTheme.light().colorScheme.surfaceContainerLow,
                child: _popover(light, AppTheme.light()),
              ),
            ),
            Expanded(
              child: ColoredBox(
                color: AppTheme.dark().colorScheme.surfaceContainerLow,
                child: _popover(dark, AppTheme.dark()),
              ),
            ),
          ],
        ),
      ),
    );
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/lasso_options.png'));
    expect(tester.takeException(), isNull);
  });
}
