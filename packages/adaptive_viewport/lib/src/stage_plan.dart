import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'fold_posture.dart';
import 'viewport.dart';

/// How a media stage — a live picture with controls around it — is arranged
/// in a window. Decided by [StagePlanner.plan] from the window's shape, not
/// from which device it is.
enum StageMode {
  /// A wide window (tablet, desktop, an unfolded phone held sideways): the
  /// picture is framed in its pane with the controls in a bar below.
  framed,

  /// An upright phone: the picture across the top, a bar of controls below,
  /// read-outs in the black band above a letterboxed picture.
  column,

  /// A phone on its side: the picture has the whole window and the controls
  /// float over its trailing edge in a rail.
  docked,

  /// A foldable half-open like a laptop: the picture alone above the fold,
  /// and every control — zoom and drawing tools included — on the deck below
  /// it, nothing on the crease.
  tabletop,
}

/// What the planner needs to know besides the [viewport].
@immutable
class StageRequest {
  const StageRequest({
    required this.viewport,
    required this.wide,
    this.fullscreen = false,
    this.textDirection = TextDirection.ltr,
    this.topChrome = false,
    this.hasRail = true,
    this.railWidth = 76,
    this.railExtra = 0,
  });

  final ScreenViewport viewport;

  /// Whether the app gives this window its wide layout (a sidebar, a framed
  /// picture). The breakpoint is the app's.
  final bool wide;

  /// Picture only, edge to edge.
  final bool fullscreen;

  final TextDirection textDirection;

  /// Whether something above the stage (an app bar) already keeps it clear
  /// of the top of the screen. Without it the stage reaches the top edge and
  /// the plan places a floating menu button.
  final bool topChrome;

  /// Whether a docked stage shows its rail.
  final bool hasRail;

  /// Width of the docked rail, before the safe-area inset it adds.
  final double railWidth;

  /// Width of whatever is docked beside the rail (a gallery panel).
  final double railExtra;
}

/// Where everything over and around a stage's picture goes, in the stage's
/// coordinates — the window's whenever the stage fills it (docked, tabletop,
/// full screen); under an app bar or in a framed pane, from the stage's own
/// top-left. [menuStart] is from the leading edge.
@immutable
class StagePlan {
  const StagePlan({
    required this.mode,
    required this.fullscreen,
    required this.window,
    required this.safe,
    required this.overlayInsets,
    required this.railBeside,
    required this.railOnLeft,
    required this.railExtent,
    required this.railPadding,
    required this.floatingMenu,
    required this.menuStart,
    required this.menuTop,
    required this.badgeLeft,
    required this.badgeTop,
    required this.actionsTop,
    required this.actionsRight,
    required this.deckPadding,
    required this.fold,
    required this.obstacles,
  });

  final StageMode mode;
  final bool fullscreen;
  final Size window;

  /// The window edges the picture reaches, as insets its overlays keep: the
  /// safe area on those edges, less any side inset a known hole accounts for
  /// (the controls step around the hole instead).
  final EdgeInsets safe;

  /// [safe] plus the docked rail on its side.
  final EdgeInsets overlayInsets;

  final bool railBeside;
  final bool railOnLeft;

  /// Width the rail (and anything docked beside it) takes from the trailing
  /// edge, its inset included.
  final double railExtent;

  /// The safe area the rail lays its groups out in: [safe], with a hole in
  /// the rail's column as a top or bottom inset.
  final EdgeInsets railPadding;

  /// Whether the stage reaches the top-leading corner with no app bar above
  /// it, so the way to the navigation floats over the picture.
  final bool floatingMenu;
  final double menuStart;
  final double menuTop;

  /// Top-left of the recording badge, when it is over the picture.
  final double badgeLeft;
  final double badgeTop;

  /// Full screen: the top and right of the floating action column.
  final double actionsTop;
  final double actionsRight;

  /// Tabletop: insets inside the deck below the fold.
  final EdgeInsets deckPadding;

