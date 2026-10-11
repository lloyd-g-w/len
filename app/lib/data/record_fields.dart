import 'syncable.dart';

/// Strict, typed access to the `data` of a live [SyncRecord].
///
/// Every field of a collection's format is required (nullable ones must be
/// present, possibly `null`); a missing field or a value of the wrong type
/// throws [FormatException], so the sync engine skips the record as
/// malformed. Keys a reader does not ask for are ignored.
class RecordFields {
  RecordFields(this.record) : _data = record.data!;

  final SyncRecord record;
  final Map<String, Object?> _data;

  /// Throws the [FormatException] for a bad or missing field [key].
  Never invalid(String key) =>
      throw FormatException('Malformed ${record.collection} ${record.id}: $key');

  T _get<T>(String key) {
    final value = _data[key];
    if (value is T && _data.containsKey(key)) return value;
    invalid(key);
  }

  String string(String key) => _get<String>(key);
  String? stringOrNull(String key) => _get<String?>(key);
  int integer(String key) => _get<int>(key);
  int? integerOrNull(String key) => _get<int?>(key);
  bool boolean(String key) => _get<bool>(key);
  List<Object?> list(String key) => _get<List<Object?>>(key);
  Map<String, Object?> object(String key) => _get<Map<String, Object?>>(key);
  Map<String, Object?>? objectOrNull(String key) => _get<Map<String, Object?>?>(key);

  /// A finite number (JSON does not distinguish ints and doubles).
  double number(String key) {
    final value = _get<num>(key);
    if (!value.isFinite) invalid(key);
    return value.toDouble();
  }

  /// The value of [values] named by string field [key].
  T choice<T extends Enum>(String key, List<T> values) =>
      values.asNameMap()[string(key)] ?? invalid(key);
}
