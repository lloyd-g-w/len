part of 'stroke_shaper.dart';

/// 6. Radii: causal smoothing, then the end rules, then the tapers.
extension _Radii on StrokeShaper {
  void _radii(int count) {
    final keep = p.radiusKeep, d = p.slope;
    // Values computed from final input in an earlier call are final.
    final from = _radDone;
    _r1.length = count;
    _r2.length = count;
    _rs.length = count;
    for (var i = from; i < count; i++) {
      if (i == 0) {
        _r1[0] = _r2[0] = _rs[0] = _rr[0];
        continue;
      }
      _r1[i] = _r1[i - 1] * keep + _rr[i] * (1 - keep);
      _r2[i] = _r2[i - 1] * keep + _r1[i] * (1 - keep);
      _rs[i] = _r2[i].clamp(_rs[i - 1] - d, _rs[i - 1] + d);
    }
    _radDone = _resFinal;
  }

  void _endRules(int count) {
    _ro.length = count;
    final from = _roDone;
    for (var i = from; i < count; i++) {
      _ro[i] = _rs[i];
    }
    if (from == 0) {
      // Start: non-swelling, then levelled (final once the start reach is,
      // which the gate ensures before anything is shown).
      final ks = math.min(count - 1, p.settleK);
      for (var i = ks - 1; i >= 0; i--) {
        _ro[i] = math.min(_ro[i], _ro[i + 1]);
      }
      if (p.levelK > 0 && count > p.levelK) {
        final level = _ro[p.levelK];
        for (var i = 0; i < p.levelK; i++) {
          _ro[i] = math.max(_ro[i], level);
        }
      }
    }
    // End (the moving tip while drawing, the real end once ended).
    final ke = math.min(count - 1, p.settleEndK);
    for (var i = count - ke; i < count; i++) {
      if (i > 0) _ro[i] = math.min(_ro[i], _ro[i - 1]);
    }
    if (p.levelEndK > 0 && count > 2 * p.levelEndK) {
      final level = _ro[count - 1 - p.levelEndK];
      for (var i = count - p.levelEndK; i < count; i++) {
        _ro[i] = math.max(_ro[i], level);
      }
    }
    final settled = _resFinal - p.endReach;
    if (settled > p.startReach && settled > _roDone) _roDone = settled;
  }

  void _taper(int count, {required bool ended}) {
    taperedFrom = count;
    if (!_tapers) return;
    _rt.length = count;
    // Final radii taper as they were; the rest (and an end taper from
    // before a roll-back) is redone.
    _rtFrom = math.min(_rtFrom, _roDone);
    final start = p.taperStart, step = p.step;
    for (var i = _rtFrom; i < count; i++) {
      _rt[i] = start > 0 ? _ro[i] * Taper.factor(i * step, start) : _ro[i];
    }
    _rtFrom = _roDone;
    taperedFrom = count;
    if (!ended || taperEnd <= 0 || count < 2) return;
    // Every sample is a step from the one before, but the last.
    final dx = _rx[count - 1] - _rx[count - 2], dy = _ry[count - 1] - _ry[count - 2];
    final total = (count - 2) * step + _dist(dx, dy);
    final length = math.min(taperEnd, total * Taper.maxEndShare);
    for (var i = count - 1; i >= 0; i--) {
      final along = i == count - 1 ? 0.0 : total - i * step;
      if (along >= length) break;
      _rt[i] *= Taper.factor(along, length);
      _rtFrom = math.min(_rtFrom, i);
      taperedFrom = i;
    }
  }
}
