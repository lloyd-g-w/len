# Len: UI overhaul spec

Status: phases 1–5 implemented (see §6 *Progress*); phases 6–8 are the plan.
The cuts this spec assumes are in [`SIMPLIFY.md`](SIMPLIFY.md); where it conflicts with `UX_AUDIT.md`, this spec wins.

**Goal.** Paper first, with chrome that recedes (GoodNotes 6, Notewise, Apple Notes): one
slim bar, one home per control, nothing parked over the page. Principles:

1. The page is the brightest thing on screen. Chrome is neutral and flat, with one accent.
2. Each command has one home. Shortcuts and context menus are extra routes, never the only one.
3. Chrome shows only while needed: indicators peek while the view moves; no permanent pills.
4. Defaults beat settings: a choice that is rarely changed is decided in code.

## 1. Design language

> **Superseded by [`DESIGN.md`](DESIGN.md)** (Swiss minimal: Sofia Sans, ruling blue,
> Material Symbols Sharp, flat chrome with hairlines). Kept for history; where they differ,
> DESIGN.md wins.

### 1.1 Spacing, radii, surfaces, elevation

**Spacing.** Keep `Gaps` (2, 4, 8, 12, 16, 24, 32, 48). In bars, controls sit 4 apart and
groups 12 apart; a 1-px divider goes only between the bar's clusters (§2.1).

**Radii.** Replace the `Radii` set in `ui/app_theme.dart`, deleting `cover`, `control`,
`card`, `toolbar` and `sheet`:

| token | dp | use |
|---|---|---|
| `xs` | 6 | chips, badges, the plate behind the selected tool |
| `sm` | 10 | buttons, fields, quick slots, covers, page thumbnails |
| `md` | 14 | menus, popovers, floating palette, snack bars |
| `lg` | 20 | dialogs, bottom sheets |
| `pill` | 999 | page indicator, zoom pill, focus puck |

**Surfaces and elevation.** Shadows come from `Shadows` only: no Material `elevation`,
and no outlines in light mode.

| role | light / dark | elevation | used for |
|---|---|---|---|
| `canvasBackdrop` | `#EDEDEA` / `#0E0E10` | – | around pages |
| `chrome` | `surface` | 0, an `outlineVariant` hairline on the edge facing content | docked bars |
| `raised` | `#FFFFFF` / `#26262B` | 1: `Shadows.low` (dark: 1-px `outlineVariant` border instead) | palette, pills, selection menu |
| `overlay` | as `raised` | 2: `Shadows.high`; dialogs over a 32 % / 56 % black scrim | popovers, menus, dialogs, sheets |

Rewrite `ui/floating_panel.dart` as `raised`, radius `md`. Today it is
`Material(elevation: 3)` and shows in the goldens as a grey outlined pill.

### 1.2 Typography

Use **Inter**, already bundled, for all UI on every platform (`fontFamily: 'Inter'` in
`AppTheme._build`). Today Android uses Roboto while the web and Linux use whatever they
find. `_textTheme` keeps six styles; drop display, headline and the 700-weight sidebar
brand.

| role | slot | size/line | weight | use |
|---|---|---|---|---|
| Title | `titleLarge` | 20/26 | 600, −0.2 | screen titles |
| Heading | `titleMedium` | 16/22 | 600 | dialog titles, notebook title in the bar |
| Body | `bodyMedium` | 14/20 | 400 | rows, descriptions |
| Label | `labelLarge` | 14/20 | 500 | buttons, menu rows, tabs |
| Caption | `bodySmall` | 12/16 | 400, `onSurfaceVariant` | card dates, hints |
| Overline | `labelSmall` | 11/14 | 600, +0.3 | `SectionLabel` (sentence case) |

Page numbers, times and zoom percentages use `FontFeature.tabularFigures()`.

### 1.3 Colour

- **Accent:** fixed ink blue `#3B5BDB` (the picker goes), only for primary buttons, focus
  rings, selection handles, links, switches, progress and the selected sidebar row.
