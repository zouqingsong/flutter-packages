# adaptive_viewport

What a screen leaves an app to lay out in, and pure planners that turn it
into the layout of each media scenario: **live preview**, **viewer** (one
image or video) and **gallery**. Shared by the Doitech apps (camivex,
MicVision / FlexionCam Control, MedView, Zi Lele) so that each follows the
same rules on every device — iPhone, iPad, iPhone Duo, Android phones,
tablets and foldables, macOS, Windows and Linux — rather than being fitted
to the devices someone happened to test.

## Rules for every scenario

1. **Content first.** The picture (or grid) is as big as the window allows;
   controls give way to it, not the other way round.
2. **Safe area on the edges content reaches, and only those.** On a
   landscape iPhone UIKit insets *both* long edges for the Dynamic Island;
   the inset is kept on the island's side only. Backgrounds and scrolling
   content run edge to edge; what is at rest keeps the inset.
   A side inset that a camera hole accounts for is not a frame. The iPhone
   Duo's cover screen, folded and upright, has no status bar. Instead it
   reports an 84 pt column down its right-hand edge, with the hole, the
   clock and the signal ring at the column's top. The picture runs under
   the column, edge to edge, with no stripe beside it. Controls are
   aligned to the screen's edge. Only what lies beside the hole or the
   read-outs (the top bar) keeps the inset.
3. **Nothing on a hole or a crease.** A control that would land on a camera
   hole moves along the edge it is on, never into the middle. Nothing goes
   on a book fold's crease.
4. **Half-folded like a laptop: content above the fold, controls on the
   deck below.** The upright half is the picture alone — no bar, zoom
   strip or tool palette over it — and everything that is pressed is on the
   deck, where the hand rests. From the fold down: the read-outs and the zoom
   buttons, the drawing or editing tools while one is in hand, the main
   controls (capture and record, or the transport), then the strip of recent
   items. A deck too short for all of it drops the strip first (rule 7).
5. **Full screen is the content alone**, edge to edge. Its controls come
   back on a tap (touch) or a pointer move (desktop), and go again
   (`ChromePolicy`).
6. **Classes, not devices.** Layout comes from `ScreenClass`: the width
   class, whether the height is short, the input and the posture. The one
   device table is where iOS reports nothing: the iPhone Duo cover screen's
   punch hole and the status read-outs beside it, in
   `DisplayHousing.punchHoleOf` and `DisplayHousing.statusReadOutsOf`.
7. **No control is reached by scrolling.** Every button is on screen at
   once, whatever the window. A bar or rail measures its groups and folds
   them until they fit (`ControlsPlanner`); labels give way to icons
   before anything scrolls. Scrolling is for content — lists, grids, text —
   never for controls. The narrowest windows this has to hold for are a
   Galaxy Z Fold cover screen on its side (about 300 pt of rail) and a
   320 dp Android phone upright with three-button navigation. Tool
   palettes (drawing, processing, camera settings) wrap their groups onto
   as few rows as fit and fold a group behind one button only where that
   saves a row (`PalettePlanner`).
8. **Live and captured are one design.** A feature both the live preview
   and the viewer (image or video) offer looks the same, sits in the same
   place and is put away the same way on both:

   | Feature | On both screens |
   | --- | --- |
   | Zoom | pinch, wheel and double tap on the picture; the same + − fit buttons; the read-out last in the view options |
   | Image processing / camera settings | one tool palette: values that are dragged open a slider row above the groups, toggles are buttons that fill while on, Done ends it; the button that opens it (`tune`) turns into Done while it is open |
   | Annotation | the same drawing palette and the same layer; the button that opens it turns into Done |
   | Share, info, full screen | the same icons, in the same order (annotate, adjust, share) |
   | Where a palette goes | at the foot of the picture, over it, clear of the bars and the safe area — `ViewerPlan.tools`, `LiveStage.toolPalette` |
   | Half-folded | from the fold down: the head line (read-outs or title) with the zoom buttons at its end, the palette in hand, the main controls (capture and record, or transport and view options) centred in what is left, then the strip while it fits |

   Only one palette is open at a time; opening one puts the other away.
   A feature only one screen has (record, crop, the scrubber) still uses
   the same parts — a `ToolPalette` group, a `ToolSliderRow` — so that
   anything new lands looking like what is already there.

