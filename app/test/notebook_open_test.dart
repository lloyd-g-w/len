import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/features/editor/editor_screen.dart';
import 'package:len/features/editor/tabs/editor_workspace.dart';
import 'package:len/features/editor/tabs/notebook_open_route.dart';
import 'package:len/features/library/library_screen.dart';
import 'package:len/features/library/notebook_card.dart';
import 'package:len/features/library/notebook_cover.dart';
import 'package:len/ui/app_theme.dart';

import 'library_ui_test.dart' show addNotebook;
import 'ui_library_test.dart' show pumpLibrary;

Finder coverOf(String title) => find.descendant(
  of: find.ancestor(of: find.text(title), matching: find.byType(NotebookCard)),
  matching: find.byType(NotebookCover),
);

NotebookOpenRoute<dynamic> editorRoute(WidgetTester tester) =>
    ModalRoute.of(tester.element(find.byType(EditorWorkspace, skipOffstage: false)))!
        as NotebookOpenRoute<dynamic>;

void main() {
  testWidgets('a card opens the editor out of its cover; back closes into it', (tester) async {
    final services = AppServices.create(AppDatabase.inMemory());
    addNotebook(services, 'Physics');
    addNotebook(services, 'Chemistry');
    await pumpLibrary(tester, services: services);
    final cover = tester.getRect(coverOf('Physics'));

    await tester.tap(coverOf('Physics'));
    await tester.pump();
    final route = editorRoute(tester);
    expect(route.settings.name, EditorWorkspace.routeName);
    expect(route.origin!.rect, cover);
    expect(route.origin!.locate!(), cover);
    expect(route.reduceMotion, isFalse);

    // Mid-flight: the cover flies (a second cover) over the library.
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(NotebookCover), findsNWidgets(3));
    expect(find.byType(LibraryScreen), findsOneWidget);
    await tester.pumpAndSettle();
    expect(route.animation!.isCompleted, isTrue);
    expect(find.byType(EditorScreen), findsOneWidget);
    expect(find.byType(LibraryScreen), findsNothing);
    expect(services.openNotebooks.active?.title, 'Physics');

    await tester.tap(find.byTooltip('Back'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(LibraryScreen), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byType(EditorWorkspace), findsNothing);
    expect(tester.getRect(coverOf('Physics')).size, cover.size);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dark mode flies on the dark backdrop, not the light paper (no pale flash)', (
    tester,
  ) async {
    expect(await flightFills(tester, AppTheme.light()), contains(Colors.white));
    final dark = await flightFills(tester, AppTheme.dark());
    expect(dark, contains(Surfaces.canvasBackdrop(Brightness.dark)));
    expect(dark, isNot(contains(Colors.white)));
  });

  testWidgets('without a cover (new notebook) and with reduced motion it fades', (tester) async {
    final services = AppServices.create(AppDatabase.inMemory());
    final physics = addNotebook(services, 'Physics');
    await pumpLibrary(tester, services: services);

    final context = tester.element(find.byType(LibraryScreen));
    unawaited(openNotebook(context, physics));
    await tester.pump();
    expect(editorRoute(tester).origin, isNull);
    expect(editorRoute(tester).transitionDuration, Motion.medium);
    await tester.pumpAndSettle();
    expect(find.byType(EditorScreen), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
      disableAnimations: true,
    );
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pump();
    await tester.tap(coverOf('Physics'));
    await tester.pump();
    final route = editorRoute(tester);
    expect(route.reduceMotion, isTrue);
    expect(route.transitionDuration, Motion.fast);
    await tester.pumpAndSettle();
    expect(find.byType(EditorScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

/// The colours the flight fills behind the editor mid-open, in [theme].
Future<Set<Color>> flightFills(WidgetTester tester, ThemeData theme) async {
  final navigator = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    MaterialApp(navigatorKey: navigator, theme: theme, home: const SizedBox.expand()),
  );
  unawaited(
    navigator.currentState!.push(
      NotebookOpenRoute<void>(
        builder: (_) => const SizedBox.expand(key: Key('editor')),
        origin: const NotebookOpenOrigin(
          rect: Rect.fromLTWH(40, 40, 120, 160),
          cover: SizedBox.expand(),
          paper: Colors.white,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 180));
  final editor = find.byKey(const Key('editor'));
  final fills = tester
      .widgetList<ColoredBox>(find.ancestor(of: editor, matching: find.byType(ColoredBox)))
      .map((box) => box.color)
      .toSet();
  await tester.pumpAndSettle();
  return fills;
}
