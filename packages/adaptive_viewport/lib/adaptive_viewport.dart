/// What a screen leaves an app to lay out in, and pure planners that turn it
/// into the layout of each media scenario.
///
/// * [ViewportScope] — put it once in `MaterialApp.builder`.
/// * [ScreenViewport.of] — safe area, holes, folds, from what the system reports.
/// * [ScreenClass.of] — width class, input and posture: what kind of window.
/// * [StagePlanner.plan] — live preview: a picture-first stage with controls.
/// * [ViewerPlanner.plan] — one image or video, with its bars and panel.
/// * [GalleryPlanner.plan] — a grid of items, with the open one beside it.
/// * [TabletopLayout] — picture above the fold, deck below, without
///   rebuilding the picture.
library;

export 'src/display_housing.dart' show DisplayHousing;
export 'src/fold_posture.dart';
export 'src/gallery_plan.dart';
export 'src/screen_class.dart';
export 'src/stage_plan.dart';
export 'src/viewer_plan.dart';
export 'src/viewport.dart';