- **Selected tool:** an `xs` plate of `onSurface` at 8 % (12 % dark), replacing the
  tonal `secondaryContainer` disc in `ToolButton`, `SlotButton` and `ToolSwitcherButton`.
- **Ink is never themed:** slots show the real colour (with the `ColorDot` hairline).
  Destructive commands are `error`, last in menus, and red in their confirmation.
- **Dark mode:** surfaces as today. Paper keeps its colour, and canvas hints and handles
  follow the paper. Text on `raised` is at least 4.5:1.

### 1.4 Icons and touch targets

Use Material Symbols **Rounded**, weight 300, fill 0 (`material_symbols_icons`: an icon
font, works on all four platforms, tree-shaken). Active and selected states use fill 1;
filled `Icons.*_rounded` are no longer mixed in. Redraw `EraserIcon`, `ShapeGlyph` and
`tools/tool_icons.dart` with 1.5-px strokes.

| where | glyph | visual | hit area |
|---|---|---|---|
| bars, toolbar | 20 | 40 × 40 | 48 on touch, 40 with a pointer |
| menu rows | 18 | – | 44 high (48 on touch) |
| quick slots | 22 dot | 36 × 36 | 44 on touch |
| empty states | 40 | – | – |

`Targets.of` decides by input, not width: touch-first means Android, or a coarse pointer
on the web.

### 1.5 Motion

Retune `Motion`: `fast` 120, `medium` 200, `slow` 300, `travel` 420 ms.

- **Chrome in/out:** fade (`medium`) plus an 8-px slide toward its edge, never a whole
  bar's height. **Popovers and menus:** fade plus scale from 0.96 at the anchor (`fast`).
- **Tools:** one plate slides between tools (`fast`); the strip cross-fades. **Taps:**
  `NoSplash` plus an `onSurface` 8 % / 12 % overlay instead of `InkSparkle`.
- **Reduced motion:** fades only, as `NotebookOpenRoute` already does.

## 2. Editor (top priority)

**Leaving the chrome:** the page pill; the canvas fit / minimap cluster; the toolbar's
palm, tune and `+` buttons, tool names, favourites and edit mode; the Select PDF text
tool (long press does it); the top bar's bookmark, image, search, export, focus and
split buttons; the sticker panel; Present (merged into focus mode, §2.7).

### 2.1 Toolbar position: Docked (default) or Floating

`ToolbarPlacement` becomes `{docked, floating}`. Delete `auto`, `top`, `bottom`,
`resolvePlacement`, `ChromeMetrics.topToolbarWidth` and `roomyBarWidth`. The choice
lives in ⋯ → View → Toolbar and in Settings → Writing.

- **Docked:** one 52-dp bar when everything fits (measured, as `oneRowWidth` does now);
  else a 48-dp tool row attached under it (no gap or shadow, one hairline under the
  block). Panes under 600 dp put the tool row at the bottom, above the gesture inset.
- **Floating:** a `raised` palette with a 4 × 20 grip. Released within 48 dp of an edge,
  it snaps to that edge's middle (horizontal top/bottom, vertical left/right); elsewhere
  it stays put. Double-tap the grip to collapse it to the puck (§2.7). Saved in
  `toolbarFloat` plus the snapped edge; the top bar keeps nav and actions.

**Bar order** (fixed): nav (← back, ▦ pages, title with the folder as a caption; tap to
rename) · tools (Pen, Highlighter, Eraser, Lasso, Shapes, Text, Laser, Insert ⊕) · the
active tool's quick slots · actions (🎙, ↶ ↷, ⋯). The title truncates first, down to
120 dp; below that the bar becomes two rows.

