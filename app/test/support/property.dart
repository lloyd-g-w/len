import 'dart:async';

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

/// A seeded generator of random values for property tests.
typedef Gen<T> = T Function(math.Random random);

/// Checks [property] for [runs] values of [gen], each drawn from its own
/// seeded [math.Random] (seed + run), so a run is deterministic and a
/// failure names the seed that reproduces it alone:
/// `forAll(gen, property, seed: <reported>, runs: 1)`.
///
/// [property] throws (an `expect` failing) when it does not hold; it may
/// be async.
Future<void> forAll<T>(
  Gen<T> gen,
  FutureOr<void> Function(T value) property, {
  int runs = 100,
  int seed = 1,
  String Function(T value)? describe,
}) async {
  for (var run = 0; run < runs; run++) {
    final value = gen(math.Random(seed + run));
    try {
      await property(value);
    } on Object catch (e) {
      final what = describe?.call(value) ?? '$value';
      final shown = what.length > 2000 ? '${what.substring(0, 2000)}…' : what;
      fail('Property failed for seed ${seed + run} (run $run of $runs):\n$shown\n\n$e');
    }
  }
}

/// Generators of common values.
abstract final class Gens {
  /// An int in [min, max] (inclusive).
  static Gen<int> intIn(int min, int max) =>
      (r) => min + r.nextInt(max - min + 1);

  /// A double in [min, max).
  static Gen<double> doubleIn(double min, double max) =>
      (r) => min + r.nextDouble() * (max - min);

  /// True with [probability].
  static Gen<bool> chance(double probability) =>
      (r) => r.nextDouble() < probability;

  /// One of [values].
  static Gen<T> oneOf<T>(List<T> values) =>
      (r) => values[r.nextInt(values.length)];

  /// The value of one of [gens].
  static Gen<T> anyOf<T>(List<Gen<T>> gens) =>
      (r) => gens[r.nextInt(gens.length)](r);

  /// A list of [length] values of [item].
  static Gen<List<T>> listOf<T>(Gen<T> item, Gen<int> length) =>
      (r) => [for (var i = length(r); i > 0; i--) item(r)];

  /// [values] shuffled.
  static List<T> shuffled<T>(List<T> values, math.Random r) => [...values]..shuffle(r);
}
