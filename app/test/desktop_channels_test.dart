import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/platform/fullscreen.dart';
import 'package:len/platform/incoming_files.dart';

/// The runners' channels as Dart sees them (tests run on a Linux or
/// Windows host, where these code paths are live).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const window = MethodChannel('len/window');
  const incoming = MethodChannel(incomingFilesChannel);

  tearDown(() {
    messenger.setMockMethodCallHandler(window, null);
    messenger.setMockMethodCallHandler(incoming, null);
  });

  test('focus mode asks the runner for full screen', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(window, (call) async {
      calls.add(call);
      return call.arguments;
    });
    expect(await setFullscreen(true), isTrue);
    expect(await setFullscreen(false), isFalse);
    expect(calls.map((c) => '${c.method}(${c.arguments})'), [
      'setFullScreen(true)',
      'setFullScreen(false)',
    ]);
  });

  test('without the runner channel, full screen is simply unavailable', () async {
    expect(await setFullscreen(true), isFalse);
  });

  test('files forwarded by a second launch arrive once ready; missing ones are dropped', () async {
    final dir = await Directory.systemTemp.createTemp('len_incoming');
    addTearDown(() => dir.delete(recursive: true));
    final pdf = File('${dir.path}/a.pdf')..writeAsBytesSync([1]);
    var ready = false;
    messenger.setMockMethodCallHandler(incoming, (call) async {
      if (call.method == 'ready') ready = true;
      return null;
    });

    final batches = <List<XFile>>[];
    final subscription = openIncomingFiles(const []).listen(batches.add);
    addTearDown(subscription.cancel);
    await pumpEventQueue();
    expect(ready, isTrue);

    await messenger.handlePlatformMessage(
      incomingFilesChannel,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('files', [
          {'path': pdf.path, 'name': 'a.pdf'},
          {'path': '${dir.path}/typo.pdf', 'name': 'typo.pdf'},
        ]),
      ),
      (_) {},
    );
    await pumpEventQueue();
    expect(batches, hasLength(1));
    expect(batches.single.map((f) => f.name), ['a.pdf']);

    // Only missing files: no (empty) batch.
    await messenger.handlePlatformMessage(
      incomingFilesChannel,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('files', [
          {'path': '${dir.path}/gone.pdf', 'name': 'gone.pdf'},
        ]),
      ),
      (_) {},
    );
    await pumpEventQueue();
    expect(batches, hasLength(1));
  });
}
