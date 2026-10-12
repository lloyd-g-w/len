/// Usage and quota of the site's storage, in bytes.
typedef StorageUsage = ({int usage, int quota});

/// The site's storage in a browser (`navigator.storage`).
abstract interface class BrowserStorage {
  /// Whether the browser keeps Len's data until the user clears it.
  Future<bool> isPersisted();

  /// Asks the browser to keep Len's data (`navigator.storage.persist()`);
  /// completes with whether it now does. Chromium and Safari decide
  /// silently (an installed app is usually granted); Firefox asks the user.
  Future<bool> requestPersistence();

  /// Current usage and quota, or null if the browser cannot tell.
  Future<StorageUsage?> usage();
}
