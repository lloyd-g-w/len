import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../ink/input/sample_source.dart';
import '../ink/input/stylus_batch.dart';
import '../ink/input/wet_ink.dart';
import 'low_latency_ink_native.dart';

/// Channel carrying `StylusBatchCodec` messages from `StylusCapture.kt`.
const String stylusSamplesChannel = 'len/stylus_samples';

StylusBatchBuffer? _buffer;
void Function(List<StylusBatch> batches)? _observer;

/// Lets the Ink Lab record every stylus batch as it arrives (null stops).
/// Batches only flow once [openStylusSamples] has been called (Android).
void observeStylusBatches(void Function(List<StylusBatch> batches)? observer) =>
    _observer = observer;

/// A sample source for one input controller, or null where the platform
/// already delivers every sample (everything but Android).
///
/// With [wetInk], [wetInkNext] and [wetInkView] (Android), the native
/// low-latency overlay draws the newest part of each stylus stroke ahead of
/// Flutter (`low_latency_ink_native.dart`): [wetInk] says at the start of
/// a stroke how it looks (null: the overlay cannot draw it), [wetInkNext]
/// how the next one would while the stylus hovers, [wetInkView] where it
/// may be drawn.
SampleSource? openStylusSamples({
  WetInkStyle? Function()? wetInk,
  WetInkStyle? Function()? wetInkNext,
  WetInkView Function()? wetInkView,
}) {
  if (!Platform.isAndroid) return null;
  final buffer = _buffer ??= _listen();
  final merger = StylusSampleMerger(buffer, devicePixelRatio: _devicePixelRatio);
  if (wetInk == null || wetInkNext == null || wetInkView == null) return merger;
  return LowLatencySource(merger, wetInk, wetInkNext, wetInkView, _devicePixelRatio);
}

double _devicePixelRatio() =>
    WidgetsBinding.instance.platformDispatcher.implicitView?.devicePixelRatio ?? 1;

/// Starts receiving batches into one app-wide buffer.
StylusBatchBuffer _listen() {
  final buffer = StylusBatchBuffer();
  const BasicMessageChannel<ByteData?>(stylusSamplesChannel, BinaryCodec()).setMessageHandler((
    message,
  ) async {
    if (message == null) return null;
    final batches = StylusBatchCodec.decode(message);
    buffer.addAll(batches);
    _observer?.call(batches);
    return null;
  });
  return buffer;
}
