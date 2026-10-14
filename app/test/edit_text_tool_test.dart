import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/element_repository.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/ink/input/live_ink.dart';
import 'package:len/ink/selection/ink_clipboard.dart';
import 'package:len/ink/surface_model.dart';
import 'package:len/ink/tool_settings.dart';
import 'package:len/ink/tools/content_tools.dart';
import 'package:len/ink/undo_history.dart';
import 'package:len/ink/viewport.dart';

import 'data_test.dart' show FakeClock;
import 'elements_test.dart' show textBox;

void main() {
  late SurfaceModel model;
  late ToolSettings tools;
  late ContentTools content;
  final a = textBox('a', const Offset(10, 10));
  final b = textBox('b', const Offset(10, 300));

  setUp(() {
    final db = AppDatabase.inMemory();
    final clock = FakeClock();
    model = SurfaceModel(
      surfaceId: 's',
      repository: StrokeRepository(db, deviceId: 'd', clock: clock),
      elementRepository: ElementRepository(db, deviceId: 'd', clock: clock),
      clock: clock,
    )..commit(InkEdit(addedElements: [a, b]));
    tools = ToolSettings(stylusOnly: true)..tool = EditorTool.lasso;
    content = ContentTools(
      model: model,
      viewport: ViewportController()..setSize(const Size(800, 600)),
      tools: tools,
      live: LiveInk(),
      clipboard: InkClipboard(),
      clock: clock,
    );
    addTearDown(() {
      content.dispose();
      model.dispose();
      db.close();
    });
  });

  test('"Edit text" goes back to the lasso when the edit ends', () {
    content.selection.select(const [], [a]);
    content.editText(a);
    expect(tools.tool, EditorTool.text);
    expect(content.selection.isEmpty, isTrue);
    expect(content.text.current?.id, 'a');

    content.text.end();
    expect(tools.tool, EditorTool.lasso);
  });

  test('a box edited from the pen (side button lasso) gives the pen back', () {
    tools.tool = EditorTool.pen;
    content.editText(a);
    content.text.end();
    expect(tools.tool, EditorTool.pen);
  });

  test('moving on to another box keeps the text tool until editing ends', () {
    content.editText(a);
    content.text.edit(b); // A tap on another box with the text tool.
    expect(tools.tool, EditorTool.text);
    expect(content.text.current?.id, 'b');
    content.text.end();
    expect(tools.tool, EditorTool.lasso);
  });

  test('a tool picked during the edit stays', () {
    content.editText(a);
    tools.tool = EditorTool.highlighter;
    expect(content.text.isEditing, isFalse);
    expect(tools.tool, EditorTool.highlighter);
  });

  test('the text tool picked by the user stays after an edit', () {
    tools.tool = EditorTool.text;
    content.editText(a);
    content.text.end();
    expect(tools.tool, EditorTool.text);
  });
}
