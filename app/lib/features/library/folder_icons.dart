import 'package:flutter/material.dart';

import '../../domain/folder.dart';

/// Glyphs for [Folder.iconKeys]; null (or an unknown key) is the plain folder.
const Map<String, IconData> folderIcons = {
  'book': Icons.menu_book_rounded,
  'school': Icons.school_rounded,
  'work': Icons.work_rounded,
  'science': Icons.science_rounded,
  'calculate': Icons.calculate_rounded,
  'palette': Icons.palette_rounded,
  'music': Icons.music_note_rounded,
  'sports': Icons.sports_soccer_rounded,
  'travel': Icons.flight_rounded,
  'home': Icons.home_rounded,
  'favorite': Icons.favorite_rounded,
  'star': Icons.star_rounded,
  'lightbulb': Icons.lightbulb_rounded,
  'code': Icons.code_rounded,
  'language': Icons.language_rounded,
  'receipt': Icons.receipt_long_rounded,
  'event': Icons.event_rounded,
  'pets': Icons.pets_rounded,
  'restaurant': Icons.restaurant_rounded,
};

/// Human-readable names for the icon picker's tooltips and semantics.
const Map<String, String> folderIconNames = {
  'book': 'Book',
  'school': 'School',
  'work': 'Work',
  'science': 'Science',
  'calculate': 'Maths',
  'palette': 'Art',
  'music': 'Music',
  'sports': 'Sports',
  'travel': 'Travel',
  'home': 'Home',
  'favorite': 'Heart',
  'star': 'Star',
  'lightbulb': 'Ideas',
  'code': 'Code',
  'language': 'Languages',
  'receipt': 'Receipts',
  'event': 'Events',
  'pets': 'Pets',
  'restaurant': 'Food',
};

/// The glyph for icon key [key] (null = the default folder icon).
IconData folderIconData(String? key) => folderIcons[key] ?? Icons.folder_rounded;

/// The glyph of [folder].
IconData iconOfFolder(Folder folder) => folderIconData(folder.icon);
