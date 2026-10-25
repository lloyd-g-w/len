import '../../../data/app_preferences.dart';
import '../../../domain/preferences.dart';
import '../../../domain/stroke.dart';
import '../../../ink/tool_settings.dart';
import '../../../ui/color_picker/color_swatches.dart';

/// Gives the pen's, highlighter's and laser's quick slots the counts set in
/// Settings → Toolbar ([AppPreferences.slotCounts], their one home): slots
/// past the count go from the end, new ones get a colour not in the row yet
/// and a size a step above the last. The selected slot stays where it is
/// (or moves to the last one left). Tools already at their counts are left
/// alone (nothing is saved, nothing notified).
void applySlotCounts(ToolSettings tools, AppPreferences preferences) {
  for (final ink in ToolSettings.inks) {
    final counts = preferences.slotCounts(ink.isHighlighter ? SlotTool.highlighter : SlotTool.pen);
    final config = tools.configOf(ink);
    if (config.colors.length == counts.colors && config.widths.length == counts.sizes) continue;
    tools.updateConfig(ink, (c) => resizeInk(c, ink, counts));
  }
  final counts = preferences.slotCounts(SlotTool.laser);
  final laser = tools.laser;
  if (laser.colors.length != counts.colors || laser.sizes.length != counts.sizes) {
    tools.laser = resizeLaser(laser, counts);
  }
}

/// [config] of [ink] with [counts] colour and width slots.
PenConfig resizeInk(PenConfig config, InkTool ink, SlotCounts counts) {
  final palette = ink.isHighlighter ? ColorSwatches.highlighter : ColorSwatches.palette;
  final d = PenDefaults.of(ink);
  var c = config;
  while (c.colors.length > counts.colors) {
    c = c.removeColor(c.colors.length - 1);
  }
  while (c.colors.length < counts.colors) {
    c = c.copyWith(colors: [...c.colors, _unused(palette, c.colors)]);
  }
  while (c.widths.length > counts.sizes) {
    c = c.removeWidth(c.widths.length - 1);
  }
  while (c.widths.length < counts.sizes) {
    final up = c.widths.last * 1.5;
    c = c.copyWith(widths: [...c.widths, d.clampWidth(up <= d.maxWidth ? up : c.widths.last)]);
  }
  return c;
}

/// [config] with [counts] colour and size slots.
LaserConfig resizeLaser(LaserConfig config, SlotCounts counts) {
  var c = config;
  while (c.colors.length > counts.colors) {
    c = c.removeColor(c.colors.length - 1);
  }
  while (c.colors.length < counts.colors) {
    c = c.copyWith(colors: [...c.colors, _unused(LaserConfig.presets, c.colors)]);
  }
  while (c.sizes.length > counts.sizes) {
    c = c.removeSize(c.sizes.length - 1);
  }
  while (c.sizes.length < counts.sizes) {
    final up = (c.sizes.last * 1.5).roundToDouble();
    c = c.copyWith(sizes: [...c.sizes, up.clamp(LaserConfig.minSize, LaserConfig.maxSize)]);
  }
  return c;
}

/// A colour of [palette] not in [used] yet (not white: it vanishes on
/// paper), else the palette's first.
int _unused(List<int> palette, List<int> used) =>
    palette.firstWhere((c) => !used.contains(c) && c != 0xFFFFFFFF, orElse: () => palette.first);
