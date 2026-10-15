import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/features/editor/clipboard/paste_peek.dart';
import 'package:len/ink/selection/ink_clipboard.dart';
import 'package:pasteboard/pasteboard.dart';

import 'support/fake_server.dart' show bigStroke;

/// Makes the `pasteboard` plugin answer "peek" with [answer] (or throw it,
/// if it is an exception); counts the calls.
int Function() mockPeek(Object? answer) {
  var calls = 0;
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(const MethodChannel('pasteboard'), (call) async {
    if (call.method != 'peek') return null;
    calls++;
    if (answer is Exception) throw answer;
    return answer;
  });
  addTearDown(
    () => messenger.setMockMethodCallHandler(
      const MethodChannel('pasteboard'),
      (call) async => const {'files', 'peek'}.contains(call.method) ? const <Object>[] : null,
    ),
  );
  return () => calls;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Pasteboard.peek', () {
    test('names the kinds the platform reports, skipping unknown ones', () async {
      mockPeek(const ['image', 'text', 'html', 'files', 'video']);
      expect(await Pasteboard.peek(), {
        PasteboardKind.image,
        PasteboardKind.text,
        PasteboardKind.html,
        PasteboardKind.files,
      });
    });

    test('an empty clipboard is an empty set', () async {
      mockPeek(const <Object>[]);
      expect(await Pasteboard.peek(), isEmpty);
    });

    test('is unknown (null) when the platform can not tell or fails', () async {
      mockPeek(null);
      expect(await Pasteboard.peek(), isNull);
      mockPeek(PlatformException(code: 'x'));
      expect(await Pasteboard.peek(), isNull);
    });

    test('never reads the clipboard', () async {
      final methods = <String>[];
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(const MethodChannel('pasteboard'), (call) async {
        methods.add(call.method);
        return const ['text'];
      });
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        methods.add(call.method);
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(
          const MethodChannel('pasteboard'),
          (call) async => const {'files', 'peek'}.contains(call.method) ? const <Object>[] : null,
        );
        messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
      });
      await Pasteboard.peek();
      expect(methods, ['peek']);
    });
  });

  group('mayPaste', () {
    test('follows the system clipboard while Len copied nothing', () async {
      final own = InkClipboard();
      Future<Set<PasteboardKind>?> answer(Set<PasteboardKind>? kinds) async => kinds;
      expect(await mayPaste(own, peek: () => answer({PasteboardKind.image})), isTrue);
      expect(await mayPaste(own, peek: () => answer({PasteboardKind.text})), isTrue);
      expect(await mayPaste(own, peek: () => answer({PasteboardKind.files})), isTrue);
      expect(await mayPaste(own, peek: () => answer({})), isFalse);
      expect(await mayPaste(own, peek: () => answer(null)), isTrue, reason: 'unknown');
      expect(await mayPaste(own, peek: () => Future.error(StateError('x'))), isTrue);
    });

    test('through the plugin', () async {
      final own = InkClipboard();
      mockPeek(const ['image']);
      expect(await mayPaste(own), isTrue);
      mockPeek(const <Object>[]);
      expect(await mayPaste(own), isFalse);
    });

    test('Len’s own ink is pasteable without asking', () async {
      final own = InkClipboard()..put([bigStroke('s', 'p', 3)], const [], Rect.zero);
      final calls = mockPeek(const <Object>[]);
      expect(await mayPaste(own), isTrue);
      expect(calls(), 0);
    });

    test('a clipboard that does not answer leaves the row', () async {
      final never = Completer<Set<PasteboardKind>?>();
      expect(await mayPaste(InkClipboard(), peek: () => never.future), isTrue);
    });
  });
}
