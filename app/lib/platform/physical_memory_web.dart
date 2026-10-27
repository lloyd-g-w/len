/// Browsers don't tell (`navigator.deviceMemory` is rounded and capped at
/// 8 GB, and the tab gets far less): caches keep their floor.
int? get physicalMemoryBytes => null;
