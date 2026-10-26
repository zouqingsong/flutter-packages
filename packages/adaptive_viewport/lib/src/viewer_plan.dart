import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'fold_posture.dart';
import 'screen_class.dart';
import 'viewport.dart';

/// How a viewer's bars sit against its picture.
enum ViewerMode {
  /// The picture has the whole window and the bars float over it, coming
  /// and going ([ChromePolicy]). Where keeping them beside the picture would
  /// cost it a good part of its size: a phone, mostly.
  overlay,

  /// The bars above and below the picture, never over it. Where the window
  /// has the room anyway (a letterboxed picture, a large window), or the
  /// picture must not be covered.
  docked,

  /// A foldable half-open like a laptop: the picture alone above the fold,
  /// and on the deck below it, from the fold down, the top bar, the open
  /// tool palette and the bottom bar — the order a live stage's deck uses.
  tabletop,
}

/// What the viewer planner needs besides the [viewport].
@immutable
class ViewerRequest {
  const ViewerRequest({
    required this.viewport,
    this.chromeShown = true,
    this.textDirection = TextDirection.ltr,
    this.mediaAspect,
    this.topBarHeight = 56,
    this.bottomBarHeight = 64,
    this.filmstripHeight = 0,
    this.panel = false,
    this.panelWidth = 320,
    this.keepPictureClear = false,
    this.toolsHeight = 0,
  });

  final ScreenViewport viewport;

  /// False for full screen: the picture alone.
  final bool chromeShown;

  final TextDirection textDirection;

  /// Width over height of what is shown, when known. It decides whether the
  /// bars fit in the picture's letterbox.
  final double? mediaAspect;

  /// Height of the top bar (back, title, actions), without the safe area.
  final double topBarHeight;

  /// Height of the bottom bar (transport, tools), without the safe area.
  final double bottomBarHeight;

  /// Height of a strip of neighbouring items under the bottom bar; 0 for
  /// none.
  final double filmstripHeight;

  /// Whether the app wants its side panel (details, series, measurements)
  /// shown. It is, where there is room for it beside the picture.
  final bool panel;

  /// Widest the side panel gets.
  final double panelWidth;

  /// Never put a bar over the picture: diagnostic images, measurements.
  final bool keepPictureClear;

  /// Height of the tool palette that is open (drawing, processing), or 0.
  /// It goes where [ViewerPlan.tools] says.
  final double toolsHeight;
}

/// Where a viewer's picture, bars and panel go, in window coordinates.
@immutable
class ViewerPlan {
  const ViewerPlan({
    required this.mode,
    required this.screen,
    required this.chrome,
    required this.window,
    required this.picture,
    required this.topBar,
    required this.bottomBar,
    required this.topBarPadding,
    required this.bottomBarPadding,
    required this.panel,
    required this.panelPadding,
    required this.deck,
    required this.overlayInsets,
    required this.fold,
    this.tools,
  });

  final ViewerMode mode;
  final ScreenClass screen;

  /// How the bars get out of the way and come back.
  final ChromePolicy chrome;

  final Size window;

  /// The picture's box. The media is fitted inside it.
  final Rect picture;

  /// Null in full screen. Includes the safe area on its outer edge; lay its
  /// contents out inside [topBarPadding].
  final Rect? topBar;

  /// The transport and tools, with the filmstrip under them. Null in full
  /// screen.
  final Rect? bottomBar;

  final EdgeInsets topBarPadding;
  final EdgeInsets bottomBarPadding;

  /// The side panel, where it is shown.
  final Rect? panel;
  final EdgeInsets panelPadding;

  /// Tabletop: the deck below the fold.
  final Rect? deck;

  /// Insets inside [picture] that a floating tool (a drawing toolbar, a
  /// zoom control) keeps: clear of the bars over it and of the safe area.
  final EdgeInsets overlayInsets;

  final TabletopFold? fold;

  /// Where the open tool palette goes, inset from the window's edges and its
  /// safe area: just above the bottom bar, or on the deck between the two
  /// bars. Null with none open ([ViewerRequest.toolsHeight] 0) or in full
  /// screen.
  final Rect? tools;

  bool get fullscreen => topBar == null;
}

