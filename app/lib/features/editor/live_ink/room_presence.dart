import 'package:flutter/material.dart';

import '../../../sync/live_rooms.dart';
import '../../../ui/app_theme.dart';

/// Who else has this notebook open right now (live sync's presence): a
/// small plate per other device with its initial, in the editor's bar
/// before the actions; nothing while the notebook is open here alone.
class RoomPresence extends StatelessWidget {
  const RoomPresence({super.key, required this.rooms, required this.room});

  final LiveRooms rooms;
  final String room;

  /// Plates shown at most; more are counted in the last one.
  static const maxShown = 3;

  /// Edge of a plate: a bar glyph with a little room around the letter.
  static const double plate = Glyphs.bar + Gaps.xs;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: rooms,
    builder: (context, _) {
      final others = rooms.othersIn(room);
      if (others.isEmpty) return const SizedBox.shrink();
      final names = [for (final m in others) m.name ?? 'Another device'];
      final shown = others.length > maxShown ? maxShown - 1 : others.length;
      final label = 'Also open on ${_list(names)}';
      return Tooltip(
        message: label,
        child: Semantics(
          label: label,
          excludeSemantics: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gaps.sm),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: Gaps.xs,
              children: [
                for (final name in names.take(shown)) _Plate(text: initialOf(name)),
                if (others.length > shown) _Plate(text: '+${others.length - shown}'),
              ],
            ),
          ),
        ),
      );
    },
  );

  /// The letter a device [name] shows as (its plate, its pointer's label).
  static String initialOf(String name) =>
      name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase();

  static String _list(List<String> names) => names.length == 1
      ? names.single
      : '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
}

/// One device's plate: its initial on the chrome, a hairline around it.
class _Plate extends StatelessWidget {
  const _Plate({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: RoomPresence.plate,
      height: RoomPresence.plate,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Surfaces.selected(scheme),
        borderRadius: BorderRadius.circular(Radii.xs),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurface),
        maxLines: 1,
      ),
    );
  }
}
