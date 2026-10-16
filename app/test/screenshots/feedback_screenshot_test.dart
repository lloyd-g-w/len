@Tags(['screenshots'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/blob_backend.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/features/editor/editor_screen.dart';
import 'package:len/features/library/library_screen.dart';
import 'package:len/features/settings/settings_screen.dart';
import 'package:len/sync/sync_api.dart';
import 'package:len/ui/app_theme.dart';
import 'package:len/ui/startup_error.dart';

import '../support/fake_server.dart';
import 'screenshot_harness.dart';

/// When things go wrong: the startup error screen, the library warning
/// that files won't be kept, and Settings → Sync connected and failing.
void main() {
  setUpAll(loadRealFonts);

  const phone = ('phone', Size(390, 844), 2.0);
  const desktop = ('desktop', Size(1440, 900), 1.0);
  const modes = [ThemeMode.light, ThemeMode.dark];

  for (final (name, size, dpr) in [phone, desktop]) {
    for (final mode in modes) {
      testWidgets('startup error $name ${mode.name}', (tester) async {
        setWindow(tester, size, dpr: dpr);
        final s = AppServices.create(AppDatabase.inMemory());
        addTearDown(s.dispose);
        await pumpApp(
          tester,
          s,
          StartupErrorScreen(
            error: StateError('database is locked'),
            dataFolder: '/home/me/.local/share/dev.len.len',
            onRetry: () async {},
          ),
          mode: mode,
        );
        expect(tester.takeException(), isNull);
        await shoot(tester, 'f_startup_error_${name}_${mode.name}');
      });

      testWidgets('files not kept $name ${mode.name}', (tester) async {
        setWindow(tester, size, dpr: dpr);
        final s = AppServices.create(AppDatabase.inMemory(), blobBackend: VolatileBlobBackend());
        addTearDown(s.dispose);
        await pumpApp(tester, s, const LibraryScreen(), mode: mode);
        expect(tester.takeException(), isNull);
        await shoot(tester, 'f_files_not_kept_${name}_${mode.name}');
      });

      testWidgets('sync rejected token $name ${mode.name}', (tester) async {
        setWindow(tester, size, dpr: dpr);
        final server = FakeServer();
        final s = AppServices.create(
          AppDatabase.inMemory(),
          syncApiFactory: (url, token) =>
              SyncApi(baseUrl: url, token: token, client: server.client),
        );
        addTearDown(s.dispose);
        s.sync.configure(url: 'https://len.example.com', token: 'wrong');
        await tester.runAsync(s.sync.syncNow);
        await pumpApp(tester, s, const SettingsScreen(showSync: true), mode: mode);
        expect(tester.takeException(), isNull);
        await shoot(tester, 'f_sync_rejected_${name}_${mode.name}');
      });

      // A failing sync marked in the library header (phones) and the
      // editor's bar (UX_AUDIT R7-14).
      testWidgets('sync failing marks $name ${mode.name}', (tester) async {
        setWindow(tester, size, dpr: dpr);
        final server = FakeServer();
        final s = AppServices.create(
          AppDatabase.inMemory(),
          syncApiFactory: (url, token) =>
              SyncApi(baseUrl: url, token: token, client: server.client),
        );
        addTearDown(s.dispose);
        final nb = s.notebooks.create(
          title: 'Lecture notes',
          kind: NotebookKind.paged,
          paper: PaperStyle.wideRuled,
          coverColor: Palette.covers[0],
        );
        s.sync.configure(url: 'https://len.example.com', token: 'wrong');
        await tester.runAsync(s.sync.syncNow);
        await pumpApp(tester, s, const LibraryScreen(), mode: mode);
        await shoot(tester, 'f_sync_failing_library_${name}_${mode.name}');
        await pumpApp(tester, s, EditorScreen(notebook: nb), mode: mode);
        expect(tester.takeException(), isNull);
        await shoot(tester, 'f_sync_failing_editor_${name}_${mode.name}');
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
