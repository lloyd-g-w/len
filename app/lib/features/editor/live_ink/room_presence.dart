import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../sync/live_rooms.dart';
import '../../../ui/app_theme.dart';

/// Who else has this notebook open right now (live sync's presence): a
/// small plate per other device with its initial, in the editor's bar
/// before the actions; nothing while the notebook is open here alone.
///
/// While others are here the plates sit in a slot of a fixed size (room
/// for the most plates shown, aligned to its end) in a layer and a build
/// scope of their own: devices joining, leaving or renamed rebuild, lay
/// out and repaint the plates only, never the bar around them (only the
/// first to come and the last to go change the bar).
class RoomPresence extends StatefulWidget {
  const RoomPresence({super.key, required this.rooms, required this.room, this.compact = false});

  final LiveRooms rooms;
  final String room;

  /// One plate only (phones, short windows): the other device's initial,
  /// or how many others there are ("+3").
  final bool compact;

  /// Plates shown at most; more are counted in the last one.
  static const maxShown = 3;

  /// Edge of a plate: a bar glyph with a little room around the letter.
  static const double plate = Glyphs.bar + Gaps.xs;

  /// The letter a device [name] shows as (its plate, its pointer's label).
  static String initialOf(String name) =>
      name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase();

  @override
  State<RoomPresence> createState() => _RoomPresenceState();
}

class _RoomPresenceState extends State<RoomPresence> {
  /// Whether others are here (the slot shows).
  late bool _here = _othersHere;

  bool get _othersHere => widget.rooms.othersIn(widget.room).isNotEmpty;

  @override
  void initState() {
    super.initState();
    widget.rooms.addListener(_roomsChanged);
  }

  @override
  void didUpdateWidget(RoomPresence old) {
    super.didUpdateWidget(old);
    if (old.rooms != widget.rooms) {
      old.rooms.removeListener(_roomsChanged);
      widget.rooms.addListener(_roomsChanged);
    }
    _here = _othersHere;
  }

  @override
  void dispose() {
    widget.rooms.removeListener(_roomsChanged);
    super.dispose();
  }

  /// Rebuilds the slot only when it comes or goes: the plates follow the
  /// room themselves.
  void _roomsChanged() {
    if (_othersHere != _here) setState(() => _here = !_here);
  }

  @override
  Widget build(BuildContext context) {
    if (!_here) return const SizedBox.shrink();
    final most = widget.compact ? 1 : RoomPresence.maxShown;
    return SizedBox.fromSize(
      size: _slot(context, most),
      child: RepaintBoundary(
        // Its own build scope: the bar's (a LayoutBuilder's) would lay out
        // the bar again, and repaint it, whenever the plates rebuild.
        child: LayoutBuilder(
          builder: (context, _) =>
              ListenableBuilder(listenable: widget.rooms, builder: (context, _) => _plates(most)),
        ),
      ),
    );
  }

  Widget _plates(int most) {
    final others = widget.rooms.othersIn(widget.room);
    if (others.isEmpty) return const SizedBox.shrink();
    final names = [for (final m in others) m.name ?? 'Another device'];
    final shown = others.length > most ? most - 1 : others.length;
    final label = 'Also open on ${_list(names)}';
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      // Should a count need more room than kept ("+100"), the plates
      // shrink rather than overflow.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: AlignmentDirectional.centerEnd,
        child: Tooltip(
          message: label,
          excludeFromSemantics: true,
          child: Semantics(
            label: label,
            excludeSemantics: true,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: _padding(widget.compact)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: Gaps.xs,
                children: [
                  for (final name in names.take(shown)) _Plate(text: RoomPresence.initialOf(name)),
                  if (others.length > shown) _Plate(text: '+${others.length - shown}'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static double _padding(bool compact) => compact ? Gaps.xs : Gaps.sm;

  /// The slot for [most] plates: each as wide as an initial needs, the
  /// last as a two-digit count does, as tall as their text.
  Size _slot(BuildContext context, int most) {
    final style = _Plate.styleOf(context);
    final scaler = MediaQuery.textScalerOf(context);
    Size measure(String text) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final size = painter.size;
      painter.dispose();
      return size;
    }

    final initial = measure('W'), count = measure('+88');
    const plate = RoomPresence.plate;
    double width(Size text) => math.max(plate, text.width + 2 * _Plate.inset);
    final last = math.max(width(initial), width(count));
    return Size(
      2 * _padding(widget.compact) + (most - 1) * (width(initial) + Gaps.xs) + last,
      math.max(plate, math.max(initial.height, count.height)),
    );
  }

  static String _list(List<String> names) => names.length == 1
      ? names.single
      : '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
}

/// One device's plate: its initial (or a count) on a selected-ink plate,
/// wider when its text needs it (large text, "+12").
class _Plate extends StatelessWidget {
  const _Plate({required this.text});

  final String text;

  /// Room on either side of the text.
  static const double inset = Gaps.xxs;

  /// The style of a plate's text.
  static TextStyle? styleOf(BuildContext context) {
    final theme = Theme.of(context);
    return theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurface);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(
        minWidth: RoomPresence.plate,
        minHeight: RoomPresence.plate,
      ),
      padding: const EdgeInsets.symmetric(horizontal: inset),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Surfaces.selected(scheme),
        borderRadius: BorderRadius.circular(Radii.xs),
      ),
      child: Text(text, style: styleOf(context), maxLines: 1),
    );
  }
}
