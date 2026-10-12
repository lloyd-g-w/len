import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/text/text_data.dart';

import 'content_tools_ui_test.dart';
import 'text_box_ui_test.dart' show ctrl, mockClipboardText, paste;

const _html =
    '<meta charset="utf-8"><h1>Trip</h1><p>Pack <b>early</b> and <i>light</i></p>'
    '<ul><li>Clothes<ul><li>Socks</li></ul></li><li>Tickets</li></ul>';

/// Makes the `pasteboard` plugin's channel report [html] (as Linux does:
/// UTF-8 bytes), no image and no files.
void mockClipboardHtml(String? html) {
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel('pasteboard');
  messenger.setMockMethodCallHandler(channel, (call) async {
    return switch (call.method) {
      'html' => html == null ? null : Uint8List.fromList(utf8.encode(html)),
      'files' => <String>[],
      _ => null,
    };
  });
  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
}

void main() {
  testWidgets('Ctrl+V on the canvas with HTML adds a formatted text box (undoable)', (
    tester,
  ) async {
    mockClipboardText('Trip\nPack early and light\nClothes\nSocks\nTickets');
    mockClipboardHtml(_html);
    final (services, nb) = await openCanvas(tester);
    await paste(tester);
    final data = TextData.fromJson(liveElements(services, nb.id).single.data);
    expect(data.text, 'Trip\nPack early and light\nClothes\nSocks\nTickets');
    expect(data.paras, const [
      ParaStyle(heading: 1),
      ParaStyle.body,
      ParaStyle(list: ListKind.bullet),
      ParaStyle(list: ListKind.bullet, indent: 1),
      ParaStyle(list: ListKind.bullet),
    ]);
    expect(data.spans, const [
      StyledRange(10, 15, SpanStyle(bold: true)),
      StyledRange(20, 25, SpanStyle(italic: true)),
    ]);
    await tester.tap(find.byTooltip('Undo (Ctrl+Z)'));
    await tester.pump();
    expect(liveElements(services, nb.id), isEmpty);
  });

  testWidgets('Ctrl+Shift+V on the canvas pastes plain text', (tester) async {
    mockClipboardText('Trip');
    mockClipboardHtml('<h1>Trip</h1>');
    final (services, nb) = await openCanvas(tester);
    await ctrl(tester, LogicalKeyboardKey.keyV, shift: true);
    await tester.pump();
    await tester.pump();
    final data = TextData.fromJson(liveElements(services, nb.id).single.data);
    expect((data.text, data.isRich), ('Trip', false));
  });

  testWidgets('Ctrl+V in a text box inserts HTML formatted at the caret; Ctrl+Shift+V plain', (
    tester,
  ) async {
    mockClipboardText('x');
    mockClipboardHtml('<p>a <b>bold</b> word</p><ol><li>one</li><li>two</li></ol>');
    final (services, nb) = await openCanvas(tester);
    await key(tester, LogicalKeyboardKey.keyT);
    await mouseDrag(tester, const [Offset(300, 400)]);
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('text-box-field'));
    await tester.enterText(field, 'Start: ');
    await tester.pump();
    await paste(tester);
    await ctrl(tester, LogicalKeyboardKey.keyV, shift: true);
    await tester.pump();
    await key(tester, LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    final data = TextData.fromJson(liveElements(services, nb.id).single.data);
    expect(data.text, 'Start: a bold word\none\ntwox');
    expect(data.spans, const [StyledRange(9, 13, SpanStyle(bold: true))]);
    expect(data.paras, const [
      ParaStyle.body,
      ParaStyle(list: ListKind.number),
      ParaStyle(list: ListKind.number),
    ]);
    await tester.tap(find.byTooltip('Undo (Ctrl+Z)'));
    await tester.pump();
    expect(liveElements(services, nb.id), isEmpty);
  });
}
