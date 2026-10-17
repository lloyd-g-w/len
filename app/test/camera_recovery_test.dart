import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/notebook_page.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/surface_element.dart';
import 'package:len/features/camera/camera_purpose.dart';
import 'package:len/features/documents/scan/scan_screen.dart';
import 'package:len/features/editor/editor_screen.dart';
import 'package:len/features/library/launch_routes.dart';
import 'package:len/ui/app_theme.dart';

import 'content_tools_ui_test.dart' show liveElements;
import 'import_flow_ui_test.dart' show png;
import 'scan_flow_test.dart' show photoFile, scan;
import 'support/fake_camera.dart';
import 'support/real_async.dart';

/// Starts the app on [services] (as `pumpLibrary`, without settling: a
/// scan screen loading its photo animates until it has).
Future<AppServices> pumpLibrary(WidgetTester tester, {required AppServices services}) async {
  tester.view
    ..physicalSize = const Size(1280, 800)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(services.dispose);
  await tester.pumpWidget(
    AppScope(
      services: services,
      child: MaterialApp(
        theme: AppTheme.light(),
        onGenerateInitialRoutes: (_) => launchRoutes(services),
        onGenerateRoute: namedRoute,
      ),
    ),
  );
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return services;
}

/// Services whose camera hands back [lost], as Android does when Len
/// starts again after being killed while the camera was in front; the
/// camera had been opened for [purpose].
AppServices relaunched(FakeCameraCapture capture) =>
    AppServices.create(AppDatabase.inMemory(), camera: capture);

Notebook lecture(AppServices services, {int pages = 2}) {
  final notebook = services.notebooks.create(
    title: 'Lecture',
    kind: NotebookKind.paged,
    paper: PaperStyle.blank,
    coverColor: 0xFF3B5BDB,
  );
  for (var i = 1; i < pages; i++) {
    services.pages.addPage(notebook.id, paper: notebook.paper);
  }
  return notebook;
}

/// The editor was shown when Len went (it reopens with [notebook]).
void leftInEditor(AppServices services, Notebook notebook) =>
    services.settings.workspace = jsonEncode({
      'tabs': [notebook.id],
      'active': notebook.id,
    });

List<SurfaceElement> images(AppServices services, String surface) =>
    liveElements(services, surface).where((e) => e.knownType == ElementType.image).toList();

