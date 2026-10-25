import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import 'screen_class.dart';
import 'viewport.dart';

/// How a gallery shares its window with the item it has open.
enum GalleryMode {
  /// The grid alone.
  single,

  /// The grid in a pane on the leading side, the open item beside it: a
  /// wide window, or the two halves of a book fold.
  split,

  /// Half-folded like a laptop: the open item above the fold, the grid on
  /// the deck below.
  tabletop,
}

/// What the gallery planner needs besides the [viewport].
@immutable
class GalleryRequest {
  const GalleryRequest({
    required this.viewport,
    this.textDirection = TextDirection.ltr,
    this.bodyTop = 0,
    this.detail = false,
    this.bottomBarHeight = 0,
    this.spacing = 4,
    this.margin = 12,
    this.minTileExtent,
  });

  final ScreenViewport viewport;
  final TextDirection textDirection;

  /// Where the gallery's body starts in the window: the height of an app bar
  /// above it (which keeps the top safe area itself), or 0.
  final double bodyTop;

  /// Whether the app can show the open item beside the grid. Where the
  /// window has room for both, the plan has a [GalleryPlan.detail] pane —
  /// with nothing open, the app shows a hint or the latest item there.
  final bool detail;

  /// A selection or action bar along the bottom; 0 for none.
  final double bottomBarHeight;

  final double spacing;

  /// Space around the grid, inside the safe area.
  final double margin;

  /// Smallest a tile may be; by default from the width class.
  final double? minTileExtent;
}

/// Where a gallery's grid and open item go, in the coordinates of its body
/// (the window below [GalleryRequest.bodyTop]).
@immutable
class GalleryPlan {
  const GalleryPlan({
    required this.mode,
    required this.screen,
    required this.body,
    required this.grid,
    required this.gridPadding,
    required this.columns,
    required this.tileExtent,
    required this.spacing,
    required this.detail,
    required this.detailPadding,
    required this.bottomBar,
    required this.bottomBarPadding,
  });

  final GalleryMode mode;
  final ScreenClass screen;
  final Size body;

  /// The grid's box. It scrolls edge to edge in it; [gridPadding] keeps the
  /// tiles at rest clear of the safe area and the bottom bar.
  final Rect grid;
  final EdgeInsets gridPadding;

  final int columns;
  final double tileExtent;
  final double spacing;

  /// The open item's pane, where there is one.
  final Rect? detail;
  final EdgeInsets detailPadding;

  /// The selection or action bar, safe area included.
  final Rect? bottomBar;
  final EdgeInsets bottomBarPadding;

  SliverGridDelegate get delegate => SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: spacing,
        crossAxisSpacing: spacing,
      );
}

/// Turns a [GalleryRequest] into a [GalleryPlan]. Pure.
///
/// The rules:
///
/// 1. The grid scrolls under the system bars, edge to edge; its padding
///    keeps the tiles at rest clear of the safe area on the edges it
///    reaches, and of the bottom bar.
/// 2. Columns come from the width the grid has, at no less than the width
///    class's smallest tile ([minTileFor]); never fewer than two. So a
///    phone shows three or four, a tablet five or six, a desktop window as
///    many as fit — with no device in the rule.
/// 3. The open item goes beside the grid on a wide window, and on the far
///    half of a book fold, split at the crease. A phone on its side keeps
///    one pane.
/// 4. Half-folded, the open item is above the fold and the grid on the
///    deck.
abstract final class GalleryPlanner {
  /// Narrowest and widest the grid pane gets beside an open item.
  static const double minGridPane = 320;
  static const double maxGridPane = 480;

  static double minTileFor(WidthClass width) => switch (width) {
        WidthClass.compact => 104,
        WidthClass.medium => 128,
        WidthClass.expanded || WidthClass.large => 152,
      };

  static GalleryPlan plan(GalleryRequest request) {
    final viewport = request.viewport;
    final screen = ScreenClass.of(viewport);
    final padding = viewport.padding;
    final window = viewport.size;
    final rtl = request.textDirection == TextDirection.rtl;
    final bodyTop = request.bodyTop;
    final body = Size(window.width, math.max(0, window.height - bodyTop));
    final whole = Offset.zero & body;
    // The safe area as it reaches the body: an app bar above keeps the top.
    final safe = EdgeInsets.fromLTRB(
      padding.left,
      bodyTop > 0 ? 0 : padding.top,
      padding.right,
      padding.bottom,
    );

    var mode = GalleryMode.single;
    var grid = whole;
    Rect? detail;
    final fold = screen.posture == Posture.tabletop ? viewport.tabletop : null;
    final crease = viewport.crease;
    if (request.detail && fold != null && fold.top - bodyTop > 0) {
      // Rule 4.
      mode = GalleryMode.tabletop;
      detail = Rect.fromLTRB(0, 0, body.width, fold.top - bodyTop);
      grid = Rect.fromLTRB(0, fold.bottom - bodyTop, body.width, body.height);
    } else if (request.detail && crease != null) {
      // Rule 3, at the crease.
      mode = GalleryMode.split;
      grid = rtl
          ? Rect.fromLTRB(crease.right, 0, body.width, body.height)
          : Rect.fromLTRB(0, 0, crease.left, body.height);
      detail = rtl
          ? Rect.fromLTRB(0, 0, crease.left, body.height)
          : Rect.fromLTRB(crease.right, 0, body.width, body.height);
    } else if (request.detail && screen.isWide) {
      mode = GalleryMode.split;
      final width = (body.width * 0.4).clamp(minGridPane, maxGridPane);
      grid = rtl
          ? Rect.fromLTWH(body.width - width, 0, width, body.height)
          : Rect.fromLTWH(0, 0, width, body.height);
      detail = rtl
          ? Rect.fromLTRB(0, 0, body.width - width, body.height)
          : Rect.fromLTRB(width, 0, body.width, body.height);
    }

    // Rule 1: the safe area on the edges a pane reaches.
    EdgeInsets reach(Rect rect) => EdgeInsets.fromLTRB(
          rect.left <= 0 ? safe.left : 0,
          rect.top <= 0 ? safe.top : 0,
          rect.right >= body.width ? safe.right : 0,
          rect.bottom >= body.height ? safe.bottom : 0,
        );

    final gridSafe = reach(grid);
    final bar = request.bottomBarHeight;
    final bottomBar = bar > 0
        ? Rect.fromLTRB(
            grid.left,
            grid.bottom - gridSafe.bottom - bar,
            grid.right,
            grid.bottom,
          )
        : null;
    final m = request.margin;
    final gridPadding = EdgeInsets.fromLTRB(
      m + gridSafe.left,
      m + gridSafe.top,
      m + gridSafe.right,
      m + gridSafe.bottom + bar,
    );

    // Rule 2.
    final spacing = request.spacing;
    final minTile = request.minTileExtent ?? minTileFor(screen.width);
    final available = math.max(0.0, grid.width - gridPadding.horizontal);
    final columns =
        math.max(2, ((available + spacing) / (minTile + spacing)).floor());
    final tileExtent =
        math.max(0.0, (available - spacing * (columns - 1)) / columns);

    return GalleryPlan(
      mode: mode,
      screen: screen,
      body: body,
      grid: grid,
      gridPadding: gridPadding,
      columns: columns,
      tileExtent: tileExtent,
      spacing: spacing,
      detail: detail,
      detailPadding: detail == null ? EdgeInsets.zero : reach(detail),
      bottomBar: bottomBar,
      bottomBarPadding: EdgeInsets.fromLTRB(
        gridSafe.left,
        0,
        gridSafe.right,
        gridSafe.bottom,
      ),
    );
  }
}
