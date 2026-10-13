import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/blob_backend.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/features/editor/editor_screen.dart';
import 'package:len/ui/app_theme.dart';

import 'content_tools_ui_test.dart' show liveElements;
import 'images_test.dart' show pngOf;
import 'images_ui_test.dart' show ctrl, mockClipboardImage, settleReal;

/// Blob storage that is full.
class _FullBlobs extends MemoryBlobBackend {
  @override
  Future<void> write(String sha, Stream<List<int>> data) async =>
      throw StateError('QuotaExceededError');
}

/// Paste and image insert say what happened (UX_AUDIT round 4, P2-9, P2-10).
void main() {
  Future<(AppServices, Notebook)> open(WidgetTester tester, {BlobBackend? blobs}) async {
    tester.view
      ..physicalSize = const Size(1280, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final services = AppServices.create(AppDatabase.inMemory(), blobBackend: blobs);
    addTearDown(services.dispose);
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    final notebook = services.notebooks.create(
      title: 'Board',
      kind: NotebookKind.canvas,
      paper: PaperStyle.blank,
      coverColor: 0xFF3B5BDB,
    );
    await tester.pumpWidget(
      AppScope(
        services: services,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: EditorScreen(notebook: notebook),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (services, notebook);
  }

  testWidgets('Ctrl+V with nothing to paste says so', (tester) async {
    await open(tester);
    await ctrl(tester, LogicalKeyboardKey.keyV);
    await tester.pumpAndSettle();
    expect(find.text('Nothing to paste'), findsOneWidget);
  });

  testWidgets('an image that cannot be stored is reported, not thrown', (tester) async {
    final (services, nb) = await open(tester, blobs: _FullBlobs());
    mockClipboardImage(pngOf(64, 32));
    await ctrl(tester, LogicalKeyboardKey.keyV);
    await settleReal(tester, () => find.text('Couldn’t add the image').evaluate().isNotEmpty);
    expect(liveElements(services, nb.id), isEmpty);
    expect(tester.takeException(), isNull);
  });
}
