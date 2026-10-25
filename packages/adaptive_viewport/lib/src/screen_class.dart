import 'package:flutter/foundation.dart';

import 'viewport.dart';

/// The window's width, in the Material 3 window size classes. A class, not a
/// device: an iPad in Split View is compact, a phone on its side is expanded.
enum WidthClass {
  /// Under 600: a phone upright, a cover screen, a narrow desktop window.
  compact,

  /// 600 to 839: a tablet or an unfolded foldable upright.
  medium,

  /// 840 to 1199: a tablet on its side, a phone on its side (with a compact
  /// height), a desktop window.
  expanded,

  /// 1200 and over.
  large;

  static WidthClass of(double width) => width < 600
      ? compact
      : width < 840
          ? medium
          : width < 1200
              ? expanded
              : large;

  bool atLeast(WidthClass other) => index >= other.index;
}

/// How the controls are reached.
enum InputKind {
  /// Fingers: targets of 44 pt and more; the controls come back on a tap.
  touch,

  /// A mouse or trackpad: hover; the controls come back when it moves.
  pointer,
}

/// How a foldable is being held. Flat for everything else.
enum Posture {
  flat,

  /// Half-open like a laptop: the window splits across a horizontal fold.
  tabletop,

  /// Half-open like a book, or with a hinge down the middle: a vertical
  /// crease nothing should sit on.
  book,
}

/// What kind of window a layout is in, from its shape, its posture and the
/// platform's input. Every scenario planner starts from this, so that the
/// same window gets the same answer in each app.
@immutable
class ScreenClass {
  const ScreenClass({
    required this.width,
    required this.compactHeight,
    required this.landscape,
    required this.input,
    required this.posture,
  });

  factory ScreenClass.of(ScreenViewport viewport) {
    final platform = viewport.platform ?? defaultTargetPlatform;
    // In a browser too, the platform it reports decides: there is no telling
    // a touch laptop from the window.
    final pointer = platform == TargetPlatform.macOS ||
        platform == TargetPlatform.windows ||
        platform == TargetPlatform.linux;
    return ScreenClass(
      width: WidthClass.of(viewport.size.width),
      compactHeight: viewport.size.height < compactHeightLimit,
      landscape: viewport.isLandscape,
      input: pointer ? InputKind.pointer : InputKind.touch,
      posture: viewport.tabletop != null
          ? Posture.tabletop
          : viewport.crease != null
              ? Posture.book
              : Posture.flat,
    );
  }

  /// Below this height a window cannot afford chrome above *and* below its
  /// content: a phone on its side, a short desktop window.
  static const double compactHeightLimit = 480;

  final WidthClass width;
  final bool compactHeight;
  final bool landscape;
  final InputKind input;
  final Posture posture;

  bool get isPointer => input == InputKind.pointer;

  /// Room for two panes side by side: an expanded width with the height to
  /// make each pane useful. A phone on its side is wide but short, and keeps
  /// one pane with its controls along the trailing edge.
  bool get isWide => width.atLeast(WidthClass.expanded) && !compactHeight;

  /// A phone on its side, or anything as short: the controls go beside the
  /// content rather than above and below it.
  bool get isShortLandscape => landscape && compactHeight;

  @override
  bool operator ==(Object other) =>
      other is ScreenClass &&
      other.width == width &&
      other.compactHeight == compactHeight &&
      other.landscape == landscape &&
      other.input == input &&
      other.posture == posture;

  @override
  int get hashCode =>
      Object.hash(width, compactHeight, landscape, input, posture);

  @override
  String toString() => 'ScreenClass(${width.name}'
      '${compactHeight ? ', short' : ''}, ${input.name}, ${posture.name})';
}

/// When a picture's controls get out of its way, and how they come back.
/// Touch and pointer differ; the screen does not.
@immutable
class ChromePolicy {
  const ChromePolicy._({
    required this.revealOnTap,
    required this.revealOnHover,
    required this.hideAfter,
  });

  static ChromePolicy of(InputKind input) =>
      input == InputKind.pointer ? pointer : touch;

  /// A tap on the picture shows the controls, or hides them if shown.
  static const touch = ChromePolicy._(
    revealOnTap: true,
    revealOnHover: false,
    hideAfter: Duration(seconds: 4),
  );

  /// Moving the pointer shows the controls; they go once it has been still
  /// for [hideAfter], but never while it is over one of them.
  static const pointer = ChromePolicy._(
    revealOnTap: false,
    revealOnHover: true,
    hideAfter: Duration(milliseconds: 2500),
  );

  final bool revealOnTap;
  final bool revealOnHover;
  final Duration hideAfter;
}
