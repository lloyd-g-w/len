import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/element_repository.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/domain/text/text_data.dart';
import 'package:len/features/editor/tools/text/rich_text_controller.dart';
import 'package:len/features/editor/tools/text_box_editor.dart';
import 'package:len/ink/elements/text_edit_session.dart';
import 'package:len/ink/undo_history.dart';
import 'package:len/ink/surface_model.dart';
import 'package:len/ink/tool_settings.dart';
import 'package:len/ink/viewport.dart';
import 'package:len/ui/app_theme.dart';

import 'data_test.dart' show FakeClock;
import 'elements_test.dart' show textBox;

void main() {
  testWidgets('a box changed elsewhere before any typing shows the change in the field', (
    tester,
  ) async {
    final db = AppDatabase.inMemory();
    addTearDown(db.close);
    final clock = FakeClock();
    final model = SurfaceModel(
      surfaceId: 's',
      repository: StrokeRepository(db, deviceId: 'd', clock: clock),
      elementRepository: ElementRepository(db, deviceId: 'd', clock: clock),
      clock: clock,
    );
    addTearDown(model.dispose);
    final session = TextEditSession(model: model, clock: clock);
    addTearDown(session.dispose);
    final box = textBox('t', const Offset(40, 40), text: 'old');
    model.commit(InkEdit(addedElements: [box]));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: TextBoxEditor(
            session: session,
            viewport: ViewportController()..setSize(const Size(800, 600)),
            tools: ToolSettings(stylusOnly: false),
          ),
        ),
      ),
    );
    session.edit(model.elementById('t')!);
    await tester.pump();

    // Another device (or the other pane) changes the box.
    final changed = box.copyWith(data: const TextData(text: 'new').toJson());
    model.commit(InkEdit(removedElements: [box], addedElements: [changed]));
    await tester.pump();

    final field = tester.widget<TextField>(find.byKey(const ValueKey('text-box-field')));
    expect((field.controller! as RichTextController).data.text, 'new');
    session.end();
    expect(TextData.fromJson(model.elementById('t')!.data).text, 'new');
  });
}
