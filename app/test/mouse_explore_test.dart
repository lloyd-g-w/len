import 'package:flutter_test/flutter_test.dart';
import 'package:len/ink/lab/replay_run.dart';

import 'support/ink_roughness.dart';
import 'support/mouse_writing.dart';

const _only = String.fromEnvironment('ONLY');
const _sls = String.fromEnvironment('SLS', defaultValue: '0,0.3');

void main() {
  test('explore', () {
    final rows = <String>[];
    {
      const sg = '';
      for (final speed in [150.0, 600.0]) {
        for (final model in const [
          MouseModel(hz: 1000, quantum: 0),
          MouseModel(hz: 125),
          MouseModel(hz: 1000),
          MouseModel(hz: 1000, delivery: Delivery.coalesced),
          MouseModel(hz: 500, delivery: Delivery.batched),
        ]) {
          for (final zoom in [1.0]) {
            for (final width in [1.5, 4.0]) {
              for (final sl in _sls.split(',').map(double.parse)) {
                final pen = penOf(width / zoom, sl);
                for (final (name, paths, straight) in [
                  ('formula', ownerFormula(), false),
                  ('lines', straightLines(), true),
                ]) {
                  final label =
                      'σ$sg $name v$speed ${model.quantum == 0 ? 'ideal' : model} z$zoom w$width s$sl';
                  if (_only.isNotEmpty && !RegExp(_only).hasMatch(label)) continue;
                  final rec = mouseRecording(
                    paths,
                    model: model,
                    speed: speed,
                    pen: pen,
                    zoom: zoom,
                  );
                  final replay = ReplayResult.run(rec.recording);
                  final r = roughnessOf(replay, paths, zoom: zoom, straight: straight);
                  final lag = lagOf(replay, rec.events, zoom: zoom);
                  rows.add(
                    '$label: $r  lag ${lag.median.toStringAsFixed(1)}/${lag.p90.toStringAsFixed(1)}',
                  );
                }
              }
            }
          }
        }
      }
    }
    // ignore: avoid_print
    print(rows.join('\n'));
  }, timeout: const Timeout(Duration(minutes: 20)));
}
