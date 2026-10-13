import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/archive/len_archives.dart';
import 'package:len/domain/image_data.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/surface_element.dart';
import 'package:len/platform/blob_backend_native.dart';
import 'package:len/platform/len_file_io_native.dart' show fileCrc32;

/// Natively, blob files are checksummed in a worker isolate before they go
/// into a Len file, so writing a big library doesn't hold up the UI
/// (UX_AUDIT R8-19); the zip still carries the right checksums.
void main() {
  test('blobs are checksummed off the UI thread, and the checksums hold', () async {
    final dir = await Directory.systemTemp.createTemp('len-blob-crc');
    addTearDown(() => dir.delete(recursive: true));
    final services = AppServices.create(
      AppDatabase.inMemory(),
      blobBackend: FileBlobBackend('${dir.path}/blobs'),
    );
    addTearDown(services.dispose);
    final checked = <String>[];
    services.lenFiles.checksumBlobFile = (path) {
      checked.add(path);
      return fileCrc32(path);
    };
    final notebook = services.notebooks.create(
      title: 'Images',
      kind: NotebookKind.paged,
      paper: PaperStyle.blank,
      coverColor: 0,
    );
    final page = services.pages.pagesOf(notebook.id).single;
    final contents = <Uint8List>[];
    for (var n = 0; n < 2; n++) {
      // Over a megabyte: checksummed in several chunks.
      final bytes = Uint8List.fromList(List.generate(1500 * 1024 + n, (i) => (i * 31 + n) & 0xFF));
      contents.add(bytes);
      final sha = await services.blobs.putBytes(bytes, mime: 'image/png');
      services.elements.save([
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

    final path = '${dir.path}/Images.len';
    final out = OutputFileStream(path);
    final report = await services.lenFiles.write(LenScope.notebook(notebook.id), out);
    await out.close();
    expect(report.blobs, 2);
    expect(checked, hasLength(2));

    final zip = ZipDecoder().decodeStream(InputFileStream(path));
    final blobs = zip.files.where((f) => f.name.startsWith('blobs/')).toList();
    expect(blobs, hasLength(2));
    for (final entry in blobs) {
      final bytes = entry.readBytes()!;
      expect(contents.any((c) => listEquals(c, bytes)), isTrue);
      expect(entry.crc32, getCrc32(bytes), reason: entry.name);
    }

    // And it imports whole.
    final target = AppServices.create(
      AppDatabase.inMemory(),
      blobBackend: FileBlobBackend('${dir.path}/target'),
    );
    addTearDown(target.dispose);
    final result = await target.lenFiles.import(await target.lenFiles.open(InputFileStream(path)));
    expect(result.missingBlobs, 0);
  });
}
