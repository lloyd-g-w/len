/// Whether this platform keeps an install marker: browsers don't.
const bool hasInstallMarker = false;

/// Browsers have no marker.
String? readInstallMarker(String directory) => null;

/// Browsers have no marker.
void writeInstallMarker(String directory, String deviceId) {}