```
Wide docked: one bar (landscape tablets ≈ 1040 dp+, desktops)
┌──────────────────────────────────────────────────────────────────────────────┐
│ ← ▦ Biology lecture   │ ✎ ▭ ◇ ⌒ △ T ✦ ⊕ │ ● ● ●  · • ● │ 🎙▾  ↶  ↷  ⋯ │
│     Science           │                  │                │              │
└──────────────────────────────────────────────────────────────────────────────┘
Medium docked: two rows (portrait tablets 600–1039 dp, split panes)
┌──────────────────────────────────────────────────────────┐
│ ←  ▦  Biology lecture                     🎙▾  ↶  ↷  ⋯   │ 52
│        ✎  ▭  ◇  ⌒  △  T  ✦  ⊕  │  ● ● ●   · • ●       │ 48, centred
└──────────────────────────────────────────────────────────┘
│                         page                ╭────────╮   │
│                                             │ 3 / 12 │   │ peeks while scrolling
Phone (< 600 dp)                    Floating (any width)
┌──────────────────────────────┐    ╭───────────────────────────────────────╮
│ ←  Biology lecture  ↶  ↷  ⋯  │    │ ⋮⋮ ✎ ▭ ◇ ⌒ △ T ✦ ⊕ │ ● ● ● │ · • ● │
├──────────────────────────────┤    ╰───────────────────────────────────────╯
│            page              │    snapped left/right: the same order as a
│          ╭────────╮          │    column, slots stacked under the tools
│          │ 3 / 12 │          │
├──────────────────────────────┤
│ [✎▾] │ ● ● ● │ · • ●         │ 56 + gesture inset
└──────────────────────────────┘
```

On phones, `[✎▾]` (`ToolSwitcherButton`) opens a 4 × 2 grid of the seven tools plus
Insert, with no palm toggle and no favourites. Audio, search, export and open notebooks
go in ⋯.

**Files:** rewrite `editor_toolbar.dart` (one layout per axis, no `showLabels`);
`chrome/toolbar_slot.dart` gains snapping and a vertical axis; `chrome/editor_top_bar.dart`
gets a tool-row slot and loses `roomy`; in `ChromeLayout` the docked row joins the top
extent, `navigatorAboveToolbar` goes and a floating palette covers no edge;
`toolbar_buttons.dart` loses `SettingsButton` and `PalmRejectionButton`. Delete
`toolbar/{toolbar_editor,toolbar_config,favourite_pens,reorder_start_listener}.dart` and
the `toolbarLabels` and `toolbarLayout` preferences.

### 2.2 Tools, quick slots, options popover

**Insert ⊕** is a button, not a tool. Its menu: Image…, Take photo (Android), Pages from
PDF… and Page with template… (the last two in paged notebooks). It replaces the top-bar
button in `images/image_entry_points.dart`. Drop the `selectText` descriptor from
`editor_tools.dart`.

| tool | context strip | options popover |
|---|---|---|
| Pen | colour slots, then width slots (3 by default, up to 5) | colour, width, slots, Feel (pressure, stabiliser, tapered ends) |
| Highlighter | as Pen | colour, width, slots, opacity |
| Eraser | three size slots (· • ●) | Whole stroke / Partial, size, erase highlighter only |
| Lasso | none (the tools stay centred, so nothing jumps) | none |
| Shapes | the pen's slots (the Shapes button shows the kind; its popover picks it) | kinds, "Pause to snap shapes" (moved from the pen) |
| Text | none | font, size, colour for new boxes |
| Laser | three colour slots (red, green, blue) | colours, Trail / Dot, trail Short 0.6 s / Long 1.5 s |

**Slots** (`pen/ink_slots.dart`, `pen/slot_button.dart`): colour slots are 22-dp dots in
36-dp cells; width slots are dots at real size (4–20 dp) in the same cells, without the
recessed track. The selected slot gets a 2-px `onSurface` ring with a 2-px gap. Tap to
select; tap the selected slot, long-press or right-click to open the popover on it.

**Options popover.** Tapping the active tool again opens it, for every tool.
`showAdaptivePopover`: anchored to the tool and 320 dp wide; a bottom sheet on phones.
Edits apply live to the selected slot.

