@Tags(['screenshots'])
library;

import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/raster_store.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/notebook_page.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/recording.dart';
import 'package:len/features/audio/ui/recordings_sheet.dart';
import 'package:len/features/settings/settings_screen.dart';
import 'package:len/features/settings/settings_section.dart';
import 'package:len/sync/sync_api.dart';

import '../support/fake_server.dart';
import 'screenshot_harness.dart';

/// Settings → Storage with a year of lectures: the space by kind, the
/// largest notebooks, "Free up" (sync on) and cached previews; the
/// confirmation, and a notebook opened at its recordings.
void main() {
  setUpAll(loadRealFonts);

  const phone = ('phone', Size(390, 844), 2.0);
  const desktop = ('desktop', Size(1440, 900), 1.0);

  /// Services with notebooks whose files (recorded sizes; no bytes stored)
  /// the server holds.
  AppServices services() {
    final server = FakeServer();
    final rasters = MemoryRasterStore();
    final s = AppServices.create(
      AppDatabase.inMemory(),
      rasterStore: rasters,
      syncApiFactory: (url, t) => SyncApi(baseUrl: url, token: t, client: server.client),
    );
    addTearDown(s.dispose);
    s.sync.configure(url: 'https://len.example.org', token: FakeServer.token);
    var n = 0;
    String file(int bytes, String mime) {
      final sha = sha256.convert([n++]).toString();
      s.database.execute(
        'INSERT INTO blobs (sha256, size, mime, created_at, uploaded) VALUES (?, ?, ?, 0, 1)',
        [sha, bytes, mime],
      );
      return sha;
    }

    Notebook notebook(String title) => s.notebooks.create(
      title: title,
      kind: NotebookKind.paged,
      paper: PaperStyle.blank,
      coverColor: 0xFF2F5D8A,
    );

    void lectures(String title, int mb) {
      final nb = notebook(title);
      s.recordings.save(
        notebookId: nb.id,
        parts: [RecordingPart(file(mb << 20, 'audio/aac'), 3600000)],
        mime: 'audio/aac',
        title: 'Lecture',
        segments: [RecordingSegment(0, 3600000)],
      );
    }

    void pdf(String title, int mb) {
      final nb = notebook(title);
      final sha = file(mb << 20, 'application/pdf');
      s.database.execute('INSERT INTO pdf_text_blobs (blob, pages, ok) VALUES (?, 1, 1)', [sha]);
      s.pages.insertPages(nb.id, [
        (
          size: const Size(595, 842),
          paper: Paper(PaperStyle.blank),
          color: PaperColor.white,
          background: PageBackground.pdf(blob: sha, pageIndex: 0),
        ),
      ]);
    }

    lectures('Electronics — Lecture 12', 412);
    lectures('Electronics — Lecture 11', 388);
    pdf('Signals and Systems (textbook)', 96);
    lectures('Thermodynamics', 230);
    pdf('Lab handbook', 18);
    notebook('Shopping list');
    rasters.write('chunk', Uint8List(24 << 20));
    // All synced: files only unsynced rows show are never freed.
    for (final table in ['pages', 'recordings']) {
      s.database.execute('UPDATE $table SET dirty = 0');
    }
    return s;
  }

  Finder storage() => find.byWidgetPredicate((w) => w is SettingsSection && w.title == 'Storage');

  for (final (name, size, dpr) in [phone, desktop]) {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('storage $name ${mode.name}', (tester) async {
        setWindow(tester, size, dpr: dpr);
        final s = services();
        await pumpApp(tester, s, const SettingsScreen(), mode: mode);
        await tester.ensureVisible(storage());
        await settle(tester);
        expect(find.text('Largest notebooks'), findsOneWidget);
        expect(find.textContaining('Free up'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await shoot(tester, 's_settings_storage_${name}_${mode.name}');
        if (mode == ThemeMode.dark) return;
        final freeUp = find.widgetWithText(OutlinedButton, 'Free up 1.1 GB…');
        await Scrollable.ensureVisible(tester.element(freeUp), alignment: 0.5);
        await settle(tester);
        await tester.tap(freeUp);
        await settle(tester);
        expect(find.textContaining('can’t be undone'), findsOneWidget);
        await shoot(tester, 's_dialog_storage_free_up_$name');
      });
    }
  }

  for (final (name, size, dpr) in [phone, desktop]) {
    testWidgets('storage opens a notebook at its recordings $name', (tester) async {
      setWindow(tester, size, dpr: dpr);
      await pumpApp(tester, services(), const SettingsScreen());
      final recordings = find.widgetWithText(TextButton, 'Recordings').first;
      await Scrollable.ensureVisible(tester.element(recordings), alignment: 0.5);
      await settle(tester);
      await tester.tap(recordings);
      await settle(tester);
      expect(find.byType(RecordingsList), findsOneWidget);
      expect(tester.takeException(), isNull);
      await shoot(tester, 's_storage_recordings_$name');
    });
  }
}
