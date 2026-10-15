import 'package:cross_file/cross_file.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter_test/flutter_test.dart';

import 'images_ui_test.dart' show openImageCanvas;

/// A PDF dropped on an open notebook goes the way of Open with (UX_AUDIT
/// R18-4): the library's handler, which asks where it goes.
void main() {
  testWidgets('a dropped PDF is handed on; images stay with the editor', (tester) async {
    final (services, _) = await openImageCanvas(tester);
    final handed = <List<XFile>>[];
    services.incomingFiles.handler = handed.add;
    final drop = tester.widget<DropTarget>(find.byType(DropTarget));
    drop.onDragDone!(
      DropDoneDetails(
        files: [DropItemFile('/tmp/Lecture 5.pdf', name: 'Lecture 5.pdf')],
        localPosition: const Offset(100, 100),
        globalPosition: const Offset(100, 100),
      ),
    );
    await tester.pump();
    expect(handed.single.single.name, 'Lecture 5.pdf');
  });
}
