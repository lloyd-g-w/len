import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/features/documents/scan/scan_import.dart';
import 'package:len/features/documents/scan/scan_session.dart';

import 'scan_flow_test.dart' show deskPhoto;

void main() {
  testWidgets('a cancelled scan keeps a scan a deleted page may still need', (tester) async {
    final s = AppServices.create(AppDatabase.inMemory());
    addTearDown(s.dispose);
    final nb = s.notebooks.create(
      title: 'Scans',
      kind: NotebookKind.paged,
      paper: PaperStyle.blank,
      coverColor: 0,
    );
    await tester.runAsync(() async {
      final photo = await ScanPhoto.load(deskPhoto());
      // Scanned, inserted, then undone: the page is deleted, its scan kept
      // (redo, or a deletion conflict, may bring it back).
      final first = ScanImporter(s);
      final specs = await first.render([ScanPageDraft(photo)], ScanFilter.colour);
      final page = first.insertPages(specs, notebookId: nb.id).single;
      final sha = page.background!.blob;
      s.notebooks.deletePage(page.id);
      // The same photo scanned the same way again, then cancelled.
      final again = ScanImporter(s);
      final repeat = await again.render([ScanPageDraft(photo)], ScanFilter.colour);
      expect(repeat.single.background, page.background);
      await again.discard();
      expect(await s.blobs.has(sha), isTrue);
    });
  });
}
