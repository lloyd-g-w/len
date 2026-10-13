import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/features/editor/document/paged_document_view.dart';
import 'package:len/features/editor/toolbar/tool_cluster.dart';

import 'document_editor_test.dart' show closeEditor, pumpEditor;

/// The tooltip of the toolbar control with keyboard focus.
String? focusedTooltip() {
  final context = FocusManager.instance.primaryFocus?.context;
  return context?.findAncestorWidgetOfExactType<Tooltip>()?.message;
}

int currentPage(WidgetTester tester) =>
    tester.widget<PagedDocumentView>(find.byType(PagedDocumentView)).controller.currentPage;

void main() {
  testWidgets('← and → move along the toolbar instead of turning pages', (tester) async {
    await pumpEditor(tester, size: const Size(1280, 900));
    final tools = tester.widgetList<ToolButton>(find.byType(ToolButton)).toList();
    final names = [for (final t in tools) t.descriptor.tooltip];

    // Focus the first tool (as Tab would).
    Focus.of(
      tester.element(
        find.descendant(of: find.byTooltip(names[0]), matching: find.byType(ToolGlyph)),
      ),
    ).requestFocus();
    await tester.pump();
    expect(focusedTooltip(), names[0]);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(focusedTooltip(), names[1]);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(focusedTooltip(), names[2]);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(focusedTooltip(), names[1]);
    expect(currentPage(tester), 0, reason: 'the arrows stayed in the toolbar');

    // Space picks the focused tool, as a click would.
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(
      tester
          .widgetList<ToolButton>(find.byType(ToolButton))
          .firstWhere((t) => t.selected)
          .descriptor
          .tooltip,
      names[1],
    );


    // Escape goes back to the page, where → turns pages again.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(focusedTooltip(), isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(currentPage(tester), 1);
    await closeEditor(tester);
  });
}