9. **Every control is wholly on screen.** Each toolbar, bar, palette and
   floating control — annotate, share, adjust, info, full screen, zoom,
   the transport — is fully visible: never cut off at an edge, never laid
   out beyond the screen where it cannot be seen. This holds upright and
   on the side, on every device and window size, folded, unfolded and
   half-folded, at rest and with a palette open. Two things make it so:

   * **Plan in the box the page has, not the window.** A page pushed inside
     a shell sits below its app bar or beside its sidebar; planned for the
     whole window, its bottom bar was half off the screen on one phone and
     wholly below it on another. Planners take
     `ScreenViewport.windowOf(context).within(box)`, or
     `BoxViewportBuilder`, which measures the box and hands its builder that
     viewport — the safe area, holes, crease and fold all in the box's own
     coordinates.
   * **One header.** On a narrow window a pushed page (viewer, compare,
     about) brings its own bar with a back button, and the shell drops its
     own bar while it is up: two headers took the picture's room and,
     half-folded, put a control above the fold.

   Page tests put each page where the app puts it (in the shell, below the
   bar or beside the sidebar it really has), open its palettes, and fail on
   any control not wholly inside the window.

## The screen class

`ScreenClass.of(viewport)`:

| Reading | Values | From |
| --- | --- | --- |
| `width` | `compact` < 600 ≤ `medium` < 840 ≤ `expanded` < 1200 ≤ `large` | window width (Material 3 window size classes) |
| `compactHeight` | height < 480 | window height |
| `input` | `touch`, `pointer` | platform: macOS, Windows, Linux are pointer |
| `posture` | `flat`, `tabletop`, `book` | hinge (iOS) or display features (Android) |
| `isWide` | expanded or wider, and not short | room for two panes side by side |
| `isShortLandscape` | landscape and short | a phone on its side: controls beside, not above and below |

Some windows, by class:

| Window | Class | Two panes |
| --- | --- | --- |
| iPhone upright, cover screens, 320–360 dp Android phones, iPad Split View third, narrow desktop window | compact | no |
| any phone or cover screen on its side (Fold cover landscape is ~300 tall), short desktop window | medium or expanded, short | no |
| iPad upright, Fold inner, Duo inner upright | medium | no |
| iPad on its side, Duo inner on its side, Android tablet, desktop window | expanded / large | yes |
| Fold or Flip half-open, Duo inner hinge 30°–135° | tabletop | above / below the fold |
| Fold half-open as a book | book | either side of the crease |

## Scenarios

### Live preview — `StagePlanner`

| Mode | When | Layout |
| --- | --- | --- |
| `framed` | app's wide breakpoint (e.g. `ScreenClass.isWide`) | picture framed in its pane, controls in a bar below |
| `column` | upright, not wide | picture across the top, read-outs in the letterbox band above it, one-row bar below |
| `docked` | landscape, not wide | picture edge to edge, controls in a rail over the trailing edge, clear of the island |
| `tabletop` | half-folded | picture alone above the fold; on the deck, from the fold down: read-outs and zoom buttons, the palette in hand (drawing or camera settings), the controls centred in what is left, the strip while it fits |

Full screen: the picture alone; the actions, then a recording dot only.

### Viewer — `ViewerPlanner`

| Mode | When | Layout |
| --- | --- | --- |
| `docked` | the bars cost the fitted picture ≤ 10 % of its area (they fit in its letterbox), or `keepPictureClear`, or (shape unknown) a pointer or wide window | top bar, picture, bottom bar (transport, tools, filmstrip), none overlapping; on touch (`ChromePolicy.revealOnTap`) a tap on the picture still puts them away and brings them back, the picture staying where it is |
| `overlay` | otherwise — a phone on its side, mostly | picture edge to edge, bars float over it; a tap hides or shows them (`ChromePolicy`) |
| `tabletop` | half-folded | picture alone above the fold; on the deck, from the fold down: the top bar (back, name, the zoom buttons at its end), the palette in hand (`tools`), then the bottom bar (transport, view options, filmstrip) centred in what is left — the live deck's order (rule 8) |

