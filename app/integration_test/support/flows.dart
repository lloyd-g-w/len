import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:len/app_services.dart';
import 'package:len/features/editor/editor_screen.dart';
import 'package:len/features/library/new_notebook_sheet.dart';
import 'package:len/features/library/notebook_card.dart';
import 'package:len/sync/sync_controller.dart';

import 'e2e.dart';

/// Creates a notebook (or a canvas) through the New sheet; ends in the editor.
Future<void> createNotebook(WidgetTester tester, String title, {bool canvas = false}) async {
  final empty = find.text('New notebook');
  final tile = find.byKey(const ValueKey('new-notebook-tile'));
  await tester.tap(empty.evaluate().isNotEmpty ? empty.first : tile.first);
  await pumpUntil(tester, find.byType(NewNotebookSheet));
  await settle(tester);
  if (canvas) await tapText(tester, 'Canvas');
  await tester.enterText(
    find.descendant(of: find.byType(NewNotebookSheet), matching: find.byType(TextField)).first,
    title,
  );
  await tapText(tester, 'Create');
  await pumpUntil(tester, find.byType(EditorScreen));
  await settle(tester);
}

/// More options → Page → Add page after.
Future<void> addPageAfter(WidgetTester tester) async {
  await tapTooltip(tester, 'More options');
  await tapText(tester, 'Page');
  await tapText(tester, 'Add page after', last: true);
}

/// Opens the "More" menu of the library card titled [title].
Future<void> notebookMenu(WidgetTester tester, String title) async {
  final card = find.ancestor(of: find.text(title), matching: find.byType(NotebookCard));
  await pumpUntil(tester, card);
  await tester.tap(find.descendant(of: card.first, matching: find.byTooltip('More')));
  await settle(tester);
}

/// Opens Settings from the library and connects to the e2e server, then
/// waits until a sync completed.
Future<void> connectSync(WidgetTester tester, AppServices s) async {
  await tapText(tester, 'Settings');
  await pumpUntil(tester, find.widgetWithText(TextField, 'Server URL'));
  await tester.ensureVisible(find.widgetWithText(TextField, 'Server URL'));
  await tester.enterText(find.widgetWithText(TextField, 'Server URL'), E2E.server);
  await tester.enterText(find.widgetWithText(TextField, 'Access token'), E2E.token);
  final before = s.sync.lastSuccess;
  await tester.tap(find.widgetWithText(FilledButton, 'Connect & save').first);
  await waitForSync(tester, s, before);
  await tapTooltip(tester, 'Back');
}

/// Waits until a sync completed after [before] (fails on an error).
Future<void> waitForSync(WidgetTester tester, AppServices s, DateTime? before) async {
  await waitFor(tester, () {
    if (s.sync.state == SyncState.error) fail('sync failed: ${s.sync.lastError}');
    final last = s.sync.lastSuccess;
    return s.sync.state == SyncState.idle && last != null && last != before;
  }, reason: 'sync');
}

/// Syncs now and waits for it.
Future<void> syncNow(WidgetTester tester, AppServices s) async {
  final before = s.sync.lastSuccess;
  await s.sync.syncNow();
  await waitForSync(tester, s, before);
}

/// Whether the server has the blob [sha].
Future<bool> serverHasBlob(String sha) async {
  final res = await http.head(
    Uri.parse('${E2E.server}/v1/blobs/$sha'),
    headers: {'Authorization': 'Bearer ${E2E.token}'},
  );
  return res.statusCode == 200;
}

/// Every record on the server (`GET /v1/pull`), by collection.
Future<Map<String, List<Map<String, dynamic>>>> serverRecords() async {
  final out = <String, List<Map<String, dynamic>>>{};
  var since = 0;
  while (true) {
    final res = await http.get(
      Uri.parse('${E2E.server}/v1/pull?since=$since&limit=1000'),
      headers: {'Authorization': 'Bearer ${E2E.token}'},
    );
    expect(res.statusCode, 200, reason: res.body);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final records = (body['records'] as List).cast<Map<String, dynamic>>();
    for (final r in records) {
      (out[r['collection'] as String] ??= []).add(r);
    }
    since = body['nextSince'] as int;
    if (body['hasMore'] != true) return out;
  }
}
