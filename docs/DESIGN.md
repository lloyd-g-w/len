# Len: design language

Status: foundation implemented (tokens, theme, shared components, font, icons);
the per-screen rollout is the checklist in §9. This replaces `REDESIGN.md` §1;
the rest of `REDESIGN.md` (structure, one home per command) still holds.

## 0. Subject, audience, job

- **Subject.** A paper notebook on a desk: sheets of paper, ink, rulings, the
  red margin rule, a cardboard cover, a pencil. Len is the desk and the
  notebook; the user's handwriting is the content.
- **Audience.** Students and professionals writing with a stylus on tablets
  (S Pen first), then phones, desktops and the web. They write for hours; the
  interface must disappear while they do.
- **Job.** Get to the right page fast, then get out of the way of the pen.

**Direction: Swiss minimal, derived from the notebook.** A strict 4-dp grid
like a ruled page, crisp neutral greys, one accent, a tight sans, flat
surfaces, hairlines instead of boxes, no ornament. What makes it Len's rather
than a template:

1. **Chrome is ruled paper.** Separation is drawn with 1-dp hairlines, the way
   a notebook separates lines: under the docked bar, between the sidebar and
   the library, between settings rows. No filled cards, no tinted panels.
2. **The margin rule marks where you are.** A short 2-dp accent rule,
   like the margin line of an exercise book, marks the current place: the
   current sidebar row, the focused control (the focus ring), the active
   field (its rule thickens). This is the one bold device; everything else is
   neutral.
3. **Fields are rulings.** A text field is a line you write on: a faint tint
   with a 1-dp rule under it, 2-dp accent when focused.
4. **Only paper has depth.** Pages, covers, thumbnails and slips laid over
   the page (popovers, menus, dialogs) cast a shadow; chrome never does.
5. **The page is the brightest thing.** Chrome is a step greyer than the
   page, the desk around the page another step darker.

## 1. Colour

Neutrals are true greys (R = G = B): crisp, not warm, not tinted. Ink is real
black in light mode. One accent, **ruling blue**: the blue of a notebook's
rulings, deepened to carry text; it marks state, never decoration.

| name | light | dark | role (`ColorScheme` slot) |
|---|---|---|---|
| Ink | `#000000` | `#EFEFEF` | text, icons, primary buttons (`onSurface`, `inverseSurface`) |
| Graphite | `#5A5A5A` | `#A6A6A6` | secondary text, captions, idle icons (`onSurfaceVariant`) |
| Pencil | `#8A8A8A` | `#7A7A7A` | control outlines that must read (≥ 3:1), field rules (`outline`) |
| Rule | `#DCDCDC` | `#383838` | hairlines, dividers, quiet borders (`outlineVariant`) |
| Sheet | `#FFFFFF` | `#262626` | popovers, menus, dialogs, sheets, the floating palette (`Surfaces.overlay`) |
| Board | `#F4F4F4` | `#1A1A1A` | screen background and docked chrome (`surface`) |
| Desk | `#E6E6E6` | `#000000` | around pages in the editor (`Surfaces.canvasBackdrop`) |
| Ruling blue | `#0068C9` | `#4DA3FF` | the accent (`primary`): focus, the margin rule, switches, sliders, progress, links, selection handles |
| Correction red | `#C4161C` | `#FF6B6B` | destructive commands and errors (`error`) |

Contrast (WCAG): Ink on Board 19.6:1 (dark 14.8:1); Graphite on Board 6.3:1
(dark 7.2:1), on Desk 5.5:1; ruling blue on Sheet 5.5:1 (dark 5.8:1), on Board
5.0:1; Pencil on Sheet 3.5:1 (dark 3.6:1), enough for control boundaries.

Containers between Board and Sheet, for the few places that need a plate
(`surfaceContainer*`): light `#FFFFFF` lowest, `#EEEEEE`, `#E9E9E9`, `#E3E3E3`,
`#DDDDDD` highest; dark `#141414`, `#1F1F1F`, `#232323`, `#2B2B2B`, `#333333`.

