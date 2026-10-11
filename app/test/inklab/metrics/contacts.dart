import 'package:flutter/gestures.dart';
import 'package:len/domain/preferences.dart';
import 'package:len/ink/input/stylus_buttons.dart';
import 'package:len/ink/lab/input_recording.dart';
import 'package:len/ink/lab/raw_samples.dart';

/// A contact of a recording that makes ink, and whether it is a bounce.
typedef InkContact = ({RawContact contact, bool bounce});

/// The contacts of [recording] that make ink: the stylus, and fingers or
/// the mouse only without "stylus only" (with it, fingers pan and zoom).
/// Bounces are shorter than 80 ms and start within 120 ms and 16 px of the
/// last lift (an accidental re-contact, not meant as ink).
List<InkContact> inkContacts(InputRecording recording) {
  final out = <InkContact>[];
  final fingersNavigate = recording.meta.stylusOnly;
  RawContact? previous;
  for (final c in rawContacts(recording)) {
    if (c.cancelled || c.samples.isEmpty) continue;
    // Erasing: the eraser end, or the side button (the replay's default
    // action).
    if (routeStylus(c.kind, c.buttons, PenButtonAction.eraser) != StylusRoute.tool) continue;
    if (c.kind != PointerDeviceKind.stylus && fingersNavigate) continue;
    final bounce =
        previous != null &&
        c.downUs - previous.upUs < 120000 &&
        c.upUs - c.downUs < 80000 &&
        (c.samples.first.position - previous.samples.last.position).distance < 16;
    out.add((contact: c, bounce: bounce));
    previous = c; // the last ink contact (a bounce follows a pen lift)
  }
  return out;
}

/// The contacts of [recording] meant as ink ([inkContacts] but bounces).
List<RawContact> intendedContacts(InputRecording recording) => [
  for (final c in inkContacts(recording))
    if (!c.bounce) c.contact,
];