void main() {
  testWidgets('a scan for a new notebook carries on with the photo', (tester) async {
    final capture = FakeCameraCapture(lost: photoFile('lost.jpg'));
    final services = relaunched(capture);
    services.settings.cameraPurpose = const ScanNewNotebook().encode();
    await pumpLibrary(tester, services: services);
    final s = scan(tester);
    await s.untilPages(1);
    expect(find.text('Recovered the photo you took'), findsOneWidget);
    expect(services.settings.cameraPurpose, isNull);

    await s.tap(find.text('Create notebook'));
    await pumpUntil(tester, () => find.byType(EditorScreen).evaluate().isNotEmpty);
    await tester.pumpAndSettle();
    final notebook = services.notebooks.list().single;
    final pages = services.pages.pagesOf(notebook.id);
    expect(pages.single.background?.kind, PageBackgroundKind.image);
    expect(capture.retrieved, 1);
  });

  testWidgets('a scan into a notebook reopens it and inserts after the page it was for', (
    tester,
  ) async {
    final services = relaunched(FakeCameraCapture(lost: photoFile('lost.jpg')));
    final notebook = lecture(services, pages: 3);
    final [first, _, _] = services.pages.pagesOf(notebook.id);
    services.settings.cameraPurpose = ScanIntoNotebook(notebook.id, afterPageId: first.id).encode();
    await pumpLibrary(tester, services: services);
    final s = scan(tester);
    await s.untilPages(1);
    expect(find.byType(EditorScreen, skipOffstage: false), findsOneWidget);
    expect(find.text('Insert'), findsOneWidget);

    await s.tap(find.text('Insert'));
    await pumpUntil(tester, () => services.pages.pagesOf(notebook.id).length == 4);
    await tester.pumpAndSettle();
    final pages = services.pages.pagesOf(notebook.id);
    expect(pages[1].background?.kind, PageBackgroundKind.image);
    expect(find.byType(ScanScreen), findsNothing);
    expect(find.byType(EditorScreen), findsOneWidget);
  });

  testWidgets('a scan into a notebook deleted meanwhile becomes a new notebook', (tester) async {
    final services = relaunched(FakeCameraCapture(lost: photoFile('lost.jpg')));
    final notebook = lecture(services);
    services.settings.cameraPurpose = ScanIntoNotebook(notebook.id).encode();
    services.notebooks.delete(notebook.id);
    await pumpLibrary(tester, services: services);
    await scan(tester).untilPages(1);
    expect(find.text('Create notebook'), findsOneWidget);
    expect(find.byType(EditorScreen, skipOffstage: false), findsNothing);
  });

  testWidgets('a photo goes on the page and spot it was taken for, in the reopened editor', (
    tester,
  ) async {
    final services = relaunched(FakeCameraCapture(lost: png('lost.png')));
    final notebook = lecture(services);
    final [_, second] = services.pages.pagesOf(notebook.id);
    leftInEditor(services, notebook);
    const at = Offset(220, 320);
    services.settings.cameraPurpose = PhotoOnSurface(
      notebook.id,
      surfaceId: second.id,
      at: at,
    ).encode();
    await pumpLibrary(tester, services: services);
    await pumpUntil(tester, () => images(services, second.id).isNotEmpty);
    await tester.pumpAndSettle();
    expect(find.byType(EditorScreen), findsOneWidget, reason: 'one editor, not two');
    final image = images(services, second.id).single;
    expect(image.rect.center.dx, closeTo(at.dx, 1));
    expect(image.rect.center.dy, closeTo(at.dy, 1));
    expect(find.text('Recovered the photo you took'), findsOneWidget);
  });

  testWidgets('a photo for a page deleted meanwhile goes on the page shown', (tester) async {
    final services = relaunched(FakeCameraCapture(lost: png('lost.png')));
    final notebook = lecture(services);
    final [first, second] = services.pages.pagesOf(notebook.id);
    services.notebooks.deletePage(second.id);
    services.settings.cameraPurpose = PhotoOnSurface(
      notebook.id,
      surfaceId: second.id,
      at: const Offset(220, 320),
    ).encode();
    await pumpLibrary(tester, services: services);
    await pumpUntil(tester, () => images(services, first.id).isNotEmpty);
    await tester.pumpAndSettle();
    expect(find.byType(EditorScreen), findsOneWidget);
  });

  testWidgets('a photo for a canvas lands where the view was centred', (tester) async {
    final services = relaunched(FakeCameraCapture(lost: png('lost.png')));
    final board = services.notebooks.create(
      title: 'Board',
      kind: NotebookKind.canvas,
      paper: PaperStyle.blank,
      coverColor: 0xFF3B5BDB,
    );
    const at = Offset(-40, 60);
    services.settings.cameraPurpose = PhotoOnSurface(
      board.id,
      surfaceId: board.id,
      at: at,
    ).encode();
    await pumpLibrary(tester, services: services);
    await pumpUntil(tester, () => images(services, board.id).isNotEmpty);
    await tester.pumpAndSettle();
    final image = images(services, board.id).single;
    expect(image.rect.center.dx, closeTo(at.dx, 1));
    expect(image.rect.center.dy, closeTo(at.dy, 1));
  });

  testWidgets('a photo whose notebook is gone becomes a new canvas', (tester) async {
    final services = relaunched(FakeCameraCapture(lost: png('lost.png')));
    services.settings.cameraPurpose = const PhotoOnSurface(
      'gone',
      surfaceId: 'gone',
      at: Offset.zero,
    ).encode();
    await pumpLibrary(tester, services: services);
    await pumpUntil(
      tester,
      () => services.notebooks.list().any((n) => images(services, n.id).isNotEmpty),
    );
    await tester.pumpAndSettle();
    expect(services.notebooks.list().single.kind, NotebookKind.canvas);
  });

  testWidgets('nothing came back: the library starts as usual', (tester) async {
    final capture = FakeCameraCapture();
    final services = relaunched(capture);
    services.settings.cameraPurpose = const ScanNewNotebook().encode();
    await pumpLibrary(tester, services: services);
    expect(capture.retrieved, 1);
    expect(find.byType(ScanScreen), findsNothing);
    expect(find.text('Recovered the photo you took'), findsNothing);
    expect(services.settings.cameraPurpose, isNull);
  });

  testWidgets('Insert → Take photo and the scan camera keep what the photo is for', (tester) async {
    final capture = FakeCameraCapture();
    final services = relaunched(capture);
    final notebook = lecture(services);
    final [first, _] = services.pages.pagesOf(notebook.id);
    leftInEditor(services, notebook);
    await pumpLibrary(tester, services: services);
    expect(find.byType(EditorScreen), findsOneWidget);

    await tester.tap(find.byTooltip('Insert'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Take photo'));
    await tester.pump();
    expect(capture.open, isTrue);
    final photo = CameraPurpose.decode(services.settings.cameraPurpose!)! as PhotoOnSurface;
    expect(photo.notebookId, notebook.id);
    expect(photo.surfaceId, first.id);
    // Back with a photo: inserted as before, nothing kept.
    capture.answer(png('shot.png'));
    await pumpUntil(tester, () => images(services, first.id).isNotEmpty);
    await tester.pumpAndSettle();
    expect(services.settings.cameraPurpose, isNull);

    await tester.tap(find.byTooltip('Insert'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan document…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Take photo'));
    await tester.pump();
    expect(
      CameraPurpose.decode(services.settings.cameraPurpose!),
      ScanIntoNotebook(notebook.id, afterPageId: first.id),
    );
    capture.answer(null);
    await tester.pumpAndSettle();
    expect(services.settings.cameraPurpose, isNull);
  });
}
