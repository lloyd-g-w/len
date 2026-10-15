import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:len/domain/surface_element.dart';
import 'package:len/ink/selection/selection_image.dart';

import 'content_documents_test.dart' show textBox;
import 'content_tools_ui_test.dart' show key, liveElements, liveStrokes, mouseDrag, seedStroke;
import 'flutter_test_config.dart' show mockEmptyClipboard;
import 'images_test.dart' show pngOf;
import 'images_ui_test.dart' show ctrl, openImageCanvas, settleReal;

/// Lasso Copy reaches other apps (UX_AUDIT R13-4): it puts a picture of the
/// selection (and the text of text boxes) on the system clipboard, and
/// pasting back in Len still gives ink.

/// A system clipboard as the platform keeps it: what `write` put there, its
/// image handed back re-encoded (as GTK does), its text as plain text.
class _SystemClipboard {
  _SystemClipboard() {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('pasteboard'), (call) async {
      switch (call.method) {
        case 'write':
          final args = call.arguments as Map<Object?, Object?>;
          writes++;
          // Until the platform has it, the clipboard holds what it held.
          final written = await (hold?.future ?? Future.value(true));
          png = args['png'] as Uint8List?;
          text = args['text'] as String?;
          return written;
        case 'image':
          reads++;
          final bytes = png;
          return bytes == null ? null : img.encodePng(img.decodePng(bytes)!, level: 1);
        case 'files':
          reads++;
          return const <Object>[];
      }
      return null;
    });
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') {
        reads++;
        return text == null ? null : {'text': text};
      }
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(
        const MethodChannel('pasteboard'),
        (call) async => call.method == 'files' ? const <Object>[] : null,
      );
      mockEmptyClipboard();
    });
  }

  Uint8List? png;
  String? text;
  int writes = 0;

  /// While set, writes finish only once it completes (with the result).
  Completer<bool>? hold;

  /// Reads of the clipboard (Android 12+ announces each as a paste).
  int reads = 0;
}

void main() {
  testWidgets('Copy puts a picture of the ink on the system clipboard; Ctrl+V pastes the ink', (
    tester,
  ) async {
    final (services, nb) = await openImageCanvas(
      tester,
      seed: (s, nb) async => s.strokes.save([seedStroke(nb.id)]),
    );
    final clipboard = _SystemClipboard();
    await key(tester, LogicalKeyboardKey.keyL);
    await mouseDrag(tester, const [Offset(150, 401)]);
    await ctrl(tester, LogicalKeyboardKey.keyC);
    await settleReal(tester, () => clipboard.writes == 1);
    await tester.pump();
    expect(clipboard.reads, 0, reason: 'Copy writes the clipboard, never reads it');
    // The ink's picture, transparent, framed around it; no text.
    final picture = img.decodePng(clipboard.png!)!;
    final ink = liveStrokes(services, nb.id).single;
    final layout = SelectionImage.layoutFor(SelectionImage.drawnBounds([ink], const [])!)!;
    expect((picture.width, picture.height), (layout.width, layout.height));
    expect(picture.getPixel(0, 0).a, 0);
    expect(picture.getPixel(picture.width ~/ 2, picture.height ~/ 2).a, 255);
    expect(clipboard.text, isNull);

    // Pasting it back in Len: ink, not an image.
    await ctrl(tester, LogicalKeyboardKey.keyV);
    await settleReal(tester, () => liveStrokes(services, nb.id).length == 2);
    await tester.pumpAndSettle();
    expect(liveElements(services, nb.id), isEmpty);

    // An image copied in another app afterwards is pasted as an image.
    clipboard.png = pngOf(64, 32);
    await ctrl(tester, LogicalKeyboardKey.keyV);
    await settleReal(tester, () => liveElements(services, nb.id).isNotEmpty);
    await tester.pumpAndSettle();
    expect(liveElements(services, nb.id).single.knownType, ElementType.image);
    expect(liveStrokes(services, nb.id), hasLength(2));
  });

  testWidgets('Ctrl+V right after Ctrl+C pastes the ink, not what the clipboard held', (
    tester,
  ) async {
    final (services, nb) = await openImageCanvas(
      tester,
      seed: (s, nb) async => s.strokes.save([seedStroke(nb.id)]),
    );
    final clipboard = _SystemClipboard()
      ..png =
          pngOf(64, 32) // An older screenshot.
      ..hold = Completer();
    await key(tester, LogicalKeyboardKey.keyL);
    await mouseDrag(tester, const [Offset(150, 401)]);
    await ctrl(tester, LogicalKeyboardKey.keyC);
    await settleReal(tester, () => clipboard.writes == 1);
    // Pasted while the copy's picture is still being written.
    await ctrl(tester, LogicalKeyboardKey.keyV);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    clipboard.hold!.complete(true);
    await settleReal(tester, () => liveStrokes(services, nb.id).length == 2);
    await tester.pumpAndSettle();
    expect(liveElements(services, nb.id), isEmpty);
  });

  testWidgets('copying a text box adds its text; pasting back gives the box, not a new one', (
    tester,
  ) async {
    final (services, nb) = await openImageCanvas(
      tester,
      fonts: true,
      seed: (s, nb) async => s.elements.save([textBox('box', nb.id, at: const Offset(200, 200))]),
    );
    final clipboard = _SystemClipboard();
    await key(tester, LogicalKeyboardKey.keyL);
    await mouseDrag(tester, const [Offset(220, 220)]);
    await ctrl(tester, LogicalKeyboardKey.keyC);
    await settleReal(tester, () => clipboard.writes == 1);
    expect(clipboard.text, 'Hello');
    expect(clipboard.png, isNotNull);

    await ctrl(tester, LogicalKeyboardKey.keyV);
    await settleReal(tester, () => liveElements(services, nb.id).length == 2);
    await tester.pumpAndSettle();
    final boxes = liveElements(services, nb.id);
    expect(boxes.map((e) => e.knownType), everyElement(ElementType.text));
    // The copy keeps the box's size (a pasted text would get a box of its own).
    expect(boxes.map((e) => e.rect.size), everyElement(const Size(300, 40)));
  });
}
