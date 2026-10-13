import 'dart:typed_data';

import 'dart:ui';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/archive/len_archives.dart';
import 'package:len/data/blob_backend.dart';
import 'package:len/domain/image_data.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/surface_element.dart';
import 'package:len/platform/chunked_output.dart';

/// Browsers write backups in chunks rather than whole in memory (UX_AUDIT
/// R8-17).
void main() {
  test('a Len file written in chunks reads back whole', () async {
    final s = AppServices.create(AppDatabase.inMemory(), blobBackend: MemoryBlobBackend());
    addTearDown(s.dispose);
    final n = s.notebooks.create(
      title: 'Big',
      kind: NotebookKind.paged,
      paper: PaperStyle.blank,
      coverColor: 0,
    );
    final page = s.pages.pagesOf(n.id).single;
    for (var i = 0; i < 3; i++) {
      final sha = await s.blobs.putBytes(Uint8List(300 * 1024)..[0] = i, mime: 'image/png');
      s.elements.save([
        SurfaceElement(
          id: 'img$i',
          surfaceId: page.id,
          type: 'image',
          rect: const Rect.fromLTWH(0, 0, 10, 10),
          rotation: 0,
          z: -1,
          createdAt: 1,
          data: ImageData(blob: sha, width: 10, height: 10).toJson(),
        ),
      ]);
    }
    final chunks = <Uint8List>[];
    final out = ChunkedOutput(chunks.add, chunkSize: 64 * 1024);
    var drained = 0;
    await s.lenFiles.write(
      LenScope.notebook(n.id),
      out,
      drain: () async {
        drained++;
      },
    );
    out.flush();
    expect(chunks.length, greaterThan(10));
    expect(chunks.every((c) => c.length < 400 * 1024), isTrue); // Never all of it at once.
    expect(drained, greaterThan(3)); // Between pages of records and after each blob.
    final whole = BytesBuilder();
    chunks.forEach(whole.add);
    expect(whole.length, out.length);

    final target = AppServices.create(AppDatabase.inMemory(), blobBackend: MemoryBlobBackend());
    addTearDown(target.dispose);
    final result = await target.lenFiles.import(
      await target.lenFiles.open(InputMemoryStream(whole.takeBytes())),
    );
    expect(result.complete, isTrue);
    expect(target.notebooks.get(result.notebooks.single)!.title, 'Big');
    expect(target.database.db.select('SELECT 1 FROM blobs'), hasLength(3));
  });
}
