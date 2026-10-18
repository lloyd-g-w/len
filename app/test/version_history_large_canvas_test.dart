import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/features/history/version_history_sheet.dart';
import 'package:len/features/history/version_ink_images.dart';
import 'package:len/features/history/version_preview.dart';
import 'package:len/features/history/version_surface_view.dart';
import 'package:len/ui/app_theme.dart';

import 'support/real_async.dart';

/// [n] short strokes in rows on canvas [surface].
List<Stroke> _strokes(String surface, int n) => [
  for (var i = 0; i < n; i++)
    Stroke(
      id: 's$i',
      surfaceId: surface,
      tool: InkTool.ballpoint,
      color: 0xFF1F2937,
      width: 2,
      points: [
        StrokePoint(10.0 + (i % 50) * 20, 10.0 + (i ~/ 50) * 16, 0.5),
        StrokePoint(24.0 + (i % 50) * 20, 18.0 + (i ~/ 50) * 16, 0.5),
      ],
      createdAt: i,
    ),
];

List<VersionSurfaceViewState> _views() => [
  for (final e in find.byType(VersionSurfaceView).evaluate())
    (e as StatefulElement).state as VersionSurfaceViewState,
];

void main() {
  testWidgets('a large canvas\'s thumbnail shows its ink from an image', (tester) async {
    final s = AppServices.create(AppDatabase.inMemory());
    addTearDown(s.dispose);
    final nb = s.notebooks.create(
      title: 'Board',
      kind: NotebookKind.canvas,
      paper: PaperStyle.blank,
      coverColor: 0,
    );
    await tester.runAsync(() async {
      s.strokes.save(_strokes(nb.id, VersionInkImages.minStrokes + 100));
      await s.versions.record(nb.id);
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showVersionHistory(context, s, nb.id),
                child: const Text('History'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    await pumpUntil(
      tester,
      () => _views().length == 1 && _views().single.loaded,
      reason: 'the thumbnail',
    );
    expect(_views().single.showsInkImage, isTrue);
    // Its preview too, at its size, and the part zoomed into sharp.
    await tester.tap(find.byKey(ValueKey('version-${s.versions.of(nb.id).single.id}')));
    await tester.pumpAndSettle();
    final preview = find.descendant(
      of: find.byType(VersionPreview),
      matching: find.byType(VersionSurfaceView),
    );
    VersionSurfaceViewState view() => tester.state(preview);
    await pumpUntil(tester, () => view().loaded, reason: 'the preview');
    expect(view().showsInkImage, isTrue);
    expect(view().showsZoomedPart, isFalse);
    final zoom = tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
    zoom.transformationController!.value = Matrix4.diagonal3Values(4, 4, 1);
    await tester.pump();
    expect(view().loaded, isFalse, reason: 'its part comes when the zoom rests');
    await tester.pump(const Duration(milliseconds: 200));
    await pumpUntil(tester, () => view().loaded, reason: 'the part zoomed into');
    expect(view().showsZoomedPart, isTrue);
    zoom.transformationController!.value = Matrix4.identity();
    await tester.pump(const Duration(milliseconds: 200));
    await pumpUntil(tester, () => view().loaded, reason: 'zoomed out');
    expect(view().showsZoomedPart, isFalse);
    await tester.pageBack();
    await tester.pumpAndSettle();
    // Closing disposes the images with the history (VersionSheets).
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(VersionSurfaceView), findsNothing);
  });
}
