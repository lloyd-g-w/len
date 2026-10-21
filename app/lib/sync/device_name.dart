import 'package:flutter/foundation.dart';

import '../data/settings_repository.dart';
import '../platform/device_label.dart' as platform;

/// What this device is called to the user's other devices: in their
/// presence plates (the live connection's `hello`) and on the versions it
/// makes. The user names it in Settings → Sync; until then (or once the
/// name is cleared) it is [suggested]: the system's device name where there
/// is one (Android), else the platform with the host name or the browser
/// (`Linux (studio)`, `Firefox on Mac`). Local to this device, not synced.
class DeviceName extends ChangeNotifier {
  DeviceName(this._settings, {String Function()? platformName})
    : _platformName = platformName ?? (() => platform.platformDeviceName);

  final SettingsRepository _settings;
  final String Function() _platformName;

  /// The longest name (the live connection's limit).
  static const maxLength = 64;

  /// The name in use.
  String get value => custom ?? suggested;

  /// The name the user gave, or null.
  String? get custom => _settings.deviceName;

  /// The name used while the user gave none.
  String get suggested => _settings.systemDeviceName ?? (_platform ??= _platformName());
  String? _platform;

  /// Names this device [name] (trimmed, cut to [maxLength]); empty or
  /// [suggested] goes back to the suggested name.
  void rename(String name) {
    var trimmed = name.trim();
    if (trimmed.length > maxLength) trimmed = trimmed.substring(0, maxLength).trimRight();
    final custom = trimmed.isEmpty || trimmed == suggested ? null : trimmed;
    if (custom == this.custom) return;
    _settings.deviceName = custom;
    notifyListeners();
  }

  /// Asks the system for the device's name (Android; [ask] in tests) and
  /// keeps it as [suggested] when it has one. Once per app start.
  Future<void> detect({Future<String?> Function()? ask}) async {
    final String? name;
    try {
      name = await (ask ?? platform.systemDeviceName)();
    } on Object catch (e) {
      debugPrint('Device name unavailable: $e');
      return;
    }
    if (name == null || name == _settings.systemDeviceName) return;
    if (_disposed) return;
    final cut = name.length > maxLength ? name.substring(0, maxLength).trimRight() : name;
    try {
      _settings.systemDeviceName = cut;
    } on Object catch (e) {
      // The database closed meanwhile (the app or a test ended).
      debugPrint('Device name not kept: $e');
      return;
    }
    if (custom == null && !_disposed) notifyListeners();
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
