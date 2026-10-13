import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show FocusManager, SizedBox;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:len/app.dart';
import 'package:len/app_services.dart';
import 'package:len/features/library/library_screen.dart';
import 'package:len/main.dart' as app;

/// Settings handed in by `tool/e2e.sh` (`--dart-define`).
abstract final class E2E {
  /// The local sync server (empty: sync is skipped).
  static const server = String.fromEnvironment('E2E_SERVER');
  static const token = String.fromEnvironment('E2E_TOKEN');

  /// A scratch directory for files the flows read and write (exports,
  /// images to insert, screenshots).
  static const out = String.fromEnvironment('E2E_OUT', defaultValue: '/tmp/len-e2e');
}

/// Lines the app logged with `debugPrint` during the current test.
final logged = <String>[];

/// Errors reported to the platform dispatcher (outside any zone).
final platformErrors = <Object>[];

/// Stands in for the system file dialogs (GTK), which a test cannot click:
/// "picks" the queued files and "saves" to the queued paths. Everything
/// after the dialog (reading, writing, decoding) is the real thing.
class ScriptedFileSelector extends FileSelectorPlatform {
  final openQueue = <List<String>>[];
  final saveQueue = <String>[];
  final directoryQueue = <String>[];

  /// Every dialog shown, by kind (`open`, `save`, `directory`).
  final shown = <String>[];

  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    final files = await openFiles(acceptedTypeGroups: acceptedTypeGroups);
    return files.isEmpty ? null : files.first;
  }

  @override
  Future<List<XFile>> openFiles({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    shown.add('open');
    if (openQueue.isEmpty) return const [];
    return [for (final p in openQueue.removeAt(0)) XFile(p)];
  }

  @override
  Future<FileSaveLocation?> getSaveLocation({
    List<XTypeGroup>? acceptedTypeGroups,
    SaveDialogOptions options = const SaveDialogOptions(),
  }) async {
    shown.add('save');
    return saveQueue.isEmpty ? null : FileSaveLocation(saveQueue.removeAt(0));
  }

  @override
  Future<String?> getDirectoryPath({String? initialDirectory, String? confirmButtonText}) async {
    shown.add('directory');
    return directoryQueue.isEmpty ? null : directoryQueue.removeAt(0);
  }
}

final files = ScriptedFileSelector();

/// Initialises the integration binding once per test file.
IntegrationTestWidgetsFlutterBinding initE2E() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Pump real frames as the app would get them (animations, tiles).
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  Directory(E2E.out).createSync(recursive: true);
  return binding;
}

/// Starts the real app (`main()`: the real data directory under
/// `$XDG_DATA_HOME`, SQLite, plugins) and waits for the library. Returns
/// its services, for checks against the database.
Future<AppServices> launchApp(WidgetTester tester) async {
  logged.clear();
  platformErrors.clear();
  softFailures.clear();
  final previousPrint = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) logged.add(message);
    previousPrint(message, wrapWidth: wrapWidth);
  };
  addTearDown(() => debugPrint = previousPrint);
  final previousOnError = ui.PlatformDispatcher.instance.onError;
  ui.PlatformDispatcher.instance.onError = (error, stack) {
    platformErrors.add(error);
    // ignore: avoid_print
    print('PlatformDispatcher error: $error\n$stack');
    return true;
  };
  addTearDown(() => ui.PlatformDispatcher.instance.onError = previousOnError);
  FileSelectorPlatform.instance = files;

  await app.main(const []);
  await pumpUntil(tester, find.byType(LibraryScreen));
  await settle(tester);
  return tester.widget<LenApp>(find.byType(LenApp)).services;
}

/// Unmounts the app (its widgets' dispose paths run, as when the last
/// window closes) so nothing is left running into the test's teardown.
Future<void> closeApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await settle(tester);
}

/// Problems found by [soft] checks (reported together at the end).
final softFailures = <String>[];

/// Records a failed expectation without stopping the flow, so one run
/// finds every problem after it too. [expectCleanLog] reports them.
void soft(bool ok, String what) {
  if (ok) return;
  softFailures.add(what);
  // ignore: avoid_print
  print('E2E SOFT FAILURE: $what (focus: ${FocusManager.instance.primaryFocus})');
}

/// Fails if the app logged an error, a failure or an exception (caught
/// ones included: they are bugs the user only sees as "nothing happened").
void expectCleanLog({List<Pattern> allowed = const []}) {
  final bad = RegExp(r'error|exception|failed|unhandled', caseSensitive: false);
  final problems = [
    for (final line in logged)
      if (bad.hasMatch(line) && !allowed.any(line.contains)) line,
  ];
  expect(softFailures, isEmpty, reason: 'checks that failed along the way');
  expect(problems, isEmpty, reason: 'the app logged problems');
  expect(platformErrors, isEmpty, reason: 'uncaught platform errors');
}

