import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/write_back.dart';
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

/// A write-back store whose failure the test sets.
class _Store with ChangeNotifier implements WriteBackStore {
  @override
  bool pending = false;

  @override
  WriteFailure? failure;

  int flushes = 0;

  void set(WriteFailure? failure) {
    this.failure = failure;
    pending = failure != null;
    notifyListeners();
  }

  @override
  Future<bool> flush() async {
    flushes++;
    return failure == null;
  }

  @override
  Future<bool> close() async => true;
}

Future<void> _pump(WidgetTester tester, BrowserStorage storage, {StorageWrites? writes}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: StorageSettings(storage: storage, writes: writes),
        ),
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

  testWidgets('says while changes can\'t be saved, like the library', (tester) async {
    final store = _Store();
    await _pump(tester, _FakeStorage(grant: true), writes: StorageWrites()..add(store));
    expect(find.textContaining('aren\'t saved yet'), findsNothing);

    store.set(WriteFailure.full);
    await tester.pump();
    expect(find.text('Your latest changes aren\'t saved yet'), findsOneWidget);
    expect(find.textContaining('Browser storage is full'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    expect(store.flushes, 1);

    store.set(null);
    await tester.pumpAndSettle();
    expect(find.textContaining('aren\'t saved yet'), findsNothing);
  });
}
