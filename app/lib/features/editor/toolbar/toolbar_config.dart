import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../data/app_preferences.dart';
import '../../../domain/stroke.dart';
import '../../../ink/tool_settings.dart';

/// A favourite pen (GoodNotes-style favourites row): an inking tool with a
/// colour and a width, picked in one tap.
@immutable
class FavouritePen {
  const FavouritePen({required this.tool, required this.color, required this.width});

  /// [EditorTool.pen] or [EditorTool.highlighter].
  final EditorTool tool;

  /// Opaque ARGB.
  final int color;

  /// World units.
  final double width;

  /// The ink this favourite draws with.
  InkTool get ink => tool == EditorTool.highlighter ? InkTool.highlighter : InkTool.ballpoint;

  /// The favourite matching what [tools] would draw now, if it is an ink.
  static FavouritePen? current(ToolSettings tools) {
    final tool = tools.tool;
    if (tool != EditorTool.pen && tool != EditorTool.highlighter) return null;
    final config = tools.activeConfig;
    return FavouritePen(tool: tool, color: config.color, width: config.width);
  }

  /// Whether [tools] currently draws with this favourite.
  bool isActiveIn(ToolSettings tools) => current(tools) == this;

  /// Selects this favourite's tool, colour and width in [tools].
  void applyTo(ToolSettings tools) => tools.usePreset(tool, color: color, width: width);

  Map<String, Object?> toJson() => {'tool': tool.name, 'color': color, 'width': width};

  /// Parses [toJson]'s output; null when malformed.
  static FavouritePen? fromJson(Object? json) {
    if (json is! Map) return null;
    final tool = EditorTool.values.asNameMap()[json['tool']];
    final color = json['color'], width = json['width'];
    if (tool != EditorTool.pen && tool != EditorTool.highlighter) return null;
    if (color is! int || width is! num || width <= 0) return null;
    return FavouritePen(tool: tool!, color: color, width: width.toDouble());
  }

  @override
  bool operator ==(Object other) =>
      other is FavouritePen &&
      other.tool == tool &&
      other.color == color &&
      (other.width - width).abs() < 1e-3;

  @override
  int get hashCode => Object.hash(tool, color, (width * 100).round());
}

/// The user's toolbar: the order of the tools, which are hidden, and the
/// favourite pens. Persisted locally ([AppPreferences.toolbarLayout]).
@immutable
class ToolbarConfig {
  const ToolbarConfig({
    this.order = EditorTool.values,
    this.hidden = const {},
    this.favourites = const [],
  });

  /// Every tool, in display order.
  final List<EditorTool> order;
  final Set<EditorTool> hidden;
  final List<FavouritePen> favourites;

  static const int maxFavourites = 8;

  bool get isDefault => this == const ToolbarConfig();

  /// [items] (one per tool) in the configured order without hidden tools;
  /// [keep] (the active tool) is shown even if hidden.
  List<T> arrange<T>(List<T> items, EditorTool Function(T item) toolOf, {EditorTool? keep}) {
    final rank = {for (final (i, t) in order.indexed) t: i};
    final shown = [
      for (final item in items)
        if (!hidden.contains(toolOf(item)) || toolOf(item) == keep) item,
    ];
    return shown..sort((a, b) => rank[toolOf(a)]!.compareTo(rank[toolOf(b)]!));
  }

  /// Moves [tool] just before [before] (to the end when null).
  ToolbarConfig moveBefore(EditorTool tool, EditorTool? before) {
    if (tool == before) return this;
    final list = [...order]..remove(tool);
    final at = before == null ? -1 : list.indexOf(before);
    list.insert(at == -1 ? list.length : at, tool);
    return _copy(order: list);
  }

  /// Moves the item at [from] of [shown] (the tools on screen, in this
  /// order) to index [to] of the reordered list.
  ToolbarConfig reorder(List<EditorTool> shown, int from, int to) {
    final rest = [...shown]..removeAt(from);
    return moveBefore(shown[from], to < rest.length ? rest[to] : null);
  }

  /// Shows or hides [tool]; at least one tool stays visible.
  ToolbarConfig toggle(EditorTool tool) {
    if (hidden.contains(tool)) return _copy(hidden: {...hidden}..remove(tool));
    final visible = order.where((t) => !hidden.contains(t) && t != EditorTool.selectText);
    if (visible.length <= 1) return this;
    return _copy(hidden: {...hidden, tool});
  }

  /// Adds [pen] to the favourites (once, at most [maxFavourites]).
  ToolbarConfig addFavourite(FavouritePen pen) {
    if (favourites.contains(pen) || favourites.length >= maxFavourites) return this;
    return _copy(favourites: [...favourites, pen]);
  }

  ToolbarConfig removeFavourite(int index) => _copy(favourites: [...favourites]..removeAt(index));

  ToolbarConfig _copy({
    List<EditorTool>? order,
    Set<EditorTool>? hidden,
    List<FavouritePen>? favourites,
  }) => ToolbarConfig(
    order: List.unmodifiable(order ?? this.order),
    hidden: Set.unmodifiable(hidden ?? this.hidden),
    favourites: List.unmodifiable(favourites ?? this.favourites),
  );

  String encode() => jsonEncode({
    'order': [for (final t in order) t.name],
    'hidden': [for (final t in hidden) t.name],
    'favourites': [for (final f in favourites) f.toJson()],
  });

  /// Parses [encode]'s output; the default toolbar when missing or
  /// malformed. Tools unknown to the order are appended in default order.
  static ToolbarConfig decode(String? text) {
    if (text == null) return const ToolbarConfig();
    final Object? data;
    try {
      data = jsonDecode(text);
    } on FormatException {
      return const ToolbarConfig();
    }
    if (data is! Map) return const ToolbarConfig();
    final names = EditorTool.values.asNameMap();
    List<EditorTool> tools(Object? list) => [
      if (list is List)
        for (final name in list) ?names[name],
    ];
    final order = tools(data['order']).toSet().toList();
    for (final tool in EditorTool.values) {
      if (!order.contains(tool)) order.add(tool);
    }
    final favourites = data['favourites'];
    return const ToolbarConfig()._copy(
      order: order,
      hidden: tools(data['hidden']).toSet(),
      favourites: [
        if (favourites is List)
          for (final f in favourites.take(maxFavourites)) ?FavouritePen.fromJson(f),
      ],
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ToolbarConfig &&
      listEquals(other.order, order) &&
      setEquals(other.hidden, hidden) &&
      listEquals(other.favourites, favourites);

  @override
  int get hashCode => Object.hash(Object.hashAll(order), hidden.length, Object.hashAll(favourites));
}

/// The toolbar configuration in the preferences.
extension ToolbarConfigPreference on AppPreferences {
  ToolbarConfig get toolbarConfig => ToolbarConfig.decode(toolbarLayout);
  set toolbarConfig(ToolbarConfig value) => toolbarLayout = value.isDefault ? null : value.encode();
}
