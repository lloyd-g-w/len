import '../core/clock.dart';
import 'settings_repository.dart';

/// Tells this installation's own database from one brought here from
/// elsewhere: an Android backup restored on a new (or reset) device, or a
/// data folder copied to another computer.
///
/// Next to the database lies an install marker (`platform/install_marker`)
/// holding the device id; Android's backup rules leave it out. A database
/// that has a device id but no matching marker came from somewhere else, so
/// this installation takes a new device id (it must never write as the
/// device the data came from) and forgets where sync stood, so the next sync
/// with the same server uploads and pulls everything again (last-write-wins
/// sorts out what is newer).
abstract final class InstallIdentity {
  /// Checks [marker] (the marker's content, null if there is none) against
  /// [settings]; returns the device id the marker must hold from now on and
  /// whether the database was adopted from elsewhere.
  static ({String deviceId, bool adopted}) check(
    SettingsRepository settings, {
    required String? marker,
    Clock clock = const Clock(),
  }) {
    final existing = settings.storedDeviceId;
    if (existing == null || existing == marker) {
      return (deviceId: settings.deviceId(clock), adopted: false);
    }
    settings
      ..replaceDeviceId(clock.newId())
      ..syncLastSeq = 0
      ..syncServerId = ''
      ..syncBlobsCollectedAt = 0;
    return (deviceId: settings.deviceId(clock), adopted: true);
  }
}