```
┌ Pen ──────────────────────── Reset ┐
│  ~~~~~ live stroke preview ~~~~~    │
│  Colour  ● ● ● ● ● ● ● ● ● ● ● ●    │ 12 presets
│          ● ● ● ●  recent  [Custom]  │ HSV picker opens inline
│  Width   ──────●───────  0.8 mm     │
│  Slots   ● ● ●   [+] [−]            │ add or remove quick slots
│  ▸ Feel                             │ collapsed by default
└─────────────────────────────────────┘
```

One `ToolOptionsPopover` with a section per tool merges `pen/pen_options_panel.dart`,
`pen/eraser_options_panel.dart`, `tools/shape_options_panel.dart`,
`tools/text_options_panel.dart`, `pen/slot_editors.dart` and `tools/colour_sheet.dart`.
Saved favourite colours (`ToolSettings.favorites`) become an automatic row of the last 8
used. Laser options need `ToolSettings.laser` (`color`, `style`, `fade`), persisted like
`eraser`; `LaserPainter` and `Laser.lifetime` read it instead of their constants.

### 2.3 Undo/redo, audio, overflow menu

- **Undo/redo:** in the action cluster on every size and in both modes, and on the puck
  in focus mode. The two- and three-finger taps stay.
- **Audio:** one split button replaces `AudioBarButton`'s two. 🎙 records; ▾ opens the
  recordings popover (list, play, rename, export). While recording, it is the existing
  red time pill with pause and stop. On phones audio lives in ⋯, and the floating
  recorder controls stay.
- **⋯ menu:** rewrite `chrome/editor_more_menu.dart` and slim `EditorMenuActions` to
  match:

```
Search in notebook            Ctrl+F
Export…                       Ctrl+E (new)
────────
Page ▸      Add page after · Add page with template… · Duplicate page · Bookmark page ·
            Change template… · Save as template… · ── Delete page (red)   [paged]
Background…                                                          [canvas]
View ▸      Scroll pages / One page at a time · Fit width / Fit page / Automatic ·
            Toolbar: Docked / Floating · Focus mode  F11
Open in split view                                                   [≥ 900 dp]
────────
Draw with finger   [switch]                          [once a stylus has been seen]
Settings…
Phones add at the top: Record audio · Recordings… · Open notebooks (n)
```

**Leaving the menu:** Present, Stickers, Outline, Add page to outline, tags, Show tool
names, Customise toolbar, Add page before (the overview inserts anywhere), Rename (tap the
title), Go to page (tap the indicator), and the canvas Fit content / Actual size / Back to
start / overview entries (they move to the zoom pill).

### 2.4 Page navigation

- **Page indicator:** a "3 / 12" `pill` replaces `page_navigator.dart` and the phone
  special case in `chrome/peeking.dart`. Bottom-centre on phones, bottom-right elsewhere,
  12 dp above the bottom chrome. It peeks on every size (shows while pages move, fades
  after 1.5 s) and takes no room in `ChromeLayout.covered`. Tap: Go to page (number
  field and thumbnail strip). Long press: the overview.
