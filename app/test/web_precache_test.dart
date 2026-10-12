import 'package:flutter_test/flutter_test.dart';

import '../tool/web_precache.dart';

void main() {
  const sw = "const PRECACHE = /* precache */ { version: 'dev', files: [] } /* end precache */;";

  test('lists the build files and versions them by content', () {
    final files = {
      'index.html': [1],
      'main.dart.js': [2],
      'sw.js': [3],
      'flutter_service_worker.js': [4],
      'canvaskit/canvaskit.wasm': [5],
      'canvaskit/skwasm.wasm': [6],
      'canvaskit/wimp.wasm': [6],
      'canvaskit/webparagraph/canvaskit.wasm': [6],
      'canvaskit/canvaskit.js.symbols': [7],
      'assets/packages/pdfrx/assets/pdfium.wasm': [8],
    };
    final out = injectPrecache(sw, files);
    expect(out, startsWith('const PRECACHE = /* precache */ {"version":"'));
    expect(out, endsWith('/* end precache */;'));
    for (final kept in ['index.html', 'main.dart.js', 'canvaskit/canvaskit.wasm', 'pdfium.wasm']) {
      expect(out, contains(kept));
    }
    for (final dropped in [
      '"sw.js"',
      'flutter_service_worker',
      'skwasm',
      'wimp',
      'webparagraph',
      'symbols',
    ]) {
      expect(out, isNot(contains(dropped)));
    }
    // Same files → same worker; any changed byte → a new version.
    expect(injectPrecache(sw, files), out);
    expect(
      injectPrecache(sw, {
        ...files,
        'main.dart.js': [9],
      }),
      isNot(out),
    );
    // Idempotent on an already processed worker.
    expect(injectPrecache(out, files), out);
  });

  test('keeps skwasm for wasm builds', () {
    final out = injectPrecache(sw, {
      'main.dart.wasm': [1],
      'canvaskit/skwasm.wasm': [2],
    });
    expect(out, contains('canvaskit/skwasm.wasm'));
  });
}
