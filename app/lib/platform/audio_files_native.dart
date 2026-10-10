import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/blob_store.dart';

/// A new temporary file for a capture with file [extension] (e.g. `m4a`).
Future<String> newCaptureTarget(String extension) async {
  final dir = await getTemporaryDirectory();
  await dir.create(recursive: true);
  return p.join(dir.path, 'len-recording-${DateTime.now().microsecondsSinceEpoch}.$extension');
}

/// Deletes a finished capture's temporary file (after it became a blob).
Future<void> deleteCapture(String path) async {
  try {
    await File(path).delete();
  } on FileSystemException {
    // Already gone.
  }
}

/// Why recording cannot work on this device, or null. On Linux the
/// `record` package captures with PulseAudio's `parecord` (also provided
/// by PipeWire) and encodes with `ffmpeg`, both looked up on the `PATH`.
Future<String?> recordingUnavailableReason() async {
  if (!Platform.isLinux) return null;
  final missing = [
    for (final tool in ['parecord', 'ffmpeg'])
      if (!_onPath(tool)) tool,
  ];
  if (missing.isEmpty) return null;
  return 'Recording needs ${missing.join(' and ')} '
      '(packages pulseaudio-utils / pipewire-pulse and ffmpeg).';
}

bool _onPath(String tool) {
  final path = Platform.environment['PATH'] ?? '';
  return path.split(':').any((dir) => dir.isNotEmpty && File(p.join(dir, tool)).existsSync());
}

/// Where a player can read blob [sha]: its file (streamed by the player,
/// never loaded into memory here). Null if it is not on the device.
Future<({String uri, bool isFile})?> audioUriFor(BlobStore blobs, String sha, String mime) async {
  if (!await blobs.has(sha)) return null;
  final path = blobs.localPath(sha);
  if (path != null) return (uri: path, isFile: true);
  return null;
}

/// Frees what [audioUriFor] allocated (nothing natively).
void releaseAudioUri(String uri) {}
