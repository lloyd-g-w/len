import 'dart:async';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/archive/len_archives.dart';
import 'package:len/domain/paper.dart';
import 'package:len/features/backup/restore_dialogs.dart';
import 'package:len/features/documents/import/import_flow.dart';
import 'package:len/features/documents/import/import_router.dart';
import 'package:len/features/documents/progress_dialog.dart';
import 'package:len/features/documents/template_picker.dart';
import 'package:len/features/library/library_screen.dart';
import 'package:len/features/library/notebook_card.dart';

import 'screenshot_harness.dart';

/// Every library dialog and sheet on a phone (light, dark and 1.3× text),
/// and the import flows: "Open with" destination choice, progress and the
/// messages for files Len can't open.
void main() {
  setUpAll(loadRealFonts);

  const phone = ('phone', Size(390, 844), 2.0);
  const desktop = ('desktop', Size(1440, 900), 1.0);

  BuildContext ctx(WidgetTester tester) => tester.element(find.byType(LibraryScreen));

  Finder moreOf(String title) => find.descendant(
    of: find.ancestor(of: find.text(title), matching: find.byType(NotebookCard)),
    matching: find.byTooltip('More'),
  );

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.tap(finder, warnIfMissed: false);
    await settle(tester);
  }

  /// Closes the top dialog or sheet like the system back button.
  Future<void> back(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await settle(tester);
  }

  for (final (mode, scale, suffix) in [
    (ThemeMode.light, 1.0, 'light'),
    (ThemeMode.dark, 1.0, 'dark'),
    (ThemeMode.light, 1.3, 'light_large'),
  ]) {
    testWidgets('library dialogs phone $suffix', (tester) async {
      setWindow(tester, phone.$2, dpr: phone.$3);
      final services = seededServices();
      addTearDown(services.dispose);
      await pumpApp(tester, services, const LibraryScreen(), mode: mode, textScale: scale);
      final errors = <String>[];

      Future<void> capture(String shot, Future<void> Function() open) async {
        await open();
        // Collect, don't hide, layout errors: they are app bugs to report.
        final error = tester.takeException();
        if (error != null) errors.add('$shot: $error');
        await shoot(tester, 's_dialog_${shot}_phone_$suffix');
        await back(tester);
      }

      Future<void> notebookMenu(String item) async {
        await tester.ensureVisible(moreOf('Travel plans'));
        await settle(tester);
        await tap(tester, moreOf('Travel plans'));
        await tap(tester, find.text(item));
      }

      Future<void> folderMenu(String item) async {
        await revealSideways(tester, find.text('Work').last); // Phones: the folder strip.
        await tester.longPress(find.text('Work').last);
        await settle(tester);
        await tap(tester, find.text(item));
      }

      // Phones create folders from the drawer.
      await capture('new_folder', () async {
        await tap(tester, find.byTooltip('Menu'));
        await tap(tester, find.byTooltip('New folder'));
      });
      await back(tester); // Closes the drawer.
      await capture('edit_folder', () => folderMenu('Rename…'));
      // Deleting a folder asks nothing: its message offers Undo.
      await folderMenu('Delete folder');
      await shoot(tester, 's_snackbar_delete_folder_phone_$suffix');
      await tap(tester, find.text('Undo'));
      await capture('new_notebook', () => tap(tester, newButton()));
      await capture('template_picker', () async {
        unawaited(
          showTemplatePicker(
            ctx(tester),
            initial: const PageTemplate(paper: Paper(PaperStyle.collegeRuled)),
            mode: TemplatePickerMode.change,
          ),
        );
        await settle(tester);
      });

      // Last: these scroll the library.
      await capture('rename', () => notebookMenu('Rename…'));
      await capture('move', () => notebookMenu('Move to folder…'));
      await capture('cover', () => notebookMenu('Change cover…'));
      await openLibrarySection(tester, 'Trash');
      await capture('delete_forever', () async {
        await tester.ensureVisible(moreOf('Old drafts'));
        await settle(tester);
        await tap(tester, moreOf('Old drafts'));
        await tap(tester, find.text('Delete forever…'));
      });
      await capture('empty_trash', () => tap(tester, emptyTrashButton()));

      // Restoring a backup (UX_AUDIT R8-16, R8-14).
      final manifest = LenManifest(
        kind: LenArchiveKind.library,
        title: 'Library',
        createdAt: DateTime(2026, 10, 13, 14, 5).millisecondsSinceEpoch,
      );
      await capture('restore_confirm', () async {
        unawaited(
          confirmRestore(
            ctx(tester),
            manifest: manifest,
            notebooks: 42,
            present: 3,
            intoEmpty: false,
            syncing: true,
          ),
        );
        await settle(tester);
      });
      await capture('restore_gaps', () async {
        showImported(
          ctx(tester),
          LenImportResult(
            manifest: manifest,
            notebooks: const ['n'],
            folders: const ['f'],
            folder: 'f',
            skipped: 3,
            missingBlobs: 2,
            problems: const ['Damaged file ab12'],
          ),
          folderName: 'Backup 13 Oct 2026',
          undo: () {},
        );
        await settle(tester);
      });

      if (errors.isNotEmpty) {
        // ignore: avoid_print
        print('Layout errors at phone $suffix:\n${errors.join('\n')}');
      }
      expect(scale > 1 || errors.isEmpty, isTrue, reason: errors.join('\n'));
    });
  }

  for (final (name, size, dpr) in [phone, desktop]) {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      final m = mode.name;
      testWidgets('import flows $name $m', (tester) async {
        setWindow(tester, size, dpr: dpr);
        final services = seededServices();
        addTearDown(services.dispose);
        await pumpApp(tester, services, const LibraryScreen(), mode: mode);

        // "Open with" a PDF while a notebook is open: insert or new?
        unawaited(
          ImportFlow.askWhere(ctx(tester), [
            XFile('/storage/Download/Lecture 7 slides.pdf'),
          ], const ImportDestination(title: 'Physics — Mechanics', acceptsPdf: true)),
        );
        await settle(tester);
        expect(find.text('Add to this notebook'), findsOneWidget);
        await shoot(tester, 's_import_ask_pdf_${name}_$m');
        await back(tester);

        // Photos and a PDF shared to an open canvas.
        unawaited(
          ImportFlow.askWhere(ctx(tester), [
            XFile('/storage/DCIM/IMG_2041.jpg'),
            XFile('/storage/DCIM/IMG_2042.jpg'),
            XFile('/storage/Download/handout.pdf'),
          ], const ImportDestination(title: 'Whiteboard', acceptsPdf: false)),
        );
        await settle(tester);
        expect(find.text('Open 3 files'), findsOneWidget);
        await shoot(tester, 's_import_ask_canvas_${name}_$m');
        await back(tester);

        // Progress of an import: first a stage, then page by page.
        final done = Completer<void>();
        late TaskProgress task;
        unawaited(
          runWithSteps(
            ctx(tester),
            'Importing PDF',
            subject: 'Lecture 7 slides.pdf',
            cancellable: true, // As the real import.
            (progress) {
              task = progress..stageStarted('Creating pages…', note: '48 pages');
              return done.future;
            },
          ),
        );
        await settle(tester);
        await shoot(tester, 's_import_progress_stage_${name}_$m');
        task.step(17, 48, stage: 'Reading pages…');
        await settle(tester);
        await shoot(tester, 's_import_progress_pages_${name}_$m');
        done.complete();
        await settle(tester);

        // A file Len can't open, handed over by the system.
        services.incomingFiles.add([XFile('/storage/Download/Budget 2026.xlsx')]);
        await settle(tester);
        expect(find.textContaining('Couldn’t open'), findsOneWidget);
        await shoot(tester, 's_import_unsupported_${name}_$m');

        // A PDF that fails to import (the message importPdfFlow shows).
        showMessage(ctx(tester), 'Couldn’t open “scan.pdf”: it may be damaged, or not a PDF');
        await settle(tester);
        await shoot(tester, 's_import_failed_${name}_$m');
        expect(tester.takeException(), isNull);
      });
    }
  }
}