A tap on the picture behaves the same whichever way the phone is held:
upright (`docked`) or on its side (`overlay`), it hides the bars, and the
next tap brings them back. Only the deck's bars when half-folded
(`tabletop`), and the bars of a tool in use, stay put; bars put away
upright come back once the phone is half-folded.

An open tool palette has its own rect, `plan.tools`, when the app passes
its height as `toolsHeight`: just above the bottom bar, 16 in from the safe
area, or on the deck between the two bars.

A side panel (details, series, measurements) is shown only beside the
picture: on a wide window at the trailing edge (240–`panelWidth` wide), or
on the far half of a book crease. Never on a phone; never over the picture.
Bars keep the whole safe area on their outer edge, so no button meets a
notch, island, hole or home indicator.

### Gallery — `GalleryPlanner`

| Mode | When | Layout |
| --- | --- | --- |
| `single` | default | the grid alone |
| `split` | the app shows an open item, and the window is wide or has a book crease | grid on the leading side (320–480, or up to the crease), item beside it |
| `tabletop` | the app shows an open item, half-folded | item above the fold, grid on the deck |

Columns: as many as fit at the width class's smallest tile — 104 compact,
128 medium, 152 expanded and up — and never fewer than two. A phone gets
three upright and four or five on its side, an iPad five to eight, a
desktop window eight to twelve. `plan.delegate` is
the `SliverGridDelegate`. The grid scrolls under the system bars;
`gridPadding` keeps tiles at rest clear of the safe area and the bottom
bar.

### Palettes — `PalettePlanner`

A tool palette (drawing, image processing, camera settings) is a few small
groups of buttons on dark pills, the way the Photos editor lays its tools
out, with the value being dragged in a slider row of its own above them.
The app gives each group's width in full and, where it has one, compact
(a colour row behind one colour button, filters behind a menu); the
planner wraps whole groups onto as few rows as fit and folds a group only
where that saves a row:

| Window | Drawing | Processing |
| --- | --- | --- |
| desktop, iPad, any phone on its side | one row (a phone folds the shapes behind a menu) | one row |
| iPhone 17 Pro, Pixel, Flip upright, Duo cover (370–434 of palette) | two rows; the colours behind one button | two rows, in full |
| iPhone SE, Fold cover, 360 dp Android upright (312–343) | two rows; shapes, measures and colours behind a button each | three rows |
| 320 dp Android upright, 3-button nav (288) | three rows, compact | three rows |

`PalettePlanner.heightOf` gives the height to plan for; a live deck uses
it to decide whether the strip still fits, the viewer passes it to
`ViewerRequest.toolsHeight`.

### Controls — `ControlsPlanner`

A bar (across) or a rail (down) holds three groups: the **tools**, the
**primary** actions (shutter, record) and the **view** buttons (full
screen, gallery). The app gives each group's length along the bar and its
thickness across it, and the `room` the bar has; the planner takes the
first fold that fits, measured, not by device:

| Fold | Groups | Costs |
| --- | --- | --- |
| `centred` | tools, primary centred, view — one line | nothing |
| `spread` | tools, primary, view — one line, primary off centre | symmetry |
| `folded` | primary on its own line, tools and view on the next | a second line of thickness |
| `regrouped` | tools on one line, primary and view on the next | a second line of thickness |

When nothing fits (`fits` is false) the plan is the fold that overflows
least, and only then may the tools scroll. A second line makes a rail
thicker or a bar taller; plan the stage with the folded `thickness`, so the
picture gives way to the controls and not the other way round.

| Window | Bar or rail | Fold |
| --- | --- | --- |
| iPhone 17 Pro, Duo cover — upright or on its side | bar or rail, 2 tools | `centred` |
| the same with 4 tools; Flip, Pixel, iPhone SE, Fold cover upright | bar or rail | `folded`: shutters on a line of their own |
| Galaxy Z Fold cover on its side (~300 of rail) | rail, 4 tools | `regrouped`: two columns, shutters by the edge |
| 320 dp Android upright, 3-button nav | bar, 4 tools | `regrouped`: tools above, shutters and view below |
| Android on its side, nav bar on the side | rail, 4 tools | `regrouped` |
| Android tablet on its side | rail, 4 tools | `centred` |
| wide window with the sidebar open | labelled actions if they fit, else the icon bar | — |

