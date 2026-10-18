import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/text/text_data.dart';
import 'package:pasteboard/src/pasteboard_platform_io.dart' show decodeRtfBytes;

import 'content_golden_test.dart' show loadFonts;
import 'content_tools_ui_test.dart';
import 'text_box_ui_test.dart' show ctrl, mockClipboardText, paste;

const _html =
    '<meta charset="utf-8"><h1>Trip</h1><p>Pack <b>early</b> and <i>light</i></p>'
    '<ul><li>Clothes<ul><li>Socks</li></ul></li><li>Tickets</li></ul>';

/// Makes the `pasteboard` plugin's channel report [html] and [rtf] (as
/// Linux does: bytes), no image and no files.
void mockClipboardHtml(String? html, {String? rtf}) {
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel('pasteboard');
  messenger.setMockMethodCallHandler(channel, (call) async {
    return switch (call.method) {
      'html' => html == null ? null : Uint8List.fromList(utf8.encode(html)),
      'rtf' => rtf == null ? null : Uint8List.fromList([...latin1.encode(rtf), 0]),
      'files' => <String>[],
      _ => null,
    };
  });
  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
}

const _rtf =
    r'{\rtf1\ansi\ansicpg1252\deff0\nouicompat{\fonttbl{\f0\fnil\fcharset0 Calibri;}'
    r'{\f1\fnil\fcharset2 Symbol;}}{\colortbl ;\red255\green0\blue0;}'
    r'{\*\generator Riched20 10.0.19041}\viewkind4\uc1 \pard\outlinelevel0\f0\fs22 Trip\par'
    r'\pard Pack \b\cf1 early\b0\cf0\par'
    r"{\pntext\f1\'B7\tab}{\*\pn\pnlvlblt\pnf1\pnindent0{\pntxtb\'B7}}\fi-360\li720 Socks\par}";

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

  testWidgets('Ctrl+V on the canvas with RTF but no HTML (WordPad) adds a formatted box', (
    tester,
  ) async {
    mockClipboardText('Trip\nPack early\nSocks');
    mockClipboardHtml(null, rtf: _rtf);
    final (services, nb) = await openCanvas(tester);
    await paste(tester);
    final data = TextData.fromJson(liveElements(services, nb.id).single.data);
    expect(data.text, 'Trip\nPack early\nSocks');
    expect(data.paras, const [
      ParaStyle(heading: 1),
      ParaStyle.body,
      ParaStyle(list: ListKind.bullet),
    ]);
    expect(data.spans, const [StyledRange(10, 15, SpanStyle(bold: true, color: 0xFFFF0000))]);
  });

  testWidgets('Ctrl+V in a text box inserts RTF formatted; HTML wins when both are offered', (
    tester,
  ) async {
    mockClipboardText('x');
    mockClipboardHtml(null, rtf: r"{\rtf1\ansi a {\i caf\'e9}}");
    final (services, nb) = await openCanvas(tester);
    await key(tester, LogicalKeyboardKey.keyT);
    await mouseDrag(tester, const [Offset(300, 400)]);
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('text-box-field'));
    await tester.enterText(field, 'Start: ');
    await tester.pump();
    await paste(tester);
    mockClipboardHtml('<b>B</b>', rtf: r'{\rtf1 R}');
    await paste(tester);
    await key(tester, LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    final data = TextData.fromJson(liveElements(services, nb.id).single.data);
    expect(data.text, 'Start: a caféB');
    expect(data.spans, const [
      StyledRange(9, 13, SpanStyle(italic: true)),
      StyledRange(13, 14, SpanStyle(bold: true)),
    ]);
  });

  test('RTF bytes: Latin-1 unless UTF-8, trailing NULs dropped', () {
    expect(
      decodeRtfBytes(Uint8List.fromList([...latin1.encode(r'{\rtf1 é}'), 0, 0])),
      r'{\rtf1 é}',
    );
    expect(decodeRtfBytes(Uint8List.fromList(utf8.encode(r'{\rtf1 é}'))), r'{\rtf1 é}');
  });

  testWidgets('golden: a text box pasted from HTML (heading, bold / italic, nested list)', (
    tester,
  ) async {
    await loadFonts();
    mockClipboardText('Trip');
    mockClipboardHtml(
      '<h1>Weekend trip</h1><p>Pack <b>early</b>, travel <i>light</i> and '
      '<span style="color:#e03131">book</span> <u>today</u></p>'
      '<ul><li>Clothes<ul><li>Socks</li><li>Rain jacket</li></ul></li>'
      '<li><s>Tickets</s></li></ul><ol><li>Pick up keys</li><li>Water plants</li></ol>',
    );
    await openCanvas(tester);
    await paste(tester);
    await key(tester, LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(Directionality).first,
      matchesGoldenFile('goldens/text_pasted_html.png'),
    );
  });
}
