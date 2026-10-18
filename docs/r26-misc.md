## Round 26, part M — the smaller features since round 25

Looked at the zoom window right to left, the stylus edge guard, Escape
closing previews, the overview, Settings and the Ink Lab, Rename clearing a
version's name, the curve and attaching tips, and version restore. Read the
code, probed each suspicion with a widget or unit test (throwaway probes;
the fixes' tests kept), rendered the zoom window right to left (phone and
tablet, light and dark, 1× and 2× text, with its menu) and the curve and
attach tips with the Rename prompt (390 and 1280 dp, light, dark, 2×
text), and looked at them. Verdict: *in progress.*

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
