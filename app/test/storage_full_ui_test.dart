import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/write_back.dart';
import 'package:len/features/storage/storage_attention.dart';
import 'package:len/platform/tab_handover.dart';
import 'package:len/ui/open_elsewhere.dart';

/// A write-back store whose state the test sets.
class _Store with ChangeNotifier implements WriteBackStore {
  @override
  bool pending = false;

  @override
  WriteFailure? failure;

  int flushes = 0;

  void set({required bool pending, WriteFailure? failure}) {
    this.pending = pending;
    this.failure = failure;
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

void main() {
  group('storage full (web)', () {
    Future<_Store> pumpApp(WidgetTester tester) async {
      final store = _Store();
      final services = AppServices.create(
        AppDatabase.inMemory(),
        writes: StorageWrites()..add(store),
      );
      addTearDown(services.dispose);
      await tester.pumpWidget(LenApp(services: services));
      await tester.pumpAndSettle();
      return store;
    }

    final message = StorageAttention.messageFor(WriteFailure.full);

    testWidgets('says so once, offers Try again, and says when saved', (tester) async {
      final store = await pumpApp(tester);
      store.set(pending: true, failure: WriteFailure.full);
      await tester.pump();
      expect(find.text(message), findsOneWidget);
      // The library keeps a notice while it lasts.
      expect(find.text('Your latest changes aren\'t saved yet'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 500)); // The snack bar is in.
      await tester.tap(find.widgetWithText(SnackBarAction, 'Try again'));
      await tester.pump();
      expect(store.flushes, 1);

      // Failing again doesn't repeat the message.
      await tester.pump(const Duration(seconds: 13));
      await tester.pumpAndSettle();
      store.set(pending: true, failure: WriteFailure.full);
      await tester.pump();
      expect(find.text(message), findsNothing);

      store.set(pending: false);
      await tester.pump();
      expect(find.text('Your changes are saved'), findsOneWidget);
      expect(find.text('Your latest changes aren\'t saved yet'), findsNothing);
    });

    testWidgets('nothing while writes just pend', (tester) async {
      final store = await pumpApp(tester);
      store.set(pending: true);
      await tester.pump();
      store.set(pending: false);
      await tester.pump();
      expect(find.byType(SnackBar), findsNothing);
    });
  });

  testWidgets('open in another tab: Use here, and what the other tab answered', (tester) async {
    final state = ValueNotifier(WaitState.waiting);
    var asked = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: OpenElsewhereScreen(state: state, onUseHere: () => asked++),
      ),
    );
    expect(find.text('Len is open in another tab'), findsOneWidget);
    await tester.tap(find.text('Use here'));
    expect(asked, 1);
    state.value = WaitState.asking;
    await tester.pump();
    expect(find.text('Moving Len to this tab…'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
    state.value = WaitState.refused;
    await tester.pump();
    expect(find.textContaining('storage is full'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    expect(asked, 2);
  });
}
