import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/paper.dart';
import 'package:len/features/documents/template_picker.dart';
import 'package:len/ui/app_theme.dart';

Widget _host(Widget child) => MaterialApp(
  theme: AppTheme.light(),
  home: Scaffold(body: Material(child: child)),
);

void main() {
  testWidgets('template picker renders all templates', (tester) async {
    tester.view.physicalSize = const Size(760, 980);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _host(
        const TemplatePicker(
          initial: PageTemplate(style: PaperStyle.cornell, color: PaperColor.cream),
          mode: TemplatePickerMode.create,
        ),
      ),
    );
    for (final style in PaperStyle.values) {
      expect(find.text(style.label), findsOneWidget);
    }
    await expectLater(
      find.byType(TemplatePicker),
      matchesGoldenFile('goldens/template_picker.png'),
    );
  });

  testWidgets('choosing a template returns it', (tester) async {
    TemplateChoice? choice;
    await tester.pumpWidget(
      _host(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async => choice = await showTemplatePicker(
              context,
              initial: const PageTemplate(),
              mode: TemplatePickerMode.change,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Page size'), findsNothing); // Size is fixed when changing.
    await tester.tap(find.text('Dotted'));
    await tester.pump();
    await tester.ensureVisible(find.text('Dark'));
    await tester.tap(find.text('Dark'));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Apply to all pages'));
    await tester.pumpAndSettle();
    expect(choice!.template.style, PaperStyle.dotted);
    expect(choice!.template.color, PaperColor.dark);
    expect(choice!.allPages, isTrue);
  });
}
