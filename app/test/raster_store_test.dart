import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/platform/raster_store_native.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('len_rasters'));
  tearDown(() => dir.deleteSync(recursive: true));

  Uint8List bytes(int n, int fill) => Uint8List(n)..fillRange(0, n, fill);

  test('files keep rasters across restarts, least recently used out first', () async {
    final first = FileRasterStore(dir.path, maxBytes: 3000);
    await first.write('a.png', bytes(1000, 1));
    await first.write('b.png', bytes(1000, 2));
    await first.write('c.png', bytes(1000, 3));
    expect(await first.read('a.png'), bytes(1000, 1)); // Now the most recent.
    await first.write('d.png', bytes(1000, 4)); // Evicts b.
    expect(await first.read('b.png'), isNull);
    expect(dir.listSync().length, 3);

    // A restart lists the files by last use (reads refresh it).
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final second = FileRasterStore(dir.path, maxBytes: 3000);
    await second.ready;
    expect(await second.read('c.png'), bytes(1000, 3));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await second.write('e.png', bytes(1000, 5)); // Evicts the oldest: a or d, not c.
    expect(await second.read('c.png'), isNotNull);
    expect(await second.read('e.png'), bytes(1000, 5));
    expect(dir.listSync().length, 3);
  });

  test('an interrupted write leaves no raster behind', () async {
    File('${dir.path}/x.png.0.tmp').writeAsBytesSync([1, 2, 3]);
    final store = FileRasterStore(dir.path);
    await store.write('y.png', bytes(10, 1));
    expect(dir.listSync().map((f) => f.uri.pathSegments.last), ['y.png']);
    expect(await store.read('x.png'), isNull);
  });
}
