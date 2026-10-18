import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/features/editor/split/split_view.dart';
import 'package:len/features/editor/stylus_edge_guard.dart';
import 'package:len/platform/stylus_edges.dart';

import 'document_editor_test.dart' show closeEditor, pumpEditor;

/// Records the `edges` messages sent on the low-latency ink channel.
List<bool> recordEdges(WidgetTester tester) {
  final sent = <bool>[];
  const codec = StandardMessageCodec();
  tester.binding.defaultBinaryMessenger.setMockMessageHandler('len/low_latency_ink', (data) async {
    final message = codec.decodeMessage(data) as List<Object?>;
    if (message.first == 'edges') sent.add(message[1]! as bool);
    return null;
  });
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMessageHandler('len/low_latency_ink', null),
  );
  return sent;
}

void main() {
  group('StylusEdges', () {
    testWidgets('guards from the first hold to the last release', (tester) async {
      final sent = recordEdges(tester);
      final edges = StylusEdges(supported: true);
      edges
        ..hold()
        ..hold();
      expect(edges.guarded, isTrue);
      edges.release();
      expect(sent, [true]);
      edges.release();
      expect(edges.guarded, isFalse);
      expect(sent, [true, false]);
    });

    testWidgets('sends nothing where unsupported', (tester) async {
      final sent = recordEdges(tester);
      StylusEdges(supported: false)
        ..hold()
        ..release();
      expect(sent, isEmpty);
    });
  });

  testWidgets('the editor guards the edges while it is open', (tester) async {
    expect(stylusEdges.guarded, isFalse);
    await pumpEditor(tester);
    expect(stylusEdges.guarded, isTrue);
    await closeEditor(tester);
    expect(stylusEdges.guarded, isFalse);
  });

  group('StylusEdgeGuard', () {
    late StylusEdges edges;
    late List<bool> sent;

    setUp(() => edges = StylusEdges(supported: true));

    Widget editor() => StylusEdgeGuard(edges: edges, child: const Text('editor'));

    testWidgets('guards while the editor shows, not after it goes', (tester) async {
      sent = recordEdges(tester);
      await tester.pumpWidget(MaterialApp(home: editor()));
      expect(sent, [true]);
      await tester.pumpWidget(const MaterialApp(home: Text('library')));
      expect(sent, [true, false]);
    });

    testWidgets('not while a screen or a dialog is over it', (tester) async {
      sent = recordEdges(tester);
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MaterialApp(navigatorKey: navigator, home: editor()));
      navigator.currentState!
          .push(MaterialPageRoute<void>(builder: (_) => const Text('settings')))
          .ignore();
      await tester.pumpAndSettle();
      expect(sent, [true, false]);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(sent, [true, false, true]);
      showDialog<void>(
        context: navigator.currentContext!,
        builder: (_) => const Text('dialog'),
      ).ignore();
      await tester.pumpAndSettle();
      expect(sent, [true, false, true, false]);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(sent, [true, false, true, false, true]);
    });

    testWidgets('two panes hold it once; a parked pane not at all', (tester) async {
      sent = recordEdges(tester);
      tester.view
        ..physicalSize = const Size(1440, 900)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      Widget split(Widget secondary, bool? solo) => MaterialApp(
        home: SplitView(
          primary: editor(),
          secondary: secondary,
          fraction: 0.5,
          onFraction: (_) {},
          solo: solo,
        ),
      );
      await tester.pumpWidget(split(editor(), null));
      expect(sent, [true]);
      await tester.pumpWidget(split(editor(), true));
      expect(sent, [true]); // The second pane still shows.
      await tester.pumpWidget(split(const Text('reader'), true));
      expect(sent, [true, false]); // Only the parked primary is an editor.
      await tester.pumpWidget(split(const Text('reader'), null));
      expect(sent, [true, false, true]);
    });
  });
}
