import 'dart:typed_data';

/// A growable list of doubles backed by a [Float64List] (no boxing), for
/// the per-sample arrays of the stroke pipeline.
class DoubleBuffer {
  DoubleBuffer([int capacity = 64]) : _v = Float64List(capacity);

  Float64List _v;
  int _length = 0;

  int get length => _length;

  /// Shrinks to [n] values (or grows, keeping the old values beyond the
  /// previous length undefined).
  set length(int n) {
    _reserve(n);
    _length = n;
  }

  double operator [](int i) => _v[i];
  void operator []=(int i, double value) => _v[i] = value;

  void add(double value) {
    _reserve(_length + 1);
    _v[_length++] = value;
  }

  void _reserve(int n) {
    if (n <= _v.length) return;
    var cap = _v.length * 2;
    while (cap < n) {
      cap *= 2;
    }
    _v = Float64List(cap)..setRange(0, _length, _v);
  }

  /// A copy of the first [length] values.
  Float64List toList() => Float64List.sublistView(_v, 0, _length).sublist(0);
}