/// Pumps frames until [finder] finds something (or fails after [timeout]).
Future<void> pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final end = DateTime.now().add(timeout);
  while (finder.evaluate().isEmpty) {
    if (DateTime.now().isAfter(end)) {
      fail('Timed out waiting for $finder');
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Pumps until [condition] holds (async work: database, isolates, network).
Future<void> waitFor(
  WidgetTester tester,
  bool Function() condition, {
  String reason = 'condition',
  Duration timeout = const Duration(seconds: 30),
}) async {
  final end = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(end)) fail('Timed out waiting for $reason');
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Lets animations finish (bounded: a spinner never settles).
Future<void> settle(WidgetTester tester, [Duration max = const Duration(seconds: 5)]) async {
  try {
    await tester.pumpAndSettle(
      const Duration(milliseconds: 50),
      EnginePhase.sendSemanticsUpdate,
      max,
    );
  } on FlutterError {
    // Still animating (e.g. a progress indicator): good enough.
  }
}

Future<void> tapText(WidgetTester tester, String text, {bool last = false}) async {
  final f = find.text(text);
  await pumpUntil(tester, f);
  await tester.tap(last ? f.last : f.first);
  await settle(tester);
}

Future<void> tapTooltip(WidgetTester tester, String tooltip) async {
  final f = find.byTooltip(tooltip);
  await pumpUntil(tester, f);
  await tester.tap(f.first);
  await settle(tester);
}

Future<void> press(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool ctrl = false,
  bool shift = false,
}) async {
  if (ctrl) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(key);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  if (ctrl) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await settle(tester);
}

/// A mouse drag through [points], with real time between the samples.
Future<void> mouseStroke(WidgetTester tester, List<Offset> points) async {
  final gesture = await tester.startGesture(points.first, kind: PointerDeviceKind.mouse);
  await tester.pump(const Duration(milliseconds: 16));
  for (final p in points.skip(1)) {
    await gesture.moveTo(p);
    await tester.pump(const Duration(milliseconds: 8));
  }
  await gesture.up();
  await settle(tester);
}

int _stylusPointer = 900;

/// A pen stroke with pressure and tilt, as a stylus on a tablet sends it.
Future<void> stylusStroke(WidgetTester tester, List<Offset> points) async {
  final pointer = _stylusPointer++;
  var t = Duration.zero;
  PointerEvent at(int i) {
    final p = points[i];
    final pressure = 0.3 + 0.5 * (i / (points.length - 1));
    if (i == 0) {
      return PointerDownEvent(
        timeStamp: t,
        pointer: pointer,
        kind: PointerDeviceKind.stylus,
        position: p,
        pressure: pressure,
        pressureMax: 1,
        tilt: 0.4,
      );
    }
    return PointerMoveEvent(
      timeStamp: t,
      pointer: pointer,
      kind: PointerDeviceKind.stylus,
      position: p,
      delta: p - points[i - 1],
      pressure: pressure,
      pressureMax: 1,
      tilt: 0.4,
    );
  }

  for (var i = 0; i < points.length; i++) {
    t += const Duration(milliseconds: 8);
    await tester.sendEventToBinding(at(i));
    await tester.pump(const Duration(milliseconds: 8));
  }
  await tester.sendEventToBinding(
    PointerUpEvent(
      timeStamp: t + const Duration(milliseconds: 8),
      pointer: pointer,
      kind: PointerDeviceKind.stylus,
      position: points.last,
    ),
  );
  await settle(tester);
}

/// A wavy line of [n] points from [from], [length] wide.
List<Offset> wave(Offset from, {double length = 200, int n = 24, double amp = 12}) => [
  for (var i = 0; i < n; i++) from + Offset(length * i / (n - 1), amp * ((i % 4) - 1.5)),
];

/// Mouse wheel over [at] ([delta] in logical pixels; positive y scrolls down).
Future<void> wheel(WidgetTester tester, Offset at, Offset delta, {int times = 1}) async {
  final pointer = TestPointer(77, PointerDeviceKind.mouse);
  for (var i = 0; i < times; i++) {
    await tester.sendEventToBinding(pointer.hover(at));
    await tester.sendEventToBinding(pointer.scroll(delta));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await settle(tester);
}

/// Live rows of [table] matching [where].
int count(AppServices s, String table, [String where = '1']) =>
    s.database.db
            .select('SELECT count(*) AS n FROM $table WHERE deleted = 0 AND ($where)')
            .first['n']
        as int;

/// Saves a picture of the whole app window (rendered by the real engine)
/// to `$E2E_OUT/<name>.png`, for looking at after a run.
Future<void> snapshot(WidgetTester tester, String name) async {
  final view = tester.binding.renderViews.first;
  // ignore: invalid_use_of_protected_member
  final layer = view.debugLayer! as OffsetLayer;
  final image = await layer.toImage(Offset.zero & view.size, pixelRatio: 1);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  File('${E2E.out}/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
}

/// What the Linux (and Windows) embedder sends when the user closes the
/// window; the app may save. (Here nothing exits: the test ends instead.)
Future<void> requestWindowClose(WidgetTester tester) async {
  final reply = Completer<ByteData?>();
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    SystemChannels.platform.name,
    const JSONMethodCodec().encodeMethodCall(const MethodCall('System.requestAppExit')),
    reply.complete,
  );
  final response = const JSONMethodCodec().decodeEnvelope((await reply.future)!);
  expect((response as Map)['response'], 'exit');
}
