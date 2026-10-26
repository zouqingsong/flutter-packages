import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// One group of controls laid along a line: its [length] along the line and
/// its [thickness] across it.
///
/// Down a rail, length is the group's height and thickness its width; across
/// a bar, the other way round.
@immutable
class ControlGroup {
  const ControlGroup({required this.length, required this.thickness});

  /// A run of [count] buttons, each [extent] along the line and [thickness]
  /// across it, plus the group's own [padding] at its two ends.
  const ControlGroup.run(
    int count, {
    required double extent,
    required this.thickness,
    double padding = 0,
  }) : length = count * extent + padding;

  final double length;
  final double thickness;

  @override
  String toString() => 'ControlGroup($length × $thickness)';
}

/// How a [ControlsPlan] lays its three groups out.
enum ControlsFold {
  /// One line, the primary group in the middle and the other two at the ends,
  /// each with the room to be centred on the line.
  centred,

  /// One line, the three groups spread from end to end: the primary group is
  /// between the others but not at the middle.
  spread,

  /// Two lines: the primary group on its own, the tools and the view's
  /// toggles at the two ends of the other.
  folded,

  /// Two lines, regrouped to even them out: the tools on their own, the
  /// view's toggles beside the primary group.
  regrouped,
}

/// What the controls planner needs: the room along the line and the three
/// groups that go on it.
@immutable
class ControlsRequest {
  const ControlsRequest({
    required this.room,
    required this.tools,
    required this.primary,
    required this.view,
    this.gap = 12,
  });

  /// Length of the line the controls have, insets and the bar's or rail's
  /// own padding already taken off.
  final double room;

  /// The tools that work on the content (draw, adjust, share): one end.
  final ControlGroup tools;

  /// What the screen exists for (shutter and record, play): large, in the
  /// middle, where the thumb is.
  final ControlGroup primary;

  /// The toggles that change the view (strip, full screen): the other end.
  final ControlGroup view;

  /// Between two groups, along a line and between two lines.
  final double gap;
}

/// Where a bar's or a rail's groups go.
@immutable
class ControlsPlan {
  const ControlsPlan({
    required this.fold,
    required this.thickness,
    required this.fits,
  });

  final ControlsFold fold;

  /// Room the controls take across the line: a bar's height, a rail's width.
  final double thickness;

  /// False only when even the shortest fold is longer than the room: a line
  /// then has to scroll, and the app should drop a control instead.
  final bool fits;

  bool get twoLines =>
      fold == ControlsFold.folded || fold == ControlsFold.regrouped;

  @override
  String toString() =>
      'ControlsPlan($fold, $thickness thick${fits ? '' : ', does not fit'})';
}

/// Turns a [ControlsRequest] into a [ControlsPlan]. Pure.
///
/// The rule (7 in the README): **no control is reached by scrolling.** A bar
/// or rail takes the first of these that fits in its room, measured rather
/// than chosen by device:
///
/// 1. [ControlsFold.centred] — one line, the primary group centred.
/// 2. [ControlsFold.spread] — one line, end to end.
/// 3. [ControlsFold.folded] — two lines: the primary group, and the tools and
///    toggles at either end of the other.
/// 4. [ControlsFold.regrouped] — two lines evened out: the tools, and the
///    toggles beside the primary group.
///
/// A second line costs thickness — a taller bar, a wider rail — which the
/// stage plans around, so the content gives way rather than a control
/// disappearing off the end of a line. Only when even the shortest fold is
/// too long does the plan say it does not [ControlsPlan.fits].
abstract final class ControlsPlanner {
  static ControlsPlan plan(ControlsRequest request) {
    final room = request.room;
    final gap = request.gap;
    final tools = request.tools;
    final primary = request.primary;
    final view = request.view;

    final oneLine = math.max(
      primary.thickness,
      math.max(tools.thickness, view.thickness),
    );
    final side = math.max(tools.length, view.length);
    if (primary.length + 2 * (side + gap) <= room) {
      return ControlsPlan(
        fold: ControlsFold.centred,
        thickness: oneLine,
        fits: true,
      );
    }
    if (tools.length + primary.length + view.length + 2 * gap <= room) {
      return ControlsPlan(
        fold: ControlsFold.spread,
        thickness: oneLine,
        fits: true,
      );
    }

    final foldedLength = math.max(
      tools.length + gap + view.length,
      primary.length,
    );
    final folded =
        primary.thickness + gap + math.max(tools.thickness, view.thickness);
    if (foldedLength <= room) {
      return ControlsPlan(
        fold: ControlsFold.folded,
        thickness: folded,
        fits: true,
      );
    }

    final regroupedLength = math.max(
      tools.length,
      primary.length + gap + view.length,
    );
    final regrouped =
        math.max(primary.thickness, view.thickness) + gap + tools.thickness;
    if (regroupedLength <= room) {
      return ControlsPlan(
        fold: ControlsFold.regrouped,
        thickness: regrouped,
        fits: true,
      );
    }

    // Too short for any of them: the fold that overflows least.
    return foldedLength <= regroupedLength
        ? ControlsPlan(
            fold: ControlsFold.folded, thickness: folded, fits: false)
        : ControlsPlan(
            fold: ControlsFold.regrouped,
            thickness: regrouped,
            fits: false,
          );
  }
}
