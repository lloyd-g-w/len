import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/features/settings/storage_settings.dart';
import 'package:len/platform/browser_storage_api.dart';
import 'package:len/ui/app_theme.dart';

class _FakeStorage implements BrowserStorage {
  _FakeStorage({required this.grant});

  final bool grant;
  bool persisted = false;
  int requests = 0;

  @override
  Future<bool> isPersisted() async => persisted;

  @override
  Future<bool> requestPersistence() async {
    requests++;
    persisted = grant;
    return grant;
  }

  @override
  Future<StorageUsage?> usage() async => (usage: 5 * 1024 * 1024, quota: 2 * 1024 * 1024 * 1024);
}

Future<void> _pump(WidgetTester tester, BrowserStorage storage) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: SingleChildScrollView(child: StorageSettings(storage: storage)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows usage and turns persistent storage on', (tester) async {
    final storage = _FakeStorage(grant: true);
    await _pump(tester, storage);
    expect(find.textContaining('5 MB of 2 GB'), findsOneWidget);
    expect(find.textContaining('Off:'), findsOneWidget);

    await tester.tap(find.text('Turn on'));
    await tester.pumpAndSettle();
    expect(storage.requests, 1);
    expect(find.textContaining('On:'), findsOneWidget);
    expect(find.text('Turn on'), findsNothing);
  });

  testWidgets('explains a refusal', (tester) async {
    final storage = _FakeStorage(grant: false);
    await _pump(tester, storage);
    await tester.tap(find.text('Turn on'));
    await tester.pumpAndSettle();
    expect(find.textContaining('The browser declined'), findsOneWidget);
    expect(find.text('Turn on'), findsOneWidget);
  });
}
