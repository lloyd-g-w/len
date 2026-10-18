## Round 26, part M — the smaller features since round 25

Looked at the zoom window right to left, the stylus edge guard, Escape
closing previews, the overview, Settings and the Ink Lab, Rename clearing a
version's name, the curve and attaching tips, and version restore. Read the
code, probed each suspicion with a widget or unit test (throwaway probes;
the fixes' tests kept), rendered the zoom window right to left (phone and
tablet, light and dark, 1× and 2× text, with its menu) and the curve and
attach tips with the Rename prompt (390 and 1280 dp, light, dark, 2×
text), and looked at them. Probed Escape with a text field or a control
focused and with a menu open, and a restore with one notebook in both
panes of split view (both panes' undo and redo go off, as R25-6 wants).
Verdict: the engines hold (the stylus edge guard is sound: held only while
an editor's route is current and its pane not parked, counted across
panes, released under dialogs and screens; natively stylus and eraser
only, never fingers or mice; band unit tests cover placement); what was
unfinished was right to left in the zoom window, Escape from inside a
page, and feedback while a version is restored.

### Version history

**R26-M1 P2 · A version named later with Rename… was still thinned away.** ✅
- *What:* thinning (`data/versions/version_policy.dart`) kept versions by
  kind: Save version… made a `named` one, kept until deleted, but an
  automatic version given a name with Rename… stayed `auto` and went with
  its hour's or day's bucket — the name the user gave so as to find it
  again was lost with it.
- *Fix:* `VersionInfo` carries `named` (it has a name) and thinning skips
  named versions of any kind; clearing the name lets it thin again
  (`version_history_test` "an automatic version given a name stays; its
  name cleared, it thins again"; ARCHITECTURE "Version history").

**R26-M9 P2 · Restore and Copy gave no sign of running.** ✅
- *What:* R25-4 made a second tap on Restore or Copy do nothing while the
  first runs, silently: on a large notebook the buttons looked dead, and a
  copy from a row's ⋯ showed nothing until its snack bar.
- *Fix:* `versionWork` (`history/version_flows.dart`, a `ValueNotifier`
  replacing the private `_busy` flag; one restore or copy app-wide, as
  before) drives the preview's buttons ("Restoring…", "Copying…", all off
  meanwhile; the page view's Restore this page too) and an indeterminate
  `LinearProgressIndicator` on a `Hairline.rule` line under the history's
  header (as the scan screen's), labelled for screen readers
  (`version_history_ui_test` "while a restore runs, the preview says so and
  takes no other").

**R26-M11 P3 · A version named with Rename… lacked the kept mark.** ✅ After
R26-M1 it is kept like a saved one, but only `VersionKind.named` rows had
the bookmark. The row now marks any version with a name (or saved by
hand); clearing the name drops the mark and the title says Edited again
(`history/version_row.dart`; `version_history_ui_test` "a version given a
name shows it is kept").

**R26-M12 P3 · A restore's Undo is not in the one-at-a-time rule.** ⬜ The
snack bar's Undo runs `versions.restore(before)` outside `_once`, so a
restore started from the history while it writes is not refused, and the
buttons don't say Restoring…. *Proposal:* run Undo through
`_once(VersionWork.restore, …)`.

### Zoom window right to left

**R26-M2 P2 · Right to left, ↵ still pointed left.** ✅ The rail's next-line
button showed the left-to-right return glyph while a new line goes back to
the right. `ZoomBoxRail` takes `rightToLeft` and mirrors ↵
(`zoom/zoom_box_rail.dart`; `zoom_window_rtl_test` "right to left, ↵
points back to the right").

**R26-M3 P2 · Right to left, a narrower box (rotation, resize) moved the line's start.** ✅
`ZoomWindow.setBox` kept the frame's top-left, which right to left is the
line's end: the frame's right edge, where writing goes on, jumped left.
It now keeps the top-right right to left (`zoom_window_rtl_test` "a
narrower box keeps the frame's right edge").

**R26-M4 P2 · In split view, the direction set in one pane's box left the other's box running the old way.** ✅
The preference is shared, but only the box whose ⋯ was used called
`directionChanged`: the other pane's frame advanced the wrong way until
reopened. Each `ZoomBox` now listens to the preferences and turns over
when the direction changes, wherever it was set (`zoom_window_rtl_test`
"the direction set elsewhere turns this box over too").

**R26-M5 P3 · The Right to left row's caption wrapped at 2× text.** ✅
"Lines advance leftwards" took two lines in the box's menu on a phone at
2× text; it is now "Lines go left" (`zoom/zoom_box_menu.dart`).

### Escape

**R26-M6 P3 · Escape did not close the Ink Lab.** ✅ Settings closes on
Escape (R25-8) but the Ink Lab, opened from it, did not: Escape there did
nothing. The lab is wrapped in
`EscapeCloses` (`inklab/inklab_screen.dart`; `inklab_screen_test` leaves
the lab with Escape).

**R26-M10 P2 · Escape did nothing once a control in the page had focus.** ✅
- *What:* `EscapeCloses` (R25-8) only worked while its own focus node held
  focus. After Tab to a switch or button, or typing in Settings' Server URL,
  Escape did nothing: Flutter's Escape shortcut takes only the *nearest*
  `DismissIntent` action, and every `Scaffold` has one (closing its
  drawer) that is off with no drawer open. Settings, the version preview
  and its page view, the page overview and the Ink Lab all had it.
- *Fix:* `EscapeCloses` sees Escape bubble up first (`Focus.onKeyEvent`): a
  nearer action that is on keeps it (an open drawer); in a text field it
  leaves the field (a second Escape closes; what was typed is not lost to
  one stray key); else it asks the route to pop. Menus and popovers over
  the page close alone, no double pop (`escape_closes_test`: a focused
  control, a text field, a menu open).

### Tips

**R26-M7 P2 · The attach tip showed mid-drag.** ✅ The tips wait for the pen
to rest before showing (so they never cover what is being drawn), but
dragging a line's end onto a shape is not "drawing": the attach tip
appeared under the hand while the end was still moving. A change of the
selection while attaching now restarts the rest timer
(`chrome/editor_tips.dart`; `tip_budget_test` "ends attach to shapes, once
the drag rests").

**R26-M8 P3 · The curve tip said tap and double-tap with a mouse.** ✅
`tipMessage` takes `touch` (`Targets.touchFirst`): with a pointer it says
"Click the curve to add a point; double-click a point to remove it"
(`tip_budget_test` "with a mouse, the curve tip says click").

### Checked, no findings

Stylus edge guard (`features/editor/stylus_edge_guard.dart`,
`platform/stylus_edges.dart`, `StylusEdgeGuard.kt`): see the verdict;
`stylus_edges_test` covers routes, dialogs, split view and parked panes.
Settings has no sub-pages besides the Ink Lab (R26-M6). Tips at 390 dp, dark
and 2× text wrap to two lines inside the banner; the banner is a live
region, so screen readers announce it. Restore: offline refuses with "not
on this device yet", the snack bar shows on the screen behind the history,
its Undo restores the version saved before.

Counts: 12 findings (0 P1, 7 P2, 5 P3); fixed: M1–M11 (all P2, 4 P3); open: M12 (P3).

Owner decisions for TODO Next:
- Escape in a text field of a full-screen page (Settings) leaves the field
  first and closes on the second press (R26-M10), unlike dialogs, where
  Escape closes at once. Options: keep (no typed text lost to one key), or
  close at once everywhere.
