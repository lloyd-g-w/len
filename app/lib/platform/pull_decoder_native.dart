import 'dart:isolate';
import 'dart:typed_data';

import '../sync/pull_page.dart';

/// Pages smaller than this are decoded in place: starting a worker costs
/// more than parsing them (an incremental sync's few records).
const _inPlaceBytes = 32 * 1024;

/// Decodes a `/v1/pull` answer (see [decodePullPage]) in a short-lived
/// worker isolate; its result moves back without being copied.
Future<PullPage?> decodePulled(Uint8List body, {required int since}) async =>
    body.length < _inPlaceBytes
    ? decodePullPage(body, since: since)
    : Isolate.run(() => decodePullPage(body, since: since), debugName: 'pull decoder');
