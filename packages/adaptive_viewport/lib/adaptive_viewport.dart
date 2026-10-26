/// What a screen leaves an app to lay out in, and pure planners that turn it
/// into the layout of each media scenario.
///
/// * [ViewportScope] — put it once in `MaterialApp.builder`.
/// * [ScreenViewport.of] — safe area, holes, folds, from what the system reports.
/// * [BoxViewportBuilder] — the same, for the box a page actually has (below
///   an app bar, beside a sidebar), so nothing it plans falls off the screen.
/// * [ScreenClass.of] — width class, input and posture: what kind of window.
/// * [StagePlanner.plan] — live preview: a picture-first stage with controls.
/// * [ViewerPlanner.plan] — one image or video, with its bars and panel.
/// * [GalleryPlanner.plan] — a grid of items, with the open one beside it.
/// * [ControlsPlanner.plan] — a bar's or a rail's groups, folded so none of
///   them has to be scrolled to.
/// * [PalettePlanner.plan] — a tool palette's groups, folded and wrapped onto
///   as few rows as fit, never scrolled.
/// * [TabletopLayout] — picture above the fold, deck below, without
///   rebuilding the picture.
library;

export 'src/controls_plan.dart';
export 'src/display_housing.dart' show DisplayHousing;
export 'src/fold_posture.dart';
export 'src/gallery_plan.dart';
export 'src/palette_plan.dart';
export 'src/screen_class.dart';
export 'src/stage_plan.dart';
export 'src/viewer_plan.dart';
export 'src/viewport.dart';