## Use

```dart
MaterialApp(
  builder: (context, child) => ViewportScope(child: child!),
);

final viewport = ScreenViewport.of(context);
final screen = ScreenClass.of(viewport);

// A page that does not have the whole window (below an app bar, beside a
// sidebar) plans in its own box — rule 9.
BoxViewportBuilder(
  builder: (context, viewport) => _layout(ViewerPlanner.plan(
    ViewerRequest(viewport: viewport /* … */),
  )),
);

final stage = StagePlanner.plan(StageRequest(
  viewport: viewport,
  wide: screen.isWide,             // or the app's own breakpoint
  fullscreen: immersive,
  topChrome: appBarShown,
  textDirection: Directionality.of(context),
));

final viewer = ViewerPlanner.plan(ViewerRequest(
  viewport: viewport,
  chromeShown: !immersive,
  mediaAspect: 16 / 9,
  panel: infoWanted,
));

final gallery = GalleryPlanner.plan(GalleryRequest(
  viewport: viewport,
  bodyTop: appBarBottom,           // 0 without an app bar
  detail: canShowItemBeside,
));

final controls = ControlsPlanner.plan(ControlsRequest(
  room: barWidth,                  // or the rail's height
  tools: ControlGroup.run(toolCount, extent: 44, thickness: 44, padding: 12),
  primary: const ControlGroup(length: 134, thickness: 60),
  view: const ControlGroup(length: 100, thickness: 44),
));
// controls.fold, controls.thickness, controls.fits
```

Put the picture under a `TabletopLayout(fold: …)` that is always in the
tree, so folding never rebuilds a video surface.

## Moving an app over

Today each app has its own numbers. Each maps onto a class:

| App | Now | Becomes |
| --- | --- | --- |
| camivex | sidebar at width ≥ 1000, or ≥ 900 and shortest ≥ 600 | `ScreenClass.isWide` |
| camivex | gallery tiles ≤ 190 | `GalleryPlanner` columns |
| camivex | viewer bar overlaid 16 from the edges | `ViewerPlanner` bars and `overlayInsets` |
| camivex | live rail and bar scroll when short (Fold cover, 320 dp phones) | `ControlsPlanner` folds (done) |
| MicVision | desktop from `ProductProfile.isDesktop` | `ScreenClass.input` and `isWide` |
| MicVision | grid `width ~/ 120` columns; strip 4 / 3 columns | `GalleryPlanner` columns |
| MicVision | `dependencies/fold_posture` | this package (`FoldPosture`, `TabletopLayout`) |
| MedView | PACS browser 1 / 2 / 3 columns at 600 / 900 | `WidthClass` compact / medium / expanded |
| MedView | viewer app bar compact under 560 | `WidthClass.compact` |
| MedView | bars stacked around DICOM images | `ViewerRequest.keepPictureClear` |

## Where the readings come from

| Reading | iOS | Android |
| --- | --- | --- |
| Safe area | `MediaQuery`, trimmed by `ViewportScope` using the interface orientation (plugin) | `MediaQuery` |
| Holes | measured table (`punchHoleOf`, `statusReadOutsOf`) | `DisplayFeatureType.cutout` |
| Tabletop | `UIHinge` (iOS 27.1+, plugin), inner screen in portrait, 30°–135° | `DisplayFeature` fold or hinge, `postureHalfOpened`, horizontal |
| Crease | — | vertical fold half-opened, or any vertical hinge |

`FoldPosture.simulateTabletop` splits any window, for simulators that cannot
fold.

## Testing a layout

`package:adaptive_viewport/testing.dart` has `ScreenProfile.all`: iPhones
with and without an island, the iPhone Duo's cover and inner screens (flat
and half-folded), the Galaxy Z Flip and Fold in each posture, Pixel phones
and the Pixel Fold, narrow (320 dp) and compact Android phones upright and on
their side — with three-button navigation at the bottom, or on the side in
landscape — iPads (including Split View), an Android tablet, and
macOS, Windows and Linux windows from narrow to full screen — each as the
window Flutter reports, on its platform. Run a layout over all of them; the
planner tests do so for every scenario, in both text directions, and check
that a bar's and a rail's controls fit without scrolling on every profile.