  /// Tabletop: the fold, in window coordinates.
  final TabletopFold? fold;

  /// Everything a control has to stay off.
  final List<Rect> obstacles;

  bool get isTabletop => mode == StageMode.tabletop;
}

/// Turns a [StageRequest] into a [StagePlan]. Pure: the rules are here once,
/// and a test can run them over any screen.
///
/// The rules:
///
/// 1. The picture is as big as the window allows: edge to edge in
///    [StageMode.docked] and full screen, with the controls *over* it rather
///    than beside it.
/// 2. Overlays keep the safe area of the edges the picture reaches, and only
///    those. A side inset that a camera hole accounts for is given back; the
///    controls near that hole step around it instead.
/// 3. A half-folded foldable gets the picture above the fold and the
///    controls below; nothing goes on the crease.
/// 4. A control that would land on an obstacle moves along the edge it is
///    on — never into the picture's middle.
abstract final class StagePlanner {
  /// Size of the floating menu button.
  static const double menuSize = 48;

  /// Room the recording badge needs, for clearing holes.
  static const Size badgeSize = Size(96, 32);

  /// Width of the full-screen action column.
  static const double actionsWidth = 48;

  /// Gap kept between a control and an obstacle.
  static const double clearance = 4;

  static StagePlan plan(StageRequest request) {
    final viewport = request.viewport;
    final window = viewport.size;
    final padding = viewport.padding;
    final rtl = request.textDirection == TextDirection.rtl;
    final holes = viewport.holes;

    final mode = viewport.tabletop != null && !request.wide
        ? StageMode.tabletop
        : request.wide
            ? StageMode.framed
            : viewport.isLandscape
                ? StageMode.docked
                : StageMode.column;
    final fullscreen = request.fullscreen;

    // Rule 2: the edges the picture reaches.
    final top = request.topChrome ? 0.0 : padding.top;
    var safe = switch (mode) {
      _ when fullscreen => padding,
      StageMode.framed => EdgeInsets.zero,
      StageMode.docked => padding,
      StageMode.column || StageMode.tabletop => EdgeInsets.fromLTRB(
          padding.left,
          top,
          padding.right,
          0,
        ),
    };
    safe = _giveBackHoleSides(safe, window, holes);

    final railBeside =
        mode == StageMode.docked && !fullscreen && request.hasRail;
    final railOnLeft = railBeside && rtl;
    final railExtent = railBeside
        ? request.railWidth +
            (railOnLeft ? safe.left : safe.right) +
            request.railExtra
        : 0.0;
    final overlayInsets = EdgeInsets.fromLTRB(
      railOnLeft ? railExtent : safe.left,
      safe.top,
      railBeside && !railOnLeft ? railExtent : safe.right,
      safe.bottom,
    );

    final railPadding = _railPadding(
      safe,
      window,
      holes,
      request.railWidth,
      rtl,
    );

    // Rule 4, for the top-leading corner: the menu, then the badge beside it.
    final floatingMenu = !request.topChrome && !request.wide && !fullscreen;
    var menuStart = 8 + (rtl ? safe.right : safe.left);
    final menuTop = 8 + safe.top;
    if (floatingMenu) {
      final menu = Rect.fromLTWH(
        rtl ? window.width - menuStart - menuSize : menuStart,
        menuTop,
        menuSize,
        menuSize,
      );
      final moved = stepPast(
        menu,
        holes,
        rtl ? AxisDirection.left : AxisDirection.right,
      );
      menuStart = rtl ? window.width - moved.right : moved.left;
    }

    final badgeTop = 12 + overlayInsets.top;
    final badgeStart = floatingMenu && !rtl
        ? menuStart + menuSize + clearance
        : 12 + overlayInsets.left;
    final badgeLeft = stepPast(
      Offset(badgeStart, badgeTop) & badgeSize,
      holes,
      AxisDirection.right,
    ).left;

    // The full-screen actions run down the trailing edge from the top.
    final actionsRight = 12 + overlayInsets.right;
    final actionsTop = stepPast(
      Rect.fromLTWH(
        window.width - actionsRight - actionsWidth,
        12 + overlayInsets.top,
        actionsWidth,
        window.height / 2,
      ),
      holes,
      AxisDirection.down,
    ).top;

    final deckPadding = mode == StageMode.tabletop
        ? EdgeInsets.fromLTRB(padding.left, 0, padding.right, padding.bottom)
        : EdgeInsets.zero;

    return StagePlan(
      mode: mode,
      fullscreen: fullscreen,
      window: window,
      safe: safe,
      overlayInsets: overlayInsets,
      railBeside: railBeside,
      railOnLeft: railOnLeft,
      railExtent: railExtent,
      railPadding: railPadding,
      floatingMenu: floatingMenu,
      menuStart: menuStart,
      menuTop: menuTop,
      badgeLeft: badgeLeft,
      badgeTop: badgeTop,
      actionsTop: actionsTop,
      actionsRight: actionsRight,
      deckPadding: deckPadding,
      fold: mode == StageMode.tabletop ? viewport.tabletop : null,
      obstacles: viewport.obstacles,
    );
  }