Interaction overlays are ink: hover 4 % (dark 6 %), pressed / selected plate 8 %
(dark 12 %), a firm selection 12 % (dark 20 %). Ink, covers, paper and
`Palette` markers are content and never themed.

## 2. Type

**Sofia Sans** (Lettersoup, SIL OFL 1.1) for all chrome. A narrow, crisp
grotesque with a Bulgarian designer's Cyrillic, full Greek and Latin
Extended-A (all 19 planner languages), tabular figures, weights 1–1000. Its
narrow set width keeps toolbar labels and notebook titles from truncating;
its small x-height (0.49 em against Inter's 0.55) is compensated by setting
every role one size up. Static 400 / 500 / 600 / 700 instances, subset like
the text-box fonts (`tool/build_fonts.py`).

Text boxes and printed planner labels **stay Inter** (and Lora, JetBrains
Mono, Caveat): they are the user's content on the page, stored in synced
documents and embedded in PDF export, while Sofia Sans is the desk's voice.
Chrome and paper speak in different faces on purpose.

| role | slot | size / line | weight | tracking | use |
|---|---|---|---|---|---|
| Title | `titleLarge` | 24 / 28 | 600 | −0.4 | screen titles (Library, Settings) |
| Heading | `titleMedium` | 18 / 24 | 600 | −0.2 | dialog and sheet titles, the notebook title in the bar |
| Body | `bodyMedium` | 15 / 20 | 400 | 0 | rows, descriptions |
| Label | `labelLarge` | 15 / 20 | 500 | 0 | buttons, menu rows, tabs, card titles |
| Caption | `bodySmall` | 13 / 16 | 400 | +0.1 | dates, hints (Graphite) |
| Small label | `labelSmall` | 12 / 16 | 600 | +0.2 | `SectionLabel`, badges (sentence case, Graphite) |

Rules: left-aligned everywhere (centred only for empty states and the page
indicator); sentence case; no all-caps labels; numbers that change in place
use tabular figures (`AppTheme.tabularFigures`); meta strings are separate
spans or commas, not `A · B` chains.

## 3. Grid, spacing, radii, hairlines, depth

**Grid.** 4-dp baseline; controls and gaps are multiples of 4 (`Gaps` 2, 4,
8, 12, 16, 24, 32, 48; 2 only inside controls). Screens keep a left margin
column of 24 dp (16 on phones) that headings, rows and the first cover align
to. Bars: controls 4 apart, clusters 12 apart with a hairline between.

**Radii**, tight and by object size (a page corner is square; a cover's is
slightly worn):

| token | dp | use |
|---|---|---|
| `xs` | 2 | chips, badges, plates, tooltips, the selected-tool plate |
| `sm` | 4 | buttons, fields, segmented controls, covers, thumbnails, focus ring |
| `md` | 6 | menus, popovers, the floating palette, snack bars |
| `lg` | 8 | dialogs, the top of sheets |
| `pill` | 999 | colour dots and the page indicator only |

**Hairlines.** 1 dp, Rule colour; Pencil where a control's edge must read.
The docked bar has one hairline on the edge facing the page; the library
sidebar one on its right edge; settings rows one between rows.

**Depth** (`Shadows`, the only source):

| level | token | light | used for |
|---|---|---|---|
| 0 | none | flat, hairline edge | bars, sidebars, settings, the library background |
| 1 | `Shadows.low` "contact" | 0/1/1 black 10 % + 0/2/6 black 6 % | paper at rest: pages, covers, thumbnails; the floating palette |
| 2 | `Shadows.high` "lifted" | 0/1/2 black 8 % + 0/8/24 black 12 % | slips over the page: popovers, menus, dialogs, dragged items |

Raised and overlay surfaces carry a Rule hairline in both themes (crisp edges;
in dark mode it does the shadow's work). Dialogs sit over a scrim of black
32 % (dark 60 %).

## 4. Icons

**Material Symbols Sharp**, weight 300, fill 0, optical size 20; active and
selected states fill 1. Sharp's square terminals and right-angle corners
match the 2–4-dp radii and the hairlines, where Rounded's soft ends read as
friendly Material. Keeping the same family (not another icon set) keeps every
glyph the app needs, the variable weight/fill axes and release tree-shaking.
Sizes from `Glyphs` (bar 20, menu 18, slot dot 22, empty 40). Custom glyphs
(`EraserIcon`, `ShapeGlyph`, tool icons) are drawn at 1.5 px with square caps
and mitred joins to match.

## 5. Motion

Crisp and short; motion answers an action, nothing moves on its own.
`Motion.fast` 100 ms (state changes, popovers), `medium` 180 (chrome fades,
panels), `slow` 260 (sheets, dialogs, routes), `travel` 400 (scrolling to a
page). Popovers and menus fade and drop 4 dp from their anchor
(`Motion.popoverDrop`), no scaling bloom. Chrome fades with a 8-dp slide
toward its edge (`ChromeFade`). Taps never ripple (`NoSplash`, ink overlay).
Reduced motion: fades only.

## 6. Components

All shared; features never restyle them locally.

**Buttons** (40 dp visual, hit area padded to 48 on touch, radius `sm`):

```
 ┌──────────────┐   ┌──────────────┐     Cancel          ⟨ ⌫ ⟩
 │  Create      │   │  Duplicate   │                      40×40, ink 8 % plate on press
 └──────────────┘   └──────────────┘
 primary: Ink fill,  secondary: 1-dp      quiet: Ink label,  icon button
 Board label, 600    Pencil edge, Ink     hover plate only
```
Destructive primary: Correction red fill. Disabled: Rule fill, Graphite label.
The new-notebook action (FAB) is a 56-dp Ink square, radius `md`.

**Fields** (rulings): Ink 4 % tint (dark 6 %), radius `xs` on top, a 1-dp
Graphite rule underneath; focused, the rule is 2-dp ruling blue; error,
Correction red. Label inside the field, Caption when floating.

```
 Server URL                         Server URL
 https://len.example.org            https://len.example.org|
 ───────────────────────────        ━━━━━━━━━━━━━━━━━━━━━━━━━━━  (2 dp, blue)
```

**Switch:** flat track (Rule when off, ruling blue when on), white square-ish
thumb of constant size, no check glyph. **Slider:** a 2-dp ruled track (blue
up to the value, Rule after) and an Ink tick thumb 4 × 20 dp, like a ruler's
mark. **Checkbox / radio:** 2-dp corners, blue when on. **Progress:** 2-dp
blue rule on a Rule track, square ends.

**Segmented control:** one 1-dp Pencil-edged box, radius `sm`, hairlines
between segments; the selected segment is an Ink plate (12 % / 20 %) with an
Ink label in 600, no check glyph.

```
 ┌──────────┬─────────┬────────┐
 │▓ System ▓│  Light  │  Dark  │
 └──────────┴─────────┴────────┘
```

**Chips:** radius `xs`, 1-dp Rule edge, transparent; selected: Ink plate.
**Tooltips:** Ink slab (dark: Ink is light, so text is Board), radius `xs`,
Caption text. **Snack bars:** Ink slab, radius `md`, Body text in Board, the
action in the inverse accent. **Scrollbars:** 4-dp Graphite bar at 48 %,
square-ish (radius 2). **Focus ring:** 2-dp ruling blue, 2 dp off the control,
radius `sm`, keyboard only.

**Menus and popovers:** Sheet, radius `md`, Rule hairline, `Shadows.high`;
rows 44 dp (48 touch), Label text, 18-dp Graphite glyphs; destructive last, in
red. Popovers pad 16, title Heading, a hairline only between groups.

**Dialogs:** Sheet, radius `lg`, hairline, 24 padding, Heading title
left-aligned, Body in Graphite, actions right-aligned (quiet Cancel, Ink
primary). **Sheets** (phones): Sheet, `lg` top corners, a 32 × 3 Pencil
handle, full-width stacked actions, primary on top.

**Sidebar rows:** no filled selection pill or plate; the current row gets
the margin rule (2 × 20 dp ruling blue at its left edge) and a bold Ink
label. Others: Graphite icons, Ink labels in 500; hover is an Ink 4 % plate.

**Dialog glyphs** (destructive and progress dialogs): the bare 28-dp glyph in
its colour on the title's left edge, no tinted disc.

### 6.1 Library

```
Desktop (≥ 1040)                                       hairline = sidebar edge
┌──────────────────────┬────────────────────────────────────────────────────────┐
│ Len                  │ Library                          [⌕ Search       ] ⊕ ⇅ │
│                      │ 3 folders, 7 notebooks                                 │
│▌Library              │                                                        │
│  Favourites        1 │ ▬ School      ▬ Sketches      ▬ Work                   │
│  Trash             1 │   1 item        Empty           1 item                 │
│                      │ ────────────────────────────────────────────────────── │
│ Folders            + │ ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐           │
│  › School            │ │  +   │ │ ▌    │ │ ▌    │ │ ▌~~~ │ │ ▌    │  covers:   │
│    Sketches          │ │      │ │ ▌    │ │ ▌    │ │ ▌~~~ │ │ ▌    │  contact   │
│    Work              │ └──────┘ └──────┘ └──────┘ └──────┘ └──────┘  shadow    │
│                      │ New       Travel   Spanish  Ideas    Recipes           │
│                      │ notebook  Saturday Saturday Saturday Saturday          │
│ ⚙ Settings   ☁ Off   │                                                        │
└──────────────────────┴────────────────────────────────────────────────────────┘
Tablet (840–1039): the same with an icon rail.     Phone (< 840):
                                                   ┌──────────────────────────┐
                                                   │ ≡  Library          ⌕  ⇅ │
                                                   │    3 folders, 7 notebooks│
                                                   │ ▬ School      ▬ Sketches │
                                                   │ ──────────────────────── │
                                                   │ ┌────────┐  ┌────────┐   │
                                                   │ │ ▌      │  │ ▌      │   │
                                                   │ └────────┘  └────────┘   │
                                                   │ Travel      Spanish      │
                                                   │                    ┌───┐ │
                                                   │                    │ + │ │ Ink FAB
                                                   └────────────────────┴───┴─┘
```
Folders are a ruled row of names (glyph, name, count), not grey tiles. Covers
are flat colour with a darker spine band (no gradient), radius `sm`, contact
shadow.

### 6.2 Editor chrome

```
Docked, one bar (≥ 1040): Board, 52 dp, hairline under it
┌──────────────────────────────────────────────────────────────────────────────┐
│ ←  ▦  Biology lecture  │ ✎ ▭ ◇ ⌒ △ T ✦ ⊕ │ ● ● ●  · • ● │  🎙  ↶  ↷  ⋯         │
│       Science          │ ▔▔ (ink plate)   │               │                    │
├──────────────────────────────────────────────────────────────────────────────┤
│ Desk                ┌──────────────────────────────┐                         │
│                     │ page (brightest), contact     │                        │
Two rows (600–1039): the tool row (48) joins the bar, one hairline under both.
Phone: tool row at the bottom, hairline on its top edge.

Floating palette: Sheet, radius md, hairline, contact shadow, grip of 2 ticks
╭──────────────────────────────────────────────────╮
│ ⁞⁞  ✎ ▭ ◇ ⌒ △ T ✦ ⊕ │ ● ● ● │ · • ●               │
╰──────────────────────────────────────────────────╯

Popover (tool options): Sheet, md, hairline, lifted, 4 dp below its anchor
┌ Pen ─────────────────────────── Reset ┐
│ ┌───────────────────────────────────┐ │ preview on paper, Rule edge
│ │   ~~~~~~~~ live stroke ~~~~~~~~   │ │
│ └───────────────────────────────────┘ │
│ Colour                         Custom │ Small label, quiet button
│ ● ● ● ● ●                             │
│ Size                         0.66 mm  │ tabular figures
│ ━━━━━━━━━━━━┃───────────────────────  │ ruled slider, ink tick
│ ───────────────────────────────────── │ hairline between groups
│ Feel                               ⌄  │
└───────────────────────────────────────┘
```
The selected tool keeps its Ink plate (radius `xs`); colour underlines under
tools stay (they are ink). Page indicator: Sheet pill with tabular figures.

### 6.3 Dialogs, sheets

```
Dialog (≥ 600): Sheet over scrim         Sheet (phones)
┌──────────────────────────────────┐     ┌──────────────────────────────┐
│ Move to folder                   │     │            ───               │ handle
│                                  │     │ New notebook               ✕ │
│ Choose where Travel plans goes.  │     │ ┌──────────────────────────┐ │
│ ┌──────────────────────────────┐ │     │ │ Untitled                 │ │
│ │ ▌School                      │ │     │ └──────────────────────────┘ │ ruled field
│ │  Sketches                    │ │     │ ...                          │
│ └──────────────────────────────┘ │     │ ┌──────────────────────────┐ │
│                   Cancel  [Move] │     │ │         Create           │ │ Ink
└──────────────────────────────────┘     │ └──────────────────────────┘ │
                                         │ ┌──────────────────────────┐ │
                                         │ │         Cancel           │ │ outlined
                                         └─┴──────────────────────────┴─┘
```

### 6.4 Settings

Sections are open ruled lists on Board, not cards: a Small label heading in
Graphite, rows separated by hairlines that start at the text, controls
right-aligned on wide rows, below on narrow ones.

```
Settings                                        (Title, left margin column)

General
──────────────────────────────────────────────────────────────
 ◐  Theme                         ┌────────┬───────┬───────┐
    Paper keeps its colour         │▓System▓│ Light │ Dark  │
                                   └────────┴───────┴───────┘
    ──────────────────────────────────────────────────────────
 ⌨  Keyboard shortcuts                                       ›
──────────────────────────────────────────────────────────────
Writing
 ...
```

## 7. Review against the brief and the generic defaults

First plan (v0), before review: pure white chrome; Swiss red accent;
zero radius everywhere; tracked all-caps section labels; settings sections
numbered 01, 02, 03; no shadows at all; Geologica as the face; accent-blue
primary buttons. Reviewed against the brief and the skill's list of defaults:

| v0 | problem | revised to |
|---|---|---|
| Swiss red accent | the cliché of "Swiss"; collides with destructive red, the red pen and the paper's own margin line | ruling blue, taken from the notebook's rulings; red stays for destruction |
| zero radius everywhere | the broadsheet default (hairlines + 0 radius) | a 2/4/6/8 hierarchy by object size; the page itself stays square |
| all-caps tracked labels | template chrome | sentence-case Small label, 12/16, 600 |
| numbered settings sections | not a sequence | plain headings |
| white chrome | the page would not be the brightest thing | Board chrome, Desk around pages, Sheet only for slips |
| no shadows at all | popovers melt into a white page full of ink | "only paper has depth": contact and lifted shadows for paper and slips; chrome flat |
| Geologica | wide set width costs toolbar room; heavy colour at UI sizes | Sofia Sans: narrow, crisp, full Cyrillic/Greek, tabular figures |
| accent primary buttons | accent everywhere dilutes it | Ink primary buttons; the accent marks state only |
| `A · B` meta strings (existing copy) | template chrome | commas or separate spans (rollout) |
| tinted near-black text | template chrome | true black ink; true neutral greys |
| filled grey fields | stock Material look | ruled fields: tint plus a rule, thickening in blue on focus |

After building, the screenshot critique (library, editor, toolbar and app
surfaces suites, phone/tablet/desktop, light and dark) changed:

| seen in the screenshots | revised |
|---|---|
| the current sidebar row on a grey plate read as the stock pill | plate removed: the margin rule and a bold label alone |
| a Pencil field rule antialiased to 2.4:1 against the fill | the rule is Graphite: a line you write on, readable at a glance |
| dark field fill (8 %) heavier than the Sheet around it | 6 % |
| dialog glyphs in tinted circles: ornament | bare glyph |
| dark "off" switch and slider tracks vanished into the Sheet | a lifted `#4A4A4A` off-track |
| popovers scaling from 96 %: a soft Material bloom | fade plus a 4-dp drop from the anchor |
| field label/hint styles fixed in the theme kept the UI font where tests swap it | left to Material's defaults (same Graphite colour) |

Still open (feature-level, in the rollout): Material's stadium switch (Flutter
offers no shape hook; an `AppSwitch` in `ui/` with a square thumb), grey
folder tiles and gradient covers, the blue brand tile, the accent `+` on the
new-notebook tile, white settings plates with a shadow, `·` meta strings.

Library rollout, from its screenshots: folders on their own column widths
looked loose beside the covers, so they sit on the covers' columns; the
empty state's fanned, overlapping covers read as one striped block and became
three upright covers in a row; a blue ring for the current page in the
overview competed with selection, so the current page takes the margin rule
by its number and only selection rings. Page miniatures are square (a page
corner is square); `sm` stays for covers and notebook thumbnails.

Also checked: no cream background, no terracotta, no acid accent on black, no
monospace data labels, no arrows appended to buttons, no identical shadowed
cards (settings and folders lose their plates).

## 8. Constraints kept

One home per command; chrome recedes (flat Board, hairlines, one accent);
targets by input (`Targets`: 48 touch / 40–44 pointer); WCAG AA contrast and a
keyboard focus ring; reduced motion; light and dark; 1.3× and 2× text (roles
use line heights in proportion, controls grow); layering; tokens only.

## 9. Rollout checklist (next phase)

Foundation done: tokens, scheme, type, Sofia Sans, Sharp icons, component
themes, `FloatingPanel`, `OverlaySurface`, popovers, menus, dialogs, sheets,
snack bars, `SidebarItem` (margin rule), `FocusRing`, ruled fields, slider
thumb. Next, by area:

- **Library:** done. Folders are names on the covers' columns with a
  hairline under the row; covers flat with a darker spine band; the New tile
  and Add page are Pencil-edged outlines with an Ink +; list rows ruled from
  the titles; the brand is the Ink scribble; commas in meta strings; square
  checkbox selection marks; search results label and count as separate
  spans, the page location as a plain column.
- **Editor chrome:** tool plate radius `xs` and Ink 8 % everywhere
  (`tool_cluster.dart`, `toolbar_buttons.dart`); slot rings 1.5 dp; redraw
  `EraserIcon`, `ShapeGlyph`, `tools/tool_icons.dart` with square caps;
  floating palette grip as two ticks; page indicator tabular figures; tabs
  (`editor_tabs`) with a margin-rule current tab instead of a plate.
- **Popovers:** hairlines between groups instead of spacing alone; pen
  preview box radius `sm` with a Rule edge; Feel row as a ruled disclosure.
- **Settings:** `settings_section.dart` to open ruled lists (no plates, no
  shadow); section headings on the left margin column.
- **Dialogs and sheets:** move dialog, cover sheet, new-notebook sheet,
  export sheet onto the ruled fields and Ink primary; check every
  `FilledButton.tonal` (becomes secondary/outlined).
- **Overview, templates:** done. Pages are square with the contact shadow
  only (no hover lift); the current page has the margin rule beside its
  bold number; selection is a 2-dp accent ring and a square checkbox; the
  template gallery marks its choice with the margin rule and a bold name.
  PDF views remain.
- **Audio, images, text:** recording bar as a flat Board strip with a
  hairline; text format bar on `FloatingPanel`.
- **Copy:** remove `·` chains and any remaining all-caps; one name per action.
- **App icon / splash:** done: the white scribble on a ruling-blue rule on
  an Ink tile, flat; splash on Board (`tool/branding`).
- **Controls:** an `AppSwitch` in `ui/` (flat rectangular track, square
  thumb, 44 × 24) replacing `Switch` / `SwitchListTile` (19 uses); every
  `FilledButton.tonal` to `OutlinedButton` (the theme makes both Ink).
- **Icons after merges:** other branches still add `Symbols.*_rounded`; re-run
  the rename in the "Icons: Material Symbols Sharp" commit message.
- **Tests:** refresh goldens per area as it lands.