- **Overview:** ▦ opens it (`documents/overview/`, tokens only). An All / Bookmarked /
  Outline filter (the PDF's outline) replaces the outline panel.
- **Adding pages:** the "Add page" footer, Insert ⊕ → Page with template…, ⋯ → Page →
  Add page after, and the overview's add tile. Single-page flow: swipe, ← / →, Page Up /
  Page Down.
- **Canvases:** the zoom pill (`canvas/zoom_indicator.dart`) peeks the same way. Tap it
  for 50 %, 100 %, 200 %, Fit content or Back to start. Delete `canvas_minimap.dart`,
  `minimap_painter.dart`, and the fit and overview buttons in `canvas/canvas_view.dart`.

### 2.5 Tabs

**Panes ≥ 600 dp:** the strip (`notebook_tab_strip.dart`, restyled) shows only with two
or more notebooks open: 36 dp high on `canvasBackdrop`, the active tab merging into the
bar (same `chrome` colour, no border), titles only (at most 200 dp), ✕ on hover and on
the active tab.

**Phones:** no tab UI. Opening a notebook replaces the current one; "Open notebooks" is in
⋯ while several are open. Remove `TabSwitcherButton` from the bar.

### 2.6 Selection menu and text format bar

- **Selection menu** (`tools/selection_menu.dart`, done): a `raised` pill above the selection:
  **Style** · Cut · Copy · Delete · ⋯. Style is one popover merging today's Colour and
  Style (colour, then width or pen for ink, font and size for text). ⋯ holds Duplicate,
  Paste, Convert to text, Link…, Crop and Bring to front / Send to back.
- **Text format bar** (`tools/text_format_bar.dart`, done): the same pill. Order: font ▾ ·
  size · B I U S · colour · highlight · lists ▾ · align · ✓, with Delete in a trailing ⋯.
  On phones it docks full width above the keyboard in two rows (font "Aa", size, lists,
  align, ⋯ over B I U S, colour, highlight, ✓), so every control shows; very narrow
  windows scroll each row.

### 2.7 Focus mode (absorbs presentation; F5 = focus mode with the laser)

```
┌──────────────────────────────────────────┐
│                                    ⤡     │ exit: 32 dp, 40 % opacity until hover or touch
│                  page                    │
│                                ╭──────╮  │
│                                │ ✎▾ ↶ │  │ the puck: active tool + undo
│                                ╰──────╯  │
└──────────────────────────────────────────┘
```

- **Chrome:** the bar and toolbar fade out (§1.5); the app goes immersive or full screen
  through `platform/fullscreen*`, as presentation does now.
- **Puck:** `chrome/focus_handle.dart` becomes `ToolPuck`. It sits where the toolbar was,
  can be dragged and snaps like the palette. ✎▾ opens the tool switcher with slots; ↶
  undoes. A two-finger long press hides it too: the "presenting" state.
- **Pages:** in single-page flow, ← / →, Space and swipes turn pages. Move
  `PresentationControls`' key handling here, then delete `present/`.

### 2.8 Split view

- Open from ⋯ → Open in split view or a tab's menu; while split, ⋯ also has Swap panes
  and Close split view. Delete the top-bar `SplitViewButton`. Tools are always linked
  (`linkTools` always true; its menu item goes).
- Only the pane last touched shows full chrome; the other's toolbar collapses to the
  puck and its bar dims to 60 %. The first pointer or pen contact moves focus (`fast`
  cross-fade). Each pane lays out by its own width; keep `SplitView.fits` (≥ 900 × 560).

```
┌──────────────── focused ─────────────┬──────────── other (dimmed) ───────┐
│ ←  ▦  Biology          🎙▾ ↶ ↷ ⋯     │ ✕  Lecture.pdf        ↶ ↷ ⋯      │
│   ✎ ▭ ◇ ⌒ △ T ✦ ⊕ │ ● ● ● │ · • ●    │                                  │
│              page                    ┃        pdf page       ╭──────╮   │
│                                      ┃                       │ ✎▾ ↶ │   │
└──────────────────────────────────────┴───────────────────────┴──────┴───┘
```

### 2.9 Adapting to width (the pane's, not the window's)

| pane width | top chrome | tools | audio / search / export | page indicator |
|---|---|---|---|---|
| < 600 | 52 bar: ← title ↶ ↷ ⋯ | bottom row: switcher + slots | ⋯ | bottom-centre |
| 600 to one-row fit | 52 bar + 48 tool row | centred row under the bar | 🎙 in bar; ⋯ | bottom-right |
| one-row fit (≈ 1040+) | single 52 bar | inside the bar | 🎙 in bar; ⋯ | bottom-right |
| floating | 52 bar (nav + actions) | palette, edge snapping | 🎙 in bar; ⋯ | bottom-right |

## 3. Library

```
Tablet / desktop (≥ 840)                                       Phone (< 840)
┌──────────────┬─────────────────────────────────────────┐    ┌──────────────────────┐
│ Len          │ Library          [🔍 Search      ]  ⊕▾ ⇅ │    │ ☰  Library      🔍  ⇅│
│ ▣ Library    │ ▭ Maths   ▭ Work   ▭ Reading             │    │ ▭ Maths   ▭ Work     │
│ ☆ Favourites │ ┌────┐ ┌────┐ ┌────┐ ┌────┐ ┌────┐       │    │ ┌────┐ ┌────┐        │
│ 🗑 Trash      │ │ +  │ │    │ │    │ │    │ │    │       │    │ │    │ │    │        │
│ Folders    + │ │New │ │    │ │    │ │    │ │    │       │    │ └────┘ └────┘        │
│  ▸ Maths     │ └────┘ └────┘ └────┘ └────┘ └────┘       │    │ Biology  Ideas       │
│  ▸ Work      │        Biology Ideas  Chem   …           │    │ Today·12 Canvas ╭──╮ │
│ ⟳ Synced 2m  │        Today·12 Canvas 3 Oct             │    │                 │ +│ │
│ ⚙ Settings   │                                         │    │                 ╰──╯ │
└──────────────┴─────────────────────────────────────────┘    └──────────────────────┘
```

- **Navigation** (`library_screen.dart`, `library_sidebar.dart`): from 840 dp a 248-dp
  sidebar on `chrome` with a hairline (Library, Favourites, Trash, folder tree; sync
  status and Settings at the bottom). Below 840 dp the same content is a modal `Drawer`
  from ☰. Remove the bottom `NavigationBar` and the Tags section; `Breakpoints.medium`
  goes from 720 to 840.
- **Header** (`library_header.dart`): the title (folder or breadcrumbs) with a caption
  ("12 notebooks"). On the right: search (a 280-dp field when wide; on phones a 🔍 that
  expands over the title); ⊕▾ (wide only: New notebook, New canvas, Import PDF…, New
  folder); ⇅ View (Sort: Last edited / Created / Name; Grid / List; Select…). The
  separate select, sort and layout buttons go; Select… is also in each card's menu.
- **Grid** (`library_content.dart`, `notebook_card.dart`): covers at 0.72 aspect, radius
  `sm`, `raised` shadow, about 150 dp with columns stretched to the width. Below: a
  two-line title (`bodyMedium` w500) and a caption ("Today · 12 pages", "Canvas"). ⋯ by
  the title shows on hover, and always on touch. No `TagDots`. Folders are a wrapping
  row of compact tiles above the notebooks (a 36-dp glyph in the folder colour, name).
- **New notebook** (`new_notebook_sheet.dart`): opened from the New… tile (wide), the FAB
  (phones only; hidden while an empty state shows its own button), ⊕▾ or Ctrl+N. One
  column: title; Notebook / Canvas; Paper (6 most recent + "All templates…" →
  `TemplateChooser`); Cover (one row of 10 colours); size and orientation; Create. The
  preview sits beside the form when wide and is a 120-dp strip on phones. The Cover/Paper
  tabs and the pattern gallery go.
- **Search results** (`library_search_results.dart`): keep the grouping. Rows become flat
  items separated by hairlines, not tinted cards. Page chips are `xs` on
  `surfaceContainerHigh`.

## 4. Settings

One column, at most 640 dp, centred; the two-pane layout and `SettingsSection.untitled` go.

```
General       Theme                 System · Light · Dark   (segmented, no previews)
Writing       Draw with             Automatic (default) · Stylus · Both
              Side button           Erases · Selects · Nothing
              Tap to undo and redo  one switch (two fingers undo, three redo)
              Toolbar               Docked · Floating
Handwriting   Search handwriting    switch                (Android only)
              Language              Device language ▸
Sync          server, token, Sync now, status (as now, restyled)
Storage       (web only)
About         version · licences
```

**Removed:** the accent colour, the theme previews (`theme_choice.dart` becomes a
segmented button), the separate Stylus / Gestures / Editor sections, the language-model
"Delete…" row, and Ink Lab in release builds (`about_settings.dart` opens it only with
`kDebugMode` or `--dart-define=INKLAB=true`).

**Rows** are `ListTile`s with an 18-dp leading icon, a Body title and a Caption subtitle;
controls trail on wide screens and go below the text on phones.

## 5. Sheets, popovers, menus and dialogs: one system

Every surface uses exactly one of five primitives. `features/` may not use
`SimpleDialog`, raw `showModalBottomSheet`, `AlertDialog` or `PopupMenuButton`.

| primitive | API (`ui/`) | for | phone | wide |
|---|---|---|---|---|
| Menu | `ChromeMenuAnchor`, `showContextMenuAt`, `MenuRow` | commands | anchored | anchored |
| Popover | `showAdaptivePopover` | live settings: tool options, recordings, zoom, link pickers | sheet with handle | anchored, 320 dp |
| Task sheet | `showDialogOrSheet` | a task with a commit: new notebook, export, templates, move, folder | full-height sheet | dialog 560 dp (880 two-column) |
| Confirm | `confirmAction`, `AppDialog` | one question, or progress | dialog 400 dp | dialog 400 dp |
| Message | `showMessage` | feedback, undo | floating snack bar | snack bar, at most 560 dp |

- **Headers:** a left-aligned `titleMedium` title; task sheets add ✕. A tinted icon
  appears only in destructive and progress Confirms.
- **Footers** (task sheets, Confirms): Cancel as a text button plus one filled primary,
  right-aligned. On phones they are full width and stacked, primary on top, pinned while
  the body scrolls.
- **Popovers** have no buttons: changes apply live, and outside taps or Esc close them.
- **Menus:** rows 44 dp (48 on touch), 18-dp icons with the leading slot always
  reserved, shortcut hints only where a keyboard is likely, submenus that drill in on
  phones, 8 dp from the screen edges.
- **Moving onto the system:** done — `features/` has no `PopupMenuButton`,
  raw `showModalBottomSheet`, `AlertDialog` or `SimpleDialog` left (menus use
  `MenuIconButton` / `MenuButton` with `MenuRow`s, which can lead with a
  swatch and show a label in its own style). The recordings list (`audio/ui/recordings_sheet.dart`)
  becomes a popover; the PDF outline sheet (`pdf/pdf_outline_sheet.dart`) goes (it
  becomes the overview's Outline filter); convert to text becomes a task sheet with Try
  again on error.

## 6. Implementation order

Each phase ships on its own branch with `flutter analyze` clean and tests green. It
regenerates and reviews the goldens it touches (`flutter test --update-goldens <files>`)
and re-renders the affected `test/screenshots/` suites (phone, tablet, desktop; light,
dark; 1.3× text).

| # | phase | scope | goldens / suites |
|---|---|---|---|
| 1 | Cuts | SIMPLIFY remove/merge rows: stickers, tags, minimap, toolbar customisation, favourite pens, tool names, Select-text tool, user outline, accent, folder icons, cover patterns; Present → focus; Ink Lab gated | delete `sticker_panel`, `outline_panel`, `canvas_minimap` |
| 2 | Tokens | Inter and type scale, `Radii`, surfaces, `Shadows` levels, `FloatingPanel`, no sparkle, Material Symbols, `Targets` by input | all (they change across the board) |
| 3 | Docked chrome | bar clusters, joined or second tool row, phone bottom row, new ⋯, Insert ⊕, audio split button, `ToolbarPlacement {docked, floating}` | `editor_*`, `audio_*`, `content_*`, `text_*`, `search_editor*`; suites `toolbar_`, `editor_`, `workspace_` |
| 4 | Slots and popover | neutral plate, slots, `ToolOptionsPopover`, recent colours, `ToolSettings.laser` | suite `toolbar_`; `ink_*` if previews change |
| 5 | Navigation | peeking page indicator and zoom pill, Go to page, overview filter, tab strip, no phone tabs | `editor_single`, `editor_continuous`, `page_overview`, `pdf_outline` |
| 6 | Floating, focus, split | edge snapping, vertical axis, `ToolPuck`, immersive focus with page keys, split focus and dimming | suite `workspace_`; new `focus_puck`, `toolbar_floating_h`, `toolbar_floating_v` |
| 7 | Library | sidebar or drawer, header, ⇅ menu, folder row, cards, one-column new-notebook sheet | `search_library*`; suites `library_`, `flows_`, `organise_` |
| 8 | Settings and sweep | single-column settings; grep `features/` for `showModalBottomSheet`, `AlertDialog`, `SimpleDialog`, `PopupMenuButton` until none are left; update `UX_AUDIT.md`, `ARCHITECTURE.md`, `ROADMAP.md` | suite `app_surfaces*` |

Phase 1 comes first because every later phase then gets smaller.

**Progress.** Phases 1 and 2 are in main. Phases 3 and 4 are done on
`feat/toolbar` (ARCHITECTURE *Toolbar*), with these deviations:

- Quick colour and width slots stay **1–6 each** (3 + 3 by default; user
  decision), set with − n + in the popover rather than [+] [−].
- The popover's palette is the existing 20-colour `ColorSwatches.palette`
  (two rows of ten), then up to six recent colours and Custom.
- The pen and highlighter panels are hosted unchanged under *Feel* (so the
  pen's end style from feat/pen5 merges in): "Hold to snap shapes" therefore
  shows in the pen's Feel as well as in the Shapes popover, and the eraser
  keeps *Auto-deselect*. The laser's trail length is a slider (0.3–3 s), not
  Short / Long; `ToolSettings.laser` already existed.
- The lasso's popover explains the tool instead of being empty, so tapping
  any active tool behaves the same.
- Outline: now the overview's All / Bookmarked / Outline filter (phase 5);
  the user outline is kept (SIMPLIFY lead decision) inside it, with the
  PDFs' outlines. ⋯ → *Outline* stays as a route that opens the overview on
  that filter (phones have no ▦), and *Add page to outline…* stays in Page ▸.
- View ▸ lists *Toolbar docked* / *Toolbar floating* as two choices rather than
  a nested menu. Audio's ▾ shows once the notebook has recordings (as before).
- The phone bar's tab switcher button went with this phase (no room in
  `← title ↶ ↷ ⋯`); *Open notebooks (n)* is in ⋯.
- Phase 5 (navigation) is done: the peeking page indicator, Go to page with
  a thumbnail strip, the overview's All / Bookmarked / Outline filter.
- Phase 6 is done (goldens `toolbar_floating_h`, `toolbar_floating_v`,
  `focus_puck`): the floating palette snaps to edges and runs down
  the sides (`ToolbarSlot.snap`, `ToolbarAxis`); the snapped edge is
  implied by `toolbarFloat` (x of 0 or 1 is a side). Focus mode shows the
  `ToolPuck` (active tool ▾ and undo; dragged and snapped like the palette,
  remembered in `puckFloat`) and a 32-dp exit button at 40 % until hovered
  or touched. In split view the pane used last (first pointer contact or
  keyboard focus) has full chrome; the other's bar and toolbar recede to
  60 % (deviation: they don't collapse to the puck, which would re-lay out
  the page each time focus moves). A two-finger long press in focus mode hides the puck and the exit button
  too (presenting; again to bring them back; F11 / Esc still leave).

- Phases 7 and 8 checked against §3–§5 (library and settings screenshot
  suites, all sizes): sidebar / drawer, header with caption, search, ⊕▾ and
  ⇅, folder tiles, 0.72 covers, the one-column new-notebook sheet (the paper
  row now fits the wide form), single-column settings; `features/` has no
  `showModalBottomSheet`, `AlertDialog`, `SimpleDialog` or
  `PopupMenuButton` left.
