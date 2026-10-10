import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs before every test file: plugins without a platform side in tests
/// answer like an empty system clipboard.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('pasteboard'),
    (call) async => call.method == 'files' ? const <Object>[] : null,
  );
  await testMain();
}
