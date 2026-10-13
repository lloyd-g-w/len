import 'dart:typed_data';

import '../sync/pull_page.dart';

/// Decodes a `/v1/pull` answer (see [decodePullPage]) on the UI thread.
Future<PullPage?> decodePulled(Uint8List body, {required int since}) async =>
    decodePullPage(body, since: since);