/// Turns a [ViewerRequest] into a [ViewerPlan]. Pure.
///
/// The rules:
///
/// 1. The picture is as big as the window allows. Its bars go above and
///    below it when that costs the fitted picture no more than
///    [dockLoss] of its area (they sit in its letterbox), or when the
///    picture must stay clear; otherwise they float over it and get out of
///    its way ([ChromePolicy]).
/// 2. The bars keep the whole safe area on their outer edges, so nothing in
///    them meets a notch, island, hole or home indicator — except a side
///    inset a camera hole accounts for (the iPhone Duo's cover screen), which
///    only a bar beside the hole or its read-outs keeps.
/// 3. A side panel is shown only beside the picture, never over it: on a
///    wide window, or on the far side of a book crease.
/// 4. Half-folded, the picture is above the fold, and everything that is
///    pressed below it: the top bar at the fold, the open tool palette under
///    it, then the bottom bar centred in what is left — the order the live
///    stage's deck uses, so the two screens put the same things in the same
///    places. Nothing on the crease.
/// 5. Full screen is the picture alone, edge to edge.
/// 6. An open tool palette sits just above the bottom bar, the same place a
///    live stage puts its tools: at the foot of the picture, over it.
abstract final class ViewerPlanner {
  /// The share of the fitted picture the bars may cost before they float
  /// over it instead.
  static const double dockLoss = 0.1;

  /// Narrowest a side panel is worth showing at.
  static const double minPanelWidth = 240;

  /// Between a tool palette and the window's edges or a bar.
  static const double toolsMargin = 8;

  /// From a tool palette's sides to the window's edges.
  static const double toolsSide = 16;

