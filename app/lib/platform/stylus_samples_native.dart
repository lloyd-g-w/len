import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../ink/input/sample_source.dart';
import '../ink/input/stylus_batch.dart';

/// Channel carrying `StylusBatchCodec` messages from `StylusCapture.kt`.
const String stylusSamplesChannel = 'len/stylus_samples';

StylusBatchBuffer? _buffer;

/// A sample source for one input controller, or null where the platform
/// already delivers every sample (everything but Android).
SampleSource? openStylusSamples() {
  if (!Platform.isAndroid) return null;
  final buffer = _buffer ??= _listen();
  return StylusSampleMerger(
    buffer,
    devicePixelRatio: () =>
        WidgetsBinding.instance.platformDispatcher.implicitView?.devicePixelRatio ?? 1,
  );
}

/// Starts receiving batches into one app-wide buffer.
StylusBatchBuffer _listen() {
  final buffer = StylusBatchBuffer();
  const BasicMessageChannel<ByteData?>(stylusSamplesChannel, BinaryCodec()).setMessageHandler((
    message,
  ) async {
    if (message != null) buffer.addAll(StylusBatchCodec.decode(message));
    return null;
  });
  return buffer;
}
