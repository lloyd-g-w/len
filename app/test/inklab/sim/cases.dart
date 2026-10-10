import 'dart:ui';

import 'package:len/ink/lab/input_recording.dart';

import 'digitiser.dart';
import 'pen_motion.dart';

/// A named simulated writing scenario with its ground truth.
class SimCase {
  SimCase(this.name, this.description, this.contacts, {this.model = const DigitiserModel()});

  final String name;
  final String description;
  final List<SimContact> contacts;
  final DigitiserModel model;

  /// The recording of this case drawn with [pen], and its truth.
  ({InputRecording recording, List<TruthStroke> truth}) record(PenSettings pen) =>
      Digitiser(model).record(contacts, pen: pen, note: '$name: $description');
}

/// The default pen (as shipped): 2.5 wide, stabiliser 0.4.
const PenSettings defaultPen = PenSettings();

/// Stabiliser settings every case is measured at.
const List<double> stabilisers = [0, 0.4, 1];

const _o = Offset(60, 120);

/// The scenarios: handwriting, fast loops, cusps, pressure, taps, lines,
/// pen-lift hooks, bounces, a spiral and a long stroke for timing.
final List<SimCase> simCases = [
  SimCase('cursive', 'cursive "elleue" and "lull", x-height 10 px', [
    SimContact(cursive(_o, [letterE, letterL, letterL, letterE, letterU, letterE]), start: 0),
    SimContact(cursive(_o + const Offset(90, 0), [letterL, letterU, letterL, letterL]), start: 1.6),
  ]),
  SimCase('fast_loops', 'six 7 px loops at 6 loops/s', [
    SimContact(loops(_o + const Offset(0, 10)), start: 0),
  ]),
  SimCase('zigzag', 'sharp 24 px reversals (cusps), pen stops at each tip', [
    SimContact(zigzag(_o + const Offset(0, 10)), start: 0),
    SimContact(zigzag(_o + const Offset(80, 10), height: 12, pitch: 5, seconds: 0.07), start: 0.9),
  ]),
  SimCase('pressure_swell', 'slow 220 px line, pressure 0.08 → 0.98 → 0.08', [
    SimContact(swell(_o), start: 0),
  ]),
  SimCase('taps', 'five dots (i-dots / full stops)', [
    for (var i = 0; i < 5; i++) SimContact(tap(_o + Offset(i * 14.0, 0)), start: i * 0.25),
  ]),
  SimCase('lines', 'quick straight strokes: horizontal, vertical, diagonal', [
    SimContact(line(_o, _o + const Offset(160, 0), seconds: 0.18), start: 0),
    SimContact(line(_o + const Offset(0, 20), _o + const Offset(0, 90)), start: 0.4),
    SimContact(
      line(_o + const Offset(30, 90), _o + const Offset(140, 20), seconds: 0.2),
      start: 0.8,
    ),
  ]),
  SimCase('hooks', 'strokes with pen-down and pen-up flicks (not ink)', [
    SimContact(line(_o, _o + const Offset(120, 10)), start: 0, downHook: true, upHook: true),
    SimContact(
      cursive(_o + const Offset(0, 40), [letterU, letterU, letterE]),
      start: 0.5,
      downHook: true,
      upHook: true,
    ),
  ]),
  SimCase('bounces', 'strokes followed by accidental re-contacts 40 ms after lift', [
    SimContact(line(_o, _o + const Offset(100, 0)), start: 0, bounce: true),
    SimContact(tap(_o + const Offset(120, 0)), start: 0.5, bounce: true),
  ]),
  SimCase('spiral', 'inward spiral, curvature rising (edge smoothness at 16x)', [
    SimContact(spiral(_o + const Offset(60, 40)), start: 0),
  ]),
  SimCase('long_stroke', '8 s of continuous cursive (timing vs length)', [
    SimContact(
      cursive(_o + const Offset(0, 40), [
        for (var i = 0; i < 12; i++) ...[letterE, letterL, letterU],
      ]),
      start: 0,
    ),
  ]),
];
