import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/text/html_text.dart';
import 'package:len/domain/text/text_data.dart';

import 'content_tools_ui_test.dart';
import 'flutter_test_config.dart' show mockEmptyClipboard;
import 'images_ui_test.dart' show settleReal;
import 'text_box_ui_test.dart' show ctrl, paste;

/// Rich copy to other apps (UX_AUDIT round 19): Copy in a text box puts
/// HTML on the system clipboard besides the plain text; pasting it back
/// in Len keeps Len's own formatting.

/// The system clipboard as `pasteboard`'s `write` and Flutter's plain
/// text calls leave it.
class _SystemClipboard {
  _SystemClipboard() {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = MethodChannel('pasteboard');
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'write':
          final args = call.arguments as Map<Object?, Object?>;
          text = args['text'] as String?;
          html = args['html'] as String?;
          writes++;
          return true;
        case 'html':
          return null; // (Linux sends bytes; not read here: Len's own copy wins.)
        case 'files' || 'peek':
          return const <Object>[];
      }
      return null;
    });
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') return text == null ? null : {'text': text};
      if (call.method == 'Clipboard.setData') plainWrites++;
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => const {'files', 'peek'}.contains(call.method) ? const <Object>[] : null,
      );
      mockEmptyClipboard();
    });
  }

  String? text;
  String? html;
  int writes = 0;
  int plainWrites = 0;
}

void main() {
  testWidgets('Ctrl+C in a text box writes HTML too; Ctrl+V in Len keeps its formatting', (
    tester,
  ) async {
    final clipboard = _SystemClipboard();
    final (services, nb) = await openCanvas(tester);
    await key(tester, LogicalKeyboardKey.keyT);
    await mouseDrag(tester, const [Offset(300, 400)]);
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('text-box-field'));
    await tester.enterText(field, 'Trip\nSocks');
    await tester.pump();
    await ctrl(tester, LogicalKeyboardKey.keyA);
    await ctrl(tester, LogicalKeyboardKey.keyB);
    await ctrl(tester, LogicalKeyboardKey.digit8, shift: true); // Bulleted list.
    await ctrl(tester, LogicalKeyboardKey.keyC);
    await tester.pump();

    expect(clipboard.writes, 1);
    expect(clipboard.plainWrites, 0);
    expect(clipboard.text, 'Trip\nSocks');
    // Linux: a UTF-8 document; the formatting read back as Docs would.
    expect(clipboard.html, startsWith('<meta charset="utf-8">'));
    expect(clipboard.html, contains('<ul><li><b>Trip</b></li><li><b>Socks</b></li></ul>'));
    final read = textFromHtml(clipboard.html!, const TextData())!;
    expect(read.text, 'Trip\nSocks');
    expect(read.paras, everyElement(const ParaStyle(list: ListKind.bullet)));
    expect(read.spans, const [
      StyledRange(0, 4, SpanStyle(bold: true)),
      StyledRange(5, 10, SpanStyle(bold: true)),
    ]);

    // Pasted on the canvas: Len's own copy, list and all.
    await key(tester, LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await paste(tester);
    await tester.pumpAndSettle();
    final boxes = liveElements(services, nb.id);
    expect(boxes, hasLength(2));
    final copied = TextData.fromJson(boxes.first.data);
    final pasted = TextData.fromJson(boxes.last.data);
    expect(pasted.text, 'Trip\nSocks');
    expect(pasted.paras, everyElement(const ParaStyle(list: ListKind.bullet)));
    expect(pasted.spans, copied.spans);
  });

  testWidgets('lasso Copy of text boxes writes their HTML', (tester) async {
    final clipboard = _SystemClipboard();
    await openCanvas(tester);
    await key(tester, LogicalKeyboardKey.keyT);
    await mouseDrag(tester, const [Offset(300, 400)]);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('text-box-field')), 'Title');
    await tester.pump();
    await ctrl(tester, LogicalKeyboardKey.keyA);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1); // Heading 1.
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await key(tester, LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await ctrl(tester, LogicalKeyboardKey.keyA); // Selects everything on the page.
    await tester.pumpAndSettle();
    await ctrl(tester, LogicalKeyboardKey.keyC);
    await settleReal(tester, () => clipboard.writes == 1);
    expect(clipboard.text, 'Title');
    expect(clipboard.html, contains('<h1>Title</h1>'));
  });
}
