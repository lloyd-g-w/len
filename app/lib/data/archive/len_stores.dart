import '../syncable_table.dart';

/// The tables a Len file is read from and written into, by collection
/// ([LenFormat.collections]).
class LenStores {
  LenStores(Iterable<SyncableTable> tables)
    : _byCollection = {for (final t in tables) t.collection: t};

  final Map<String, SyncableTable> _byCollection;

  /// The table of [collection]; throws if it is not one of a Len file's.
  SyncableTable of(String collection) =>
      _byCollection[collection] ?? (throw ArgumentError.value(collection, 'collection'));

  /// The table of [collection], or null for collections Len files don't hold.
  SyncableTable? maybeOf(String collection) => _byCollection[collection];

  /// Any of the tables (they share one database).
  SyncableTable get any => _byCollection.values.first;
}
