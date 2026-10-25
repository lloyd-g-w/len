# Len: simplification inventory

These are the user-facing features and settings, taken from the code (`app/lib/features`,
`app/lib/ui`, `domain/preferences.dart`, `data/app_preferences.dart`,
`ink/tool_settings.dart`). Each one gets a verdict that [`REDESIGN.md`](REDESIGN.md)
builds on. The app is pre-release, so removals delete code and data outright, with no
migrations kept (CONVENTIONS).

**Verdicts:**

- **Keep:** as it is (restyled by REDESIGN).
- **Hide:** keep the feature, but move it to ⋯, a popover or Settings.
- **Merge:** fold it into another feature.
- **Remove:** delete the code, preference, data and tests.
- **Default:** turn the setting into a fixed, good default.

**Status:** ✅ before a verdict means it is done in main (rounds 1–9; checked against the
code in round 9's follow-ups). Rows without one are kept as they are, or still open.

**Effort:**

- **S:** under half a day, local to the UI.
- **M:** touches data, sync collections or several features.
- **L:** a cross-cutting change.

Parity floor (never cut): ink, highlighter, eraser, lasso, shapes, text, images, PDF
import / annotate / export, templates and paper, search, folders, sync, audio, infinite
canvas.

## Editor: tools and toolbar

| # | Feature | Verdict | Reason | Files | Effort |
|---|---|---|---|---|---|
| 1 | Pen, Highlighter, Eraser (whole / partial, size, highlighter only), Lasso | Keep | Parity core | `editor_tools.dart`, `pen/*`, `ink/tools/*` | – |
| 2 | Shapes tool (7 kinds) + draw-and-hold snap | ✅ Keep | Parity; the "Hold to snap" switch moves from the pen popover to the Shapes popover | `tools/shape_options_panel.dart`, `pen/pen_options_panel.dart` | S |
| 3 | Text tool, rich text, lists, checklists | Keep | Parity | `tools/text/*`, `tools/text_format_bar.dart` | – |
| 4 | Six bundled fonts (Inter, Nunito, Lora, JetBrains Mono, Caveat, Kalam) | ✅ Remove Nunito and Kalam | Two sans and two handwriting fonts overlap; this cuts bundle and web weight | `pubspec.yaml`, `assets/fonts`, `domain/text/*` font list, `tools/text/text_style_menus.dart` | S |
| 5 | Laser pointer | ✅ Keep, add options | The user wants it kept and customisable: colour slots, Trail / Dot, trail length | `editor_tools.dart`, `ink/tools/laser.dart`, `ink/render/laser_painter.dart`, `ink/tool_settings.dart` | M |
| 6 | Select PDF text tool (X) | ✅ Merge into long press / right-click on PDF text | It is a second selection tool next to the lasso, and the long press already works | `editor_tools.dart` (`selectText`), `pdf/pdf_text_tool.dart`, `ToolSettings.selectTextAvailable` | S |
| 7 | Palm-rejection button in the toolbar | ✅ Hide (⋯ "Draw with finger" + Settings) | `stylusOnly` is already automatic (null → on at the first stylus contact) | `toolbar_buttons.dart` `PalmRejectionButton`, `tool_switcher.dart` | S |
| 8 | Tool settings (tune) button | ✅ Remove | Tapping the active tool opens the popover, so this is a duplicate | `toolbar_buttons.dart` `SettingsButton` | S |
| 9 | Customise toolbar (reorder, hide tools, edit mode) | ✅ Remove | Complexity for 7 tools; a fixed order is learnable and makes layouts predictable | `toolbar/toolbar_editor.dart`, `toolbar/toolbar_config.dart`, `toolbar/reorder_start_listener.dart`, `AppPreferences.toolbarLayout` | S |
| 10 | Favourite pens (up to 8) | ✅ Remove | Duplicates the quick colour and width slots | `toolbar/favourite_pens.dart`, `ToolSettings.usePreset`, `tool_switcher.dart` | S |
| 11 | Show tool names | ✅ Remove | The glyphs are standard, and tooltips and screen readers name them | `toolbar_buttons.dart`, `AppPreferences.toolbarLabels`, `editor_more_menu.dart` | S |
| 12 | Toolbar placement auto / top / bottom / floating | ✅ Merge → Docked / Floating | Four options with an "auto" nobody understands; docked adapts by width | `domain/preferences.dart`, `chrome/toolbar_slot.dart`, `chrome/chrome_metrics.dart`, `settings/editor_settings.dart` | M |
| 13 | Quick colour and width slots (1–6, `+` in the bar) | ✅ Keep; max 5; `+` moves to the popover | Core GoodNotes / Notewise speed; the `+` cluttered the bar | `pen/ink_slots.dart`, `pen/ink_strip.dart`, `pen/slot_button.dart` | S |
| 14 | Saved favourite colours in the colour picker | ✅ Merge → automatic "Recent" row | Saving colours by hand is a chore; recent colours cover it | `ToolSettings.favorites`, `pen/slot_editors.dart`, `tools/colour_sheet.dart`, `ui/color_picker/*` | S |
| 15 | Pen feel (pressure, stabiliser, tapered ends), highlighter opacity | ✅ Keep in the popover, with Feel collapsed | Stored per stroke and valued by stylus users | `pen/pen_options_panel.dart` | – |
| 16 | Stickers (built-in, user, panel, save selection as sticker) | ✅ Remove | Built-ins duplicate shapes; reuse is covered by copy and paste across notebooks; it adds a synced collection | `features/stickers/*`, `editor/stickers/*`, `data/sticker_repository.dart`, `data/sticker_codec.dart`, `sync/sync_engine.dart`, `SYNC_PROTOCOL.md`, `test/stickers_test.dart` | M |
| 17 | Images (file, camera, clipboard, drop, crop, order) | ✅ Keep; the entry point moves to toolbar Insert ⊕ | Parity | `images/*` | S |
| 18 | Links (lasso → page or web, planner links, link tint) | ✅ Keep; "Link…" goes to the selection More menu | Planners depend on them | `links/*` | – |
| 19 | Convert handwriting to text (lasso) | ✅ Keep, in selection More | Valuable on Android | `recognition/convert_to_text_dialog.dart` | – |
| 20 | Selection menu: Colour and Style as two actions | ✅ Merge → one "Style" popover | Two popovers that edit the same thing | `tools/selection_menu.dart`, `tools/selection_style_panel.dart` | S |
| 21 | Bring to front / send to back, duplicate, paste in the selection bar | ✅ Hide in selection More (in the bar's overflow; arranging only where items overlap) | Rarely used; they made the bar overflow on phones | `tools/selection_menu.dart` | S |

## Editor: chrome and navigation

| # | Feature | Verdict | Reason | Files | Effort |
|---|---|---|---|---|---|
| 22 | Top-bar buttons: bookmark, insert image, search, export, focus, split | ✅ Hide (⋯, Page ▸, Insert ⊕, shortcuts) | The bar keeps nav, tools, audio, undo and ⋯ only | `chrome/editor_top_bar.dart`, `chrome/editor_more_menu.dart` | S |
| 23 | Page navigator pill (‹ n/m › + ▾) | ✅ Merge → peeking page indicator (tap: go to page) | A permanent pill over the page; its buttons duplicate scrolling, the overview and Add page | `page_navigator.dart`, `chrome/peeking.dart`, `chrome/editor_chrome.dart` | S |
| 24 | Go to page… menu item | ✅ Merge into the page indicator tap | One home | `editor_more_menu.dart` | S |
| 25 | Add page before | ✅ Remove (the overview inserts anywhere) | Rare; "after" plus the overview cover it | `editor_more_menu.dart`, `document/page_actions.dart` | S |
| 26 | Page layout (continuous / single), page zoom (auto / width / page) | ✅ Hide, merged into ⋯ → View | Both are view options with one home | `editor_more_menu.dart`, `document/page_fit.dart` | S |
| 27 | Save page as template, change template, duplicate page | ✅ Keep in ⋯ → Page (the one page menu, R9-3) | Parity, but not top-level | `editor_more_menu.dart` | – |
| 28 | Bookmarks | Keep (Page ▸, overview, canvas menu) | Cheap and expected | `documents/overview/*` | – |
| 29 | Outline: user entries, "Add page to outline", outline panel | ✅ Merge: PDF outline + bookmarks become filters in the overview; remove user entries (lead decision: user entries kept, in the overview's Outline filter) | Bookmarks already mark pages; a third navigation panel is too much | `outline/*`, `data/outline_repository.dart`, `pdf/pdf_outline_sheet.dart`, sync engine, `test/outline_ui_test.dart` | M |
| 30 | Tabs (up to 8, tab strip, Ctrl+Tab) | ✅ Keep on ≥ 600 dp; Hide on phones (no switcher button) | GoodNotes parity on tablets; noise on phones | `tabs/notebook_tab_strip.dart`, `tabs/tab_switcher.dart`, `chrome/editor_top_bar.dart` | S |
| 31 | Split view | ✅ Hide (⋯ and the tab menu, not the top bar) | A power feature (PDF beside notes); keep, but out of the way | `split/split_view_button.dart`, `chrome/editor_top_bar.dart` | S |
| 32 | Split "Same tools in both panes" | ✅ Default (always linked) | Two tool states confuse; one toolbar shows at a time | `split/split_controller.dart`, `OpenNotebooks.linkTools`, `ToolSettings.adopt` | S |
| 33 | Presentation mode (F5, controls bar) | ✅ Merge into focus mode (+ laser, page keys) | The same thing as immersive focus mode with the laser | `present/*`, `editor_more_menu.dart`, `split/split_view.dart` (`solo`) | S |
| 34 | Focus mode | ✅ Keep; it gains the tool puck | Writing without chrome is a core tablet use | `chrome/focus_handle.dart`, `chrome/editor_chrome.dart` | M |
| 35 | Canvas minimap and "show overview" | ✅ Remove | It says little; fit content and zoom cover it | `canvas/canvas_minimap.dart`, `canvas/minimap_painter.dart`, `canvas/canvas_view.dart`, `canvas_minimap` golden | S |
| 36 | Canvas fit content, actual size, back to start (⋯ + buttons) | ✅ Merge into the zoom pill menu | One home for canvas navigation | `canvas/zoom_indicator.dart`, `canvas/canvas_view.dart`, `editor_more_menu.dart` | S |
| 37 | Double-tap zoom, gesture HUD, empty-canvas hint | Keep (no settings) | Invisible until needed | `double_tap_zoom.dart`, `chrome/gesture_hud.dart`, `canvas/canvas_empty_hint.dart` | – |
| 38 | One-time tips (side button, multi-finger taps) | ✅ Keep the side-button tip; remove the multi-finger tip (R9: no finger-tap tip; tips on a budget) | The HUD already teaches undo when it happens | `chrome/editor_tips.dart` | S |
| 39 | Audio: record button + recordings button | ✅ Merge → one split button (🎙 ▾) (▾ once there are recordings) | Two mic-ish icons side by side | `audio/ui/audio_bar_button.dart` | S |
| 40 | Audio player, trim, speed, ±10 s, ink replay, export, recovery | Keep | Parity (GoodNotes audio) | `audio/*` | – |
| 41 | In-notebook search (text, PDF, handwriting) | ✅ Keep; entry in ⋯ + Ctrl+F | Parity | `search/editor/*` | – |

## Library

| # | Feature | Verdict | Reason | Files | Effort |
|---|---|---|---|---|---|
| 42 | Folders (nested, colours, drag and drop, tree) | Keep | Parity | `library/*`, `data/folder_repository.dart` | – |
| 43 | Folder icons (19 glyphs) | ✅ Remove | Colour already distinguishes folders; one less picker | `library/folder_icons.dart`, `dialogs/folder_icon_picker.dart`, `Folder.icon`, sync field | S |
| 44 | Favourites | Keep | One tap, and it is what "starred" users expect | `library_controller.dart` | – |
| 45 | Tags (notebook and page tags, tag manager, filter chips, sidebar section) | ✅ Remove | Overlaps folders and favourites; two synced collections; neither reference app needs it | `features/tags/*`, `editor/tags/*`, `data/tag_repository.dart`, `data/tagging_repository.dart`, `library_header.dart`, `library_sidebar.dart`, `library_menus.dart`, sync | M |
| 46 | Trash, restore, empty, duplicate notebook | Keep | Safety | `library_actions.dart` | – |
| 47 | Grid / list + sort (3) as separate buttons | ✅ Merge → one ⇅ View menu | Two buttons for rare choices | `library_header.dart` | S |
| 48 | Selection mode (bulk move, trash, favourite) | ✅ Keep; entry in the ⇅ menu and the card menu | Parity | `library/selection/*` | S |
| 49 | Bottom navigation (phones) | ✅ Remove → drawer | Four tabs for three rarely-switched places; it steals height | `library_screen.dart` | S |
| 50 | New… tile and FAB both | ✅ Merge: tile on wide, FAB on phones | One primary action per screen | `new_notebook_tile.dart`, `library_screen.dart` | S |
| 51 | Cover colours (14) and patterns (6), cover sheet | ✅ Merge: 10 colours, no patterns | Live thumbnails show content; patterns are decoration nobody picks | `domain/cover_style.dart`, `cover_pattern_painter.dart`, `cover_picker.dart`, `dialogs/cover_sheet.dart`, `Palette.covers` | S |
| 52 | Create sheet with Cover / Paper tabs | ✅ Merge → one column (recent papers + "All templates…") | Faster common path | `new_notebook_sheet.dart`, `new_notebook/*` | M |
| 53 | Library full-text and handwriting search | Keep | Parity | `search/*` | – |

## Documents and templates

| # | Feature | Verdict | Reason | Files | Effort |
|---|---|---|---|---|---|
| 54 | Templates (about 25 procedural), paper colours, sizes, orientation, My templates | Keep | Parity; cheap vector code | `domain/templates/*`, `documents/templates/*` | – |
| 55 | Planners (daily, weekly, monthly, year, linked) | Keep | Notewise / GoodNotes users expect them | `patterns_planner.dart`, `planner_*` | – |
| 56 | Planner language picker (19 languages) | ✅ Default: device locale; remove the picker (keep the label tables) | A per-planner language choice is rarely wanted | `documents/templates/planner_options.dart` | S |
| 57 | Planner week start (Mon / Sun) | ✅ Default from locale, kept in a collapsed "More options" | Locale gets it right almost always | `planner_options.dart` | S |
| 58 | PDF import, annotate, text select, links, export (vector) | Keep | Parity | `documents/*`, `editor/pdf/*` | – |
| 59 | Export sheet: PNG resolution 192 / 384 dpi | ✅ Default 288 dpi; remove the choice | A technical knob with an obviously right answer | `export/export_options.dart`, `export/export_sheet_sections.dart` | S |
| 60 | Export: templates and backgrounds on / off, page range | Keep | Commonly needed | `export/*` | – |
| 61 | Page overview with selection, reorder, bookmarks | ✅ Keep; it adds an Outline filter | Parity | `documents/overview/*` | S |

## Settings and app

| # | Setting / feature | Verdict | Reason | Files | Effort |
|---|---|---|---|---|---|
| 62 | Theme (system / light / dark) with live previews | ✅ Keep; previews → segmented | Previews take a screen for three choices | `settings/theme_choice.dart`, `appearance_settings.dart` | S |
| 63 | Accent colour (7) | ✅ Remove (fixed ink blue) | Ink and covers carry the colour; this keeps the app calm and the goldens single | `settings/appearance_settings.dart`, `Accents`, `AppPreferences.accentColor`, `app.dart` theme wiring | S |
| 64 | Stylus only | ✅ Keep as "Draw with: Automatic / Stylus only / Stylus & finger" (as the "Draw with finger" switch: automatic until set) | Automatic already exists (null); make it visible | `settings/input_settings.dart` | S |
| 65 | Side button action (erase / select / nothing) | Keep | S Pen first-class | `input_settings.dart` | – |
| 66 | Two-finger undo, three-finger redo (two switches) | ✅ Merge → one switch | Nobody wants one without the other | `input_settings.dart`, `AppPreferences` | S |
| 67 | Settings → Editor (toolbar position) | ✅ Merge into Writing (Docked / Floating) | One row doesn't need a section | `settings/editor_settings.dart` | S |
| 68 | Handwriting: search toggle, language | Keep (Android only) | Needed for recognition | `settings/handwriting_settings.dart` | – |
| 69 | Handwriting: language model "Delete…" | ✅ Remove | Android manages ML Kit models; it is a storage edge case | `handwriting_settings.dart` | S |
| 70 | Sync, Storage (web), About, licences | Keep | Needed | `settings/*` | – |
| 71 | Two-pane settings layout | ✅ Remove → single centred column | Five short sections don't need master / detail | `settings/settings_screen.dart`, `settings_section.dart` | S |
| 72 | Ink Lab (7 taps on the version) in release builds | Overridden (lead decision: kept, behind 7 taps). Was: Remove from release (`kDebugMode` or `--dart-define=INKLAB=true`) | A developer tool; its "Perf test" notebooks land in the user's library | `settings/about_settings.dart`, `features/inklab/*` | S |
| 73 | Library sync status in the sidebar | Keep (small, bottom) | Self-hosted users need to see it | `ui/sync_status_button.dart` | – |
| 74 | Library layout and sort preferences | Keep | Remembered, not settings | `AppPreferences` | – |

## Top removals (biggest simplification for the effort)

1. Stickers (#16): a whole feature and synced collection that duplicates shapes and
   copy-paste.
2. Tags (#45): two synced collections that overlap folders and favourites.
3. Toolbar customisation, favourite pens and tool names (#9–11): about 600 lines and
   three preferences.
4. Presentation mode merged into focus mode (#33).
5. Canvas minimap (#35).
6. User outline entries (#29): bookmarks plus the PDF outline in the overview are
   enough.
7. The Select PDF text tool (#6): long press already does it.
8. The accent colour picker (#63).
9. Cover patterns and folder icons (#43, #51).
10. Ink Lab in release builds (#72); the phone bottom navigation goes too (#49).

## Lead decisions (overrides the table above)

- **Approved** as written, except the rows below.
- **Outline (row 29): keep** user outline entries and the outline panel (GoodNotes parity); restyle only.
- **Ink Lab (row 72): keep in release builds,** still behind 7 taps on the version. The user records real S Pen input with it on the tablet.
- **Material Symbols Rounded (`material_symbols_icons`): approved.** (Superseded by
  DESIGN.md: Material Symbols **Sharp**.)
- **Pen tip ends:** pens get an end style (round / tapered / flat) with per-style settings (taper length; start, end or both). This replaces the old fixed taper and lives in the tool options popover. (Since
  2026-10-25 the popover offers the end style alone; taper length and where it tapers keep
  their stored values.)
