import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/domain/chunk_grid.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/ink/input/live_ink.dart';
import 'package:len/ink/selection/ink_clipboard.dart';
import 'package:len/ink/surface_model.dart';
import 'package:len/ink/tool_settings.dart';
import 'package:len/ink/tools/content_tools.dart';
import 'package:len/ink/viewport.dart';

Stroke _dot(String id, double x) => Stroke(
  id: id,
  surfaceId: 's',
  tool: InkTool.ballpoint,
  color: 0xFF000000,
  width: 4,
  points: [StrokePoint(x, 100, 0.5), StrokePoint(x + 50, 120, 0.5)],
  createdAt: 1,
);

void main() {
  test('select all loads its area for the moment only, not for the session', () {
    final db = AppDatabase.inMemory();
    addTearDown(db.close);
    StrokeRepository(
      db,
      deviceId: 'd',
    ).save([_dot('here', 100), _dot('there', 20000), _dot('later', 40000)]);
    final model = SurfaceModel(
      surfaceId: 's',
      repository: StrokeRepository(db, deviceId: 'd'),
      maxLoadedChunks: 2, // Chunks with content.
    );
    addTearDown(model.dispose);
    final content = ContentTools(
      model: model,
      viewport: ViewportController()..setSize(const Size(800, 600)),
      tools: ToolSettings(stylusOnly: true),
      live: LiveInk(),
      clipboard: InkClipboard(),
    );
    addTearDown(content.dispose);
    const screen = 'screen';
    model.ensureLoaded(const Rect.fromLTWH(0, 0, 800, 600), view: screen);

    content.selectAllIn(const Rect.fromLTWH(19800, 0, 800, 600));
    expect(content.selection.strokes.map((s) => s.id), ['there']);
    content.selection.clear();

    // The screen moves on: memory fills up, and what select all loaded is
    // far from every view.
    model.ensureLoaded(const Rect.fromLTWH(39800, 0, 800, 600), view: screen);
    expect(model.strokeById('later'), isNotNull);
    expect(model.strokeById('there'), isNull);
    expect(model.isComplete(ChunkGrid.keyAt(20000, 100)), isFalse);
  });
}
