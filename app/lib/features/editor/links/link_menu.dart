import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../ui/menus.dart';

/// What the "Link…" menu offers.
enum LinkChoice { page, url, remove }

/// Shows the "Link…" menu under [anchor]: link to a page or a web address,
/// and with [canRemove] remove the existing link.
Future<LinkChoice?> showLinkMenu(
  BuildContext anchor, {
  bool canRemove = false,
}) => showContextMenuAt<LinkChoice>(
  anchor,
  items: [
    const MenuRow(value: LinkChoice.page, icon: Symbols.description_rounded, label: 'Link to page…'),
    const MenuRow(value: LinkChoice.url, icon: Symbols.public_rounded, label: 'Link to web address…'),
    if (canRemove) ...[
      const PopupMenuDivider(),
      const MenuRow(
        value: LinkChoice.remove,
        icon: Symbols.link_off_rounded,
        label: 'Remove link',
        destructive: true,
      ),
    ],
  ],
);
