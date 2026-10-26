import 'package:flutter/foundation.dart';

/// One group of a tool palette — the drawing tools, the colours, undo and
/// redo — in its full form and, where it has one, a compact form: the same
/// choices behind one button that shows the current one, the way the Photos
/// markup tools put the shapes behind a "+".
@immutable
class PaletteGroup {
  const PaletteGroup({required this.width, this.compactWidth});

  /// Width of the group laid out in full.
  final double width;

  /// Width of its compact form, or null when it has none.
  final double? compactWidth;

  bool get foldable => compactWidth != null && compactWidth! < width;

  @override
  String toString() =>
      'PaletteGroup($width${foldable ? ' / $compactWidth' : ''})';
}

/// What the palette planner needs: the width it has and the groups, in order.
@immutable
class PaletteRequest {
  const PaletteRequest({
    required this.room,
    required this.groups,
    this.gap = 8,
  });

  /// The width a row of groups may take.
  final double room;

  final List<PaletteGroup> groups;

  /// Between two groups on a row.
  final double gap;
}

/// Where a palette's groups go: which are compact, and which share a row.
@immutable
class PalettePlan {
  const PalettePlan({
    required this.compact,
    required this.rows,
    required this.fits,
  });

  /// Per group, whether it takes its compact form.
  final List<bool> compact;

  /// Indices of the groups on each row, top to bottom, in order.
  final List<List<int>> rows;

  /// False only when a group is wider than the room even compact; its row
  /// then has to be clipped, and the app should drop a control instead.
  final bool fits;

  @override
  String toString() => 'PalettePlan($rows, compact $compact'
      '${fits ? '' : ', does not fit'})';
}

/// Lays a tool palette out so that no tool is reached by scrolling (rule 7).
///
/// Groups stay whole and in order, and wrap onto as few rows as the width
/// allows. Where folding a group into its compact form saves a row, it is
/// folded; where it does not, every group is shown in full — a tool behind a
/// menu is one more tap, so it is only put there to save a row.
///
/// A phone held upright gets two or three rows, a phone on its side or a
/// tablet one.
abstract final class PalettePlanner {
  static PalettePlan plan(PaletteRequest request) {
    final groups = request.groups;
    final foldable = [
      for (var i = 0; i < groups.length; i++)
        if (groups[i].foldable) i,
    ];

    PalettePlan? best;
    var bestFolds = 0;
    // Every combination of folds; palettes have a handful of groups, and
    // only those with a compact form count.
    for (var mask = 0; mask < 1 << foldable.length; mask++) {
      final compact = List.filled(groups.length, false);
      var folds = 0;
      for (var bit = 0; bit < foldable.length; bit++) {
        if (mask & (1 << bit) != 0) {
          compact[foldable[bit]] = true;
          folds++;
        }
      }
      final widths = [
        for (var i = 0; i < groups.length; i++)
          compact[i] ? groups[i].compactWidth! : groups[i].width,
      ];
      final candidate = _wrap(widths, request.room, request.gap, compact);
      if (best == null || _better(candidate, folds, best, bestFolds)) {
        best = candidate;
        bestFolds = folds;
      }
    }
    return best!;
  }

  /// Fitting beats not fitting, fewer rows beat more, and fewer folds break
  /// a tie.
  static bool _better(PalettePlan a, int aFolds, PalettePlan b, int bFolds) {
    if (a.fits != b.fits) return a.fits;
    if (a.rows.length != b.rows.length) return a.rows.length < b.rows.length;
    return aFolds < bFolds;
  }

  static PalettePlan _wrap(
    List<double> widths,
    double room,
    double gap,
    List<bool> compact,
  ) {
    final rows = <List<int>>[];
    var fits = true;
    var line = <int>[];
    var used = 0.0;
    for (var i = 0; i < widths.length; i++) {
      final width = widths[i];
      if (width > room + 0.01) fits = false;
      final next = line.isEmpty ? width : used + gap + width;
      if (line.isNotEmpty && next > room + 0.01) {
        rows.add(line);
        line = [i];
        used = width;
      } else {
        line.add(i);
        used = next;
      }
    }
    if (line.isNotEmpty) rows.add(line);
    return PalettePlan(compact: compact, rows: rows, fits: fits);
  }

  /// Height of a [plan] whose rows are [rowHeight] tall, [gap] apart.
  static double heightOf(
    PalettePlan plan, {
    required double rowHeight,
    double gap = 8,
  }) =>
      plan.rows.isEmpty
          ? 0
          : plan.rows.length * rowHeight + (plan.rows.length - 1) * gap;
}
