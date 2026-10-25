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
3. **Nothing on a hole or a crease.** A control that would land on a camera
   hole moves along the edge it is on, never into the middle. Nothing goes
   on a book fold's crease.
4. **Half-folded like a laptop: content above the fold, controls on the
   deck below.**
5. **Full screen is the content alone**, edge to edge. Its controls come
   back on a tap (touch) or a pointer move (desktop), and go again
   (`ChromePolicy`).
6. **Classes, not devices.** Layout comes from `ScreenClass`: the width
   class, whether the height is short, the input and the posture. The one
   device table is where iOS reports nothing: the iPhone Duo cover screen's
   punch hole, in `DisplayHousing.punchHoleOf`.

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
| iPhone upright, cover screens, iPad Split View third, narrow desktop window | compact | no |
| any phone or cover screen on its side, short desktop window | medium or expanded, short | no |
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
| `tabletop` | half-folded | picture above the fold, controls and strip on the deck |

Full screen: the picture alone; the actions, then a recording dot only.

### Viewer — `ViewerPlanner`

| Mode | When | Layout |
| --- | --- | --- |
| `docked` | the bars cost the fitted picture ≤ 10 % of its area (they fit in its letterbox), or `keepPictureClear`, or (shape unknown) a pointer or wide window | top bar, picture, bottom bar (transport, tools, filmstrip), none overlapping |
| `overlay` | otherwise — a phone on its side, mostly | picture edge to edge, bars float over it and hide (`ChromePolicy`) |
| `tabletop` | half-folded | picture above the fold, top bar over it; transport and filmstrip on the deck |

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

## Use

```dart
MaterialApp(
  builder: (context, child) => ViewportScope(child: child!),
);

final viewport = ScreenViewport.of(context);
final screen = ScreenClass.of(viewport);

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
| Holes | measured table (`punchHoleOf`) | `DisplayFeatureType.cutout` |
| Tabletop | `UIHinge` (iOS 27.1+, plugin), inner screen in portrait, 30°–135° | `DisplayFeature` fold or hinge, `postureHalfOpened`, horizontal |
| Crease | — | vertical fold half-opened, or any vertical hinge |

`FoldPosture.simulateTabletop` splits any window, for simulators that cannot
fold.

## Testing a layout

`package:adaptive_viewport/testing.dart` has `ScreenProfile.all`: iPhones
with and without an island, the iPhone Duo's cover and inner screens (flat
and half-folded), the Galaxy Z Flip and Fold in each posture, Pixel phones
and the Pixel Fold, iPads (including Split View), an Android tablet, and
macOS, Windows and Linux windows from narrow to full screen — each as the
window Flutter reports, on its platform. Run a layout over all of them; the
planner tests do so for every scenario, in both text directions.
