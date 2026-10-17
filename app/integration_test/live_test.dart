// End-to-end, live sync: two app instances at once (tool/e2e.sh starts
// this file twice, LEN_E2E_ROLE=a and =b, each with its own data
// directory) on one server. A writes; B sees A's pointer, then the stroke
// as A writes it, then its record — all over the live connection, without
// a pull. The two talk through files in $E2E_OUT/live/.
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/features/editor/editor_canvas.dart';
import 'package:len/features/editor/editor_screen.dart';
import 'package:len/features/editor/shared/shared_notebook.dart';
import 'package:len/features/library/notebook_card.dart';
import 'package:len/sync/sync_controller.dart';

import 'support/e2e.dart';
import 'support/flows.dart';

const _title = 'Live notes';
final _role = Platform.environment['LEN_E2E_ROLE'] ?? 'a';

/// A signal file between the two instances.
File _signal(String name) => File('${E2E.out}/live/$name');

void _say(String name) => _signal(name).createSync(recursive: true);

/// Pumps (doing [meanwhile] before each frame, if given) until the other
/// instance says [name].
Future<void> _heard(WidgetTester tester, String name, {Future<void> Function()? meanwhile}) async {
  final end = DateTime.now().add(const Duration(seconds: 120));
  while (!_signal(name).existsSync()) {
    if (DateTime.now().isAfter(end)) fail('Timed out waiting for the other device: $name');
    if (meanwhile != null) await meanwhile();
    await tester.pump(const Duration(milliseconds: 16));
  }
}

SharedNotebook _shared(WidgetTester tester) =>
    tester.widget<EditorCanvas>(find.byType(EditorCanvas)).session.shared;

void main() {
  initE2E();

  testWidgets('live sync between two running devices ($_role)', (tester) async {
    final s = await launchApp(tester);
    _say('$_role-started');
    if (_role == 'a') {
      await _writer(tester, s);
    } else {
      await _watcher(tester, s);
    }
    await closeApp(tester);
    expectCleanLog();
  });
}

/// Device A: makes the notebook, waits for B in it, points and writes.
Future<void> _writer(WidgetTester tester, AppServices s) async {
  await connectSync(tester, s);
  await createNotebook(tester, _title);
  final nb = s.notebooks.list().single;
  // On the server (pushed live once the first sync ran), then B may come.
  final end = DateTime.now().add(const Duration(seconds: 30));
  while (!((await serverRecords())['notebooks'] ?? const []).any((n) => n['id'] == nb.id)) {
    if (DateTime.now().isAfter(end)) fail('the notebook never reached the server');
    await tester.pump(const Duration(milliseconds: 100));
  }
  _say('a-ready');
  await waitFor(
    tester,
    () => s.sync.rooms.othersIn(nb.id).isNotEmpty,
    reason: 'device B in the notebook',
    timeout: const Duration(seconds: 120),
  );

  // Hover the mouse over the page until B shows the pointer.
  final c = tester.getCenter(find.byType(EditorScreen));
  final mouse = TestPointer(41, PointerDeviceKind.mouse);
  var x = 0.0;
  await _heard(
    tester,
    'b-saw-pointer',
    meanwhile: () async {
      x = (x + 4) % 200;
      await tester.sendEventToBinding(mouse.hover(c + Offset(x - 100, -150)));
    },
  );
  await tester.sendEventToBinding(mouse.removePointer());

  // Write a stroke, the pen held down (moving) until B shows it live.
  await press(tester, LogicalKeyboardKey.keyP);
  const pointer = 950;
  var t = Duration.zero;
  var at = c + const Offset(-150, 0);
  PointerEvent next({bool down = false}) {
    t += const Duration(milliseconds: 8);
    at += Offset(1.5, (t.inMilliseconds % 64 < 32) ? 1 : -1);
    final make = down ? PointerDownEvent.new : PointerMoveEvent.new;
    return make(
      timeStamp: t,
      pointer: pointer,
      kind: PointerDeviceKind.stylus,
      position: at,
      pressure: 0.5,
      pressureMax: 1,
    );
  }

  await tester.sendEventToBinding(next(down: true));
  var moves = 0;
  await _heard(
    tester,
    'b-saw-live',
    meanwhile: () async {
      if (moves++ < 2000) await tester.sendEventToBinding(next());
    },
  );
  await tester.sendEventToBinding(
    PointerUpEvent(timeStamp: t, pointer: pointer, kind: PointerDeviceKind.stylus, position: at),
  );
  await settle(tester);
  final page = s.pages.pagesOf(nb.id).single;
  expect(count(s, 'strokes', "surface_id = '${page.id}'"), 1);
  await snapshot(tester, 'live_a_wrote');
  await _heard(tester, 'b-got-record');
  await tapTooltip(tester, 'Back');
  await pumpUntil(tester, find.byType(NotebookCard));
}

/// Device B: opens A's notebook, then sees A's pointer, live stroke and
/// record arrive without pulling.
Future<void> _watcher(WidgetTester tester, AppServices s) async {
  await _heard(tester, 'a-ready');
  await connectSync(tester, s);
  await pumpUntil(tester, find.text(_title));
  final nb = s.notebooks.list().single;
  final page = s.pages.pagesOf(nb.id).single;
  int strokes() => count(s, 'strokes', "surface_id = '${page.id}'");
  expect(strokes(), 0);
  await tester.tap(find.ancestor(of: find.text(_title), matching: find.byType(NotebookCard)));
  await pumpUntil(tester, find.byType(EditorScreen));
  await settle(tester);
  // From here on, nothing may pull: everything comes over the live channel.
  var runs = 0;
  var was = s.sync.state;
  void counting() {
    if (s.sync.state == SyncState.syncing && was != SyncState.syncing) runs++;
    was = s.sync.state;
  }

  s.sync.addListener(counting);
  addTearDown(() => s.sync.removeListener(counting));
  final shared = _shared(tester);
  expect(find.bySemanticsLabel(RegExp('Also open on')), findsOneWidget, reason: 'presence');

  await waitFor(
    tester,
    () => shared.remotePointers.pointers.any((p) => p.surface == page.id && p.hover != null),
    reason: 'A\'s pointer',
    timeout: const Duration(seconds: 60),
  );
  await snapshot(tester, 'live_b_pointer');
  _say('b-saw-pointer');

  await waitFor(
    tester,
    () => shared.remoteInk.strokesOn(page.id).isNotEmpty,
    reason: 'A\'s stroke as it is written',
    timeout: const Duration(seconds: 60),
  );
  expect(strokes(), 0, reason: 'live ink, not a record yet');
  await snapshot(tester, 'live_b_live_ink');
  _say('b-saw-live');

  await waitFor(
    tester,
    () => strokes() == 1 && shared.remoteInk.isEmpty,
    reason: 'A\'s stroke record, in place of the live ink',
  );
  final model = tester.widget<EditorCanvas>(find.byType(EditorCanvas)).session.doc!.activeModel;
  expect(model.loadedStrokeCount, 1, reason: 'drawn on the open page');
  expect(runs, 0, reason: 'no pull: it came over the live connection');
  await snapshot(tester, 'live_b_record');
  _say('b-got-record');
  await tapTooltip(tester, 'Back');
  await pumpUntil(tester, find.byType(NotebookCard));
}
