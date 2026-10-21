/// What a browser with user agent [ua] is called as a device: its name and
/// its system (`Firefox on Linux`, `Safari on iPad`); `Browser` when unknown.
String browserDeviceName(String ua) {
  final browser = ua.contains('Firefox/')
      ? 'Firefox'
      : ua.contains('Edg/')
      ? 'Edge'
      : ua.contains('OPR/')
      ? 'Opera'
      : ua.contains('Chrome/')
      ? 'Chrome'
      : ua.contains('Safari/')
      ? 'Safari'
      : 'Browser';
  final system = ua.contains('Android')
      ? 'Android'
      : ua.contains('iPad')
      ? 'iPad'
      : ua.contains('iPhone')
      ? 'iPhone'
      : ua.contains('Windows')
      ? 'Windows'
      : ua.contains('Mac OS')
      ? 'Mac'
      : ua.contains('CrOS')
      ? 'ChromeOS'
      : ua.contains('Linux')
      ? 'Linux'
      : null;
  return system == null ? browser : '$browser on $system';
}