  /// [rect] moved in [direction] until it clears every obstacle by
  /// [clearance] plus [gap]. Unmoved when it already does.
  static Rect stepPast(
    Rect rect,
    Iterable<Rect> obstacles,
    AxisDirection direction, {
    double gap = 2,
  }) {
    var result = rect;
    // Each pass clears one obstacle; one past it can land on the next.
    for (var pass = 0; pass <= obstacles.length; pass++) {
      Rect? hit;
      for (final obstacle in obstacles) {
        if (result.overlaps(obstacle.inflate(clearance))) {
          hit = obstacle;
          break;
        }
      }
      if (hit == null) return result;
      final step = clearance + gap;
      result = switch (direction) {
        AxisDirection.right => result.shift(
            Offset(hit.right + step - result.left, 0),
          ),
        AxisDirection.left => result.shift(
            Offset(hit.left - step - result.right, 0),
          ),
        AxisDirection.down => result.shift(
            Offset(0, hit.bottom + step - result.top),
          ),
        AxisDirection.up => result.shift(
            Offset(0, hit.top - step - result.bottom),
          ),
      };
    }
    return result;
  }

  /// [safe] without a side inset that a hole inside it accounts for. UIKit
  /// reserves the whole edge a hole is on, in landscape; the controls that
  /// can reach the hole step around it instead.
  static EdgeInsets _giveBackHoleSides(
    EdgeInsets safe,
    Size window,
    List<Rect> holes,
  ) {
    if (holes.isEmpty) return safe;
    bool explains(Rect strip) =>
        !strip.isEmpty && holes.any((hole) => hole.overlaps(strip));
    final left = explains(Rect.fromLTWH(0, 0, safe.left, window.height));
    final right = explains(
      Rect.fromLTWH(window.width - safe.right, 0, safe.right, window.height),
    );
    if (!left && !right) return safe;
    return safe.copyWith(left: left ? 0 : null, right: right ? 0 : null);
  }

  static EdgeInsets _railPadding(
    EdgeInsets safe,
    Size window,
    List<Rect> holes,
    double railWidth,
    bool rtl,
  ) {
    var result = safe;
    final column = rtl
        ? Rect.fromLTWH(0, 0, railWidth, window.height)
        : Rect.fromLTWH(window.width - railWidth, 0, railWidth, window.height);
    for (final hole in holes) {
      if (!column.overlaps(hole)) continue;
      // Less the rail's own 10 pt margin, plus 4 to stand clear of the hole.
      result = hole.center.dy > window.height / 2
          ? result.copyWith(
              bottom: math.max(result.bottom, window.height - hole.top - 6),
            )
          : result.copyWith(top: math.max(result.top, hole.bottom - 6));
    }
    return result;
  }
}