  static ViewerPlan plan(ViewerRequest request) {
    final viewport = request.viewport;
    final screen = ScreenClass.of(viewport);
    final chrome = ChromePolicy.of(screen.input);
    final window = viewport.size;
    final padding = viewport.padding;
    final rtl = request.textDirection == TextDirection.rtl;
    final whole = Offset.zero & window;
    final fullscreen = !request.chromeShown;
    final fold = screen.posture == Posture.tabletop ? viewport.tabletop : null;

    final topPadding = EdgeInsets.fromLTRB(
      padding.left,
      padding.top,
      padding.right,
      0,
    );
    final bottomPadding = EdgeInsets.fromLTRB(
      padding.left,
      0,
      padding.right,
      padding.bottom,
    );

    // Rule 4: the picture has the upright half to itself, and everything
    // that is pressed is on the deck, where the hand is — the top bar's back
    // button and name first, from the fold down, then the transport.
    if (fold != null) {
      final picture = Rect.fromLTRB(0, 0, window.width, fold.top);
      final deck = Rect.fromLTRB(0, fold.bottom, window.width, window.height);
      final deckBottom = deck.bottom - padding.bottom;
      final topBar = fullscreen
          ? null
          : Rect.fromLTWH(0, deck.top, window.width,
              math.min(request.topBarHeight, deck.height / 2));
      Rect? tools;
      Rect? bottomBar;
      if (topBar != null) {
        final bottomHeight = math.min(
          request.bottomBarHeight + request.filmstripHeight,
          deckBottom - topBar.bottom,
        );
        if (request.toolsHeight > 0) {
          tools = Rect.fromLTRB(
            padding.left + toolsSide,
            topBar.bottom + toolsMargin,
            window.width - padding.right - toolsSide,
            topBar.bottom + toolsMargin + request.toolsHeight,
          );
        }
        // Centred in what the top bar and the tools leave, as the live
        // stage centres its toolbar; never pushed off the deck.
        final above = tools == null ? topBar.bottom : tools.bottom;
        final room = deckBottom - above;
        final top = math.min(
          above + math.max(0.0, (room - bottomHeight) / 2),
          deckBottom - bottomHeight,
        );
        bottomBar = Rect.fromLTWH(
          0,
          math.max(topBar.bottom, top),
          window.width,
          bottomHeight,
        );
      }
      return ViewerPlan(
        mode: ViewerMode.tabletop,
        screen: screen,
        chrome: chrome,
        window: window,
        picture: picture,
        topBar: topBar,
        bottomBar: bottomBar,
        tools: tools,
        topBarPadding: EdgeInsets.fromLTRB(padding.left, 0, padding.right, 0),
        bottomBarPadding:
            EdgeInsets.fromLTRB(padding.left, 0, padding.right, 0),
        panel: null,
        panelPadding: EdgeInsets.zero,
        deck: deck,
        overlayInsets: EdgeInsets.fromLTRB(
          padding.left,
          padding.top,
          padding.right,
          0,
        ),
        fold: fold,
      );
    }

    // Rule 5.
    if (fullscreen) {
      return ViewerPlan(
        mode: ViewerMode.overlay,
        screen: screen,
        chrome: chrome,
        window: window,
        picture: whole,
        topBar: null,
        bottomBar: null,
        topBarPadding: topPadding,
        bottomBarPadding: bottomPadding,
        panel: null,
        panelPadding: EdgeInsets.zero,
        deck: null,
        overlayInsets: padding,
        fold: null,
      );
    }

    // Rule 3.
    var area = whole;
    Rect? panel;
    final crease = viewport.crease;
    if (request.panel && crease != null) {
      area = rtl
          ? Rect.fromLTRB(crease.right, 0, window.width, window.height)
          : Rect.fromLTRB(0, 0, crease.left, window.height);
      panel = rtl
          ? Rect.fromLTRB(0, 0, crease.left, window.height)
          : Rect.fromLTRB(crease.right, 0, window.width, window.height);
    } else if (request.panel && screen.isWide) {
      final width = math.max(
        minPanelWidth,
        math.min(request.panelWidth, window.width * 0.3),
      );
      panel = rtl
          ? Rect.fromLTWH(0, 0, width, window.height)
          : Rect.fromLTWH(window.width - width, 0, width, window.height);
      area = rtl
          ? Rect.fromLTRB(width, 0, window.width, window.height)
          : Rect.fromLTRB(0, 0, window.width - width, window.height);
    }

    // Rule 2: a side inset a camera hole accounts for is kept only by what
    // lies beside the hole (or the read-outs drawn next to it).
    final holes = viewport.holes;
    double side(Rect rect, double inset, double from, double to) {
      if (inset <= 0) return 0;
      final column = Rect.fromLTRB(from, 0, to, window.height);
      if (!holes.any((hole) => hole.overlaps(column))) return inset;
      final beside = Rect.fromLTRB(from, rect.top, to, rect.bottom);
      return holes.any((hole) => hole.overlaps(beside)) ? inset : 0;
    }

    EdgeInsets sides(Rect rect, EdgeInsets base) => EdgeInsets.fromLTRB(
          rect.left <= 0 ? side(rect, padding.left, 0, padding.left) : 0,
          base.top,
          rect.right >= window.width
              ? side(rect, padding.right, window.width - padding.right,
                  window.width)
              : 0,
          base.bottom,
        );

    // Rule 1.
    final topBar = Rect.fromLTWH(
      area.left,
      0,
      area.width,
      padding.top + request.topBarHeight,
    );
    final bottomHeight =
        padding.bottom + request.bottomBarHeight + request.filmstripHeight;
    final bottomBar = Rect.fromLTWH(
      area.left,
      window.height - bottomHeight,
      area.width,
      bottomHeight,
    );
    final between = Rect.fromLTRB(
      area.left,
      topBar.bottom,
      area.right,
      math.max(topBar.bottom, bottomBar.top),
    );
    final aspect = request.mediaAspect;
    final bool docked;
    if (request.keepPictureClear) {
      docked = true;
    } else if (aspect != null && aspect > 0) {
      final over = _fittedArea(area.size, aspect);
      docked = over > 0 &&
          _fittedArea(between.size, aspect) >= over * (1 - dockLoss);
    } else {
      docked = (screen.isPointer || screen.isWide) && !screen.compactHeight;
    }

    final picture = docked ? between : area;
    Rect toolsIn(Rect area, double above) {
      final row = Rect.fromLTRB(
        area.left,
        above - toolsMargin - request.toolsHeight,
        area.right,
        above - toolsMargin,
      );
      final inset = sides(row, EdgeInsets.zero);
      return Rect.fromLTRB(
        row.left + inset.left + toolsSide,
        row.top,
        row.right - inset.right - toolsSide,
        row.bottom,
      );
    }

    return ViewerPlan(
      mode: docked ? ViewerMode.docked : ViewerMode.overlay,
      screen: screen,
      chrome: chrome,
      window: window,
      picture: picture,
      topBar: topBar,
      bottomBar: bottomBar,
      topBarPadding: sides(topBar, topPadding),
      bottomBarPadding: sides(bottomBar, bottomPadding),
      panel: panel,
      panelPadding: panel == null
          ? EdgeInsets.zero
          : sides(
              panel, EdgeInsets.only(top: padding.top, bottom: padding.bottom)),
      deck: null,
      overlayInsets: sides(
        area,
        docked
            ? EdgeInsets.zero
            : EdgeInsets.only(top: topBar.height, bottom: bottomBar.height),
      ),
      fold: null,
      tools: request.toolsHeight > 0 ? toolsIn(area, bottomBar.top) : null,
    );
  }

  static double _fittedArea(Size box, double aspect) {
    if (box.isEmpty) return 0;
    final width = math.min(box.width, box.height * aspect);
    return width * (width / aspect);
  }
}
