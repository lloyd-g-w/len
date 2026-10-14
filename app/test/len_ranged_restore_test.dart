import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/archive/len_archives.dart';
import 'package:len/data/archive/ranged_input.dart';
import 'package:len/data/blob_backend.dart';
import 'package:len/data/surface_copier.dart';
import 'package:len/domain/image_data.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/surface_element.dart';

/// A backup picked in a browser is read in slices (`Blob.slice`): the zip
/// structure, then each entry as it is read, never the whole file.
void main() {
  test('a backup restores from slices, holding little of it at a time', () async {
    final dir = await Directory.systemTemp.createTemp('len-ranged');
    addTearDown(() => dir.delete(recursive: true));
    final source = AppServices.create(AppDatabase.inMemory(), blobBackend: MemoryBlobBackend());
    addTearDown(source.dispose);
    const blobSize = 3 << 20;
    for (var n = 0; n < 3; n++) {
      final notebook = source.notebooks.create(
        title: 'N$n',
        kind: NotebookKind.paged,
        paper: PaperStyle.blank,
        coverColor: 0,
      );
      final page = source.pages.pagesOf(notebook.id).single;
      final bytes = Uint8List(blobSize);
      for (var i = 0; i < bytes.length; i += 997) {
        bytes[i] = (i * 7 + n) & 0xFF;
      }
      final sha = await source.blobs.putBytes(bytes, mime: 'application/pdf');
      source.elements.save([
        SurfaceElement(
          id: 'img$n',
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
    final path = '${dir.path}/backup.len';
    final out = OutputFileStream(path);
    await source.lenFiles.write(const LenScope.library(), out);
    await out.close();
    final whole = File(path).readAsBytesSync();

    var read = 0, peak = 0;
    late final RangedFile file;
    file = RangedFile(whole.length, (start, end) async {
      read += end - start;
      peak = math.max(peak, file.held + end - start);
      await Future<void>.delayed(Duration.zero); // Asynchronous, like a browser.
      return Uint8List.fromList(whole.sublist(start, end));
    });

    final target = AppServices.create(AppDatabase.inMemory(), blobBackend: MemoryBlobBackend());
    addTearDown(target.dispose);
    final opened = await target.lenFiles.open(RangedInput(file));
    expect(opened.manifest.kind, LenArchiveKind.library);
    expect(opened.contents.notebooks.values.toSet(), {'N0', 'N1', 'N2'});
    final result = await target.lenFiles.import(opened, folderName: 'Backup');
    expect(result.notebooks, hasLength(3));
    expect(result.missingBlobs, 0);
    expect(result.problems, isEmpty);
    for (final id in result.notebooks) {
      final page = target.pages.pagesOf(id).single;
      final image = SurfaceCopier(
        target.strokes,
        elements: target.elements,
      ).loadAllElements(page.id).single;
      final blob = await target.blobs.read(ImageData.fromJson(image.data).blob);
      expect(blob, hasLength(blobSize));
    }
    // Each byte read about twice (a blob is checked against its hash, then
    // stored).
    expect(read, lessThan(whole.length * 2.1));
    // At most the slice being read and the one before it (1 MB each) and
    // the zip's structure.
    expect(peak, lessThan(2.5 * (1 << 20)), reason: 'of ${whole.length} bytes');
  });

  test('a slice kept after one it overlaps still finds every kept byte', () async {
    final whole = Uint8List.fromList([for (var i = 0; i < 1000; i++) i & 0xFF]);
    final file = RangedFile(whole.length, (start, end) async => whole.sublist(start, end));
    await file.load(0, 300, keep: true);
    await file.load(100, 1000, keep: true);
    expect(file.byteAt(50), 50); // Looked up last: the first slice.
    // Inside the second slice, but not the one looked up last.
    await file.load(200, 500, keep: true);
    expect(file.byteAt(700), 700 & 0xFF);
    expect(file.bytes(0, 1000), whole);
  });
}
