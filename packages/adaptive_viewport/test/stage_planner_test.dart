import 'package:adaptive_viewport/adaptive_viewport.dart';
import 'package:adaptive_viewport/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The wide breakpoint the apps use (a sidebar and a framed picture).
bool _wide(Size size) =>
    size.shortestSide >= 480 &&
    (size.width >= 1000 || (size.width >= 900 && size.shortestSide >= 600));

StagePlan _plan(
  ScreenProfile profile, {
  bool fullscreen = false,
  TextDirection direction = TextDirection.ltr,
  double railExtra = 0,
}) {
  final wide = _wide(profile.size);
  return StagePlanner.plan(
    StageRequest(
      viewport: profile.viewport,
      wide: wide,
      fullscreen: fullscreen,
      textDirection: direction,
      // An app bar on an upright narrow window, as the apps have.
      topChrome: !wide &&
          !fullscreen &&
          !profile.isLandscape &&
          profile.viewport.tabletop == null,
      railExtra: railExtra,
    ),
  );
}

/// The controls a plan places, as window rects.
Map<String, Rect> _controls(StagePlan plan, TextDirection direction) {
  final rtl = direction == TextDirection.rtl;
  final w = plan.window.width;
  final h = plan.window.height;
  return {
    if (plan.floatingMenu)
      'menu': Rect.fromLTWH(
        rtl ? w - plan.menuStart - StagePlanner.menuSize : plan.menuStart,
        plan.menuTop,
        StagePlanner.menuSize,
        StagePlanner.menuSize,
      ),
    // On a tabletop's deck the badge is with the other read-outs.
    if (plan.fullscreen || !plan.isTabletop)
      'badge': Offset(plan.badgeLeft, plan.badgeTop) & StagePlanner.badgeSize,
    if (plan.fullscreen)
      // Five round actions and their gaps.
      'actions': Rect.fromLTWH(
        w - plan.actionsRight - StagePlanner.actionsWidth,
        plan.actionsTop,
        StagePlanner.actionsWidth,
        5 * 48 + 4 * 8,
      ),
    if (plan.railBeside)
      // The rail's groups, inside its own padding and margins.
      'rail': Rect.fromLTRB(
        plan.railOnLeft ? plan.safe.left + 10 : w - 76 - plan.safe.right + 6,
        10 + plan.railPadding.top,
        plan.railOnLeft ? plan.safe.left + 76 - 6 : w - plan.safe.right - 10,
        h - 10 - plan.railPadding.bottom,
      ),
  };
}

void main() {
  group('device matrix', () {
    for (final profile in ScreenProfile.all) {
      for (final fullscreen in [false, true]) {
        for (final direction in TextDirection.values) {
          final label = '$profile${fullscreen ? ' full screen' : ''}'
              '${direction == TextDirection.rtl ? ' rtl' : ''}';
          test(label, () {
            final plan = _plan(
              profile,
              fullscreen: fullscreen,
              direction: direction,
            );
            final window = Offset.zero & profile.size;
            final controls = _controls(plan, direction);

            // A tabletop is only ever a narrow window's.
            if (profile.viewport.tabletop != null && !_wide(profile.size)) {
              expect(plan.mode, StageMode.tabletop);
            }

            for (final MapEntry(key: name, value: rect) in controls.entries) {
              expect(
                window.contains(rect.topLeft) &&
                    window.contains(rect.bottomRight - const Offset(1, 1)),
                isTrue,
                reason: '$name $rect is outside the window',
              );
              // Under an app bar or in a framed pane the stage is not at the
              // window's origin, and the bar keeps it off the screen's top.
              final atOrigin = plan.fullscreen ||
                  plan.mode == StageMode.docked ||
                  plan.mode == StageMode.tabletop;
              for (final obstacle in atOrigin ? plan.obstacles : <Rect>[]) {
                expect(
                  rect.overlaps(obstacle),
                  isFalse,
                  reason: '$name $rect is on $obstacle',
                );
              }
              // The top and bottom insets are the status bar and the home
              // indicator: never given back.
              expect(
                rect.top,
                greaterThanOrEqualTo(plan.safe.top),
                reason: '$name under the status bar',
              );
              expect(
                rect.bottom,
                lessThanOrEqualTo(profile.size.height - plan.safe.bottom),
                reason: '$name over the home indicator',
              );
              // On a tabletop, nothing over the picture reaches the crease.
              final fold = plan.fold;
              if (fold != null && name != 'rail') {
                expect(rect.bottom, lessThanOrEqualTo(fold.top));
              }
            }

            final names = controls.keys.toList();
            for (var i = 0; i < names.length; i++) {
              for (var j = i + 1; j < names.length; j++) {
                expect(
                  controls[names[i]]!.overlaps(controls[names[j]]!),
                  isFalse,
                  reason: '${names[i]} overlaps ${names[j]}',
                );
              }
            }
          });
        }
      }
    }
  });

  group('modes', () {
    ScreenProfile find(String name) =>
        ScreenProfile.all.firstWhere((profile) => profile.name == name);

    test('by window shape, not device', () {
      expect(_plan(find('iPhone 17 Pro portrait')).mode, StageMode.column);
      expect(_plan(find('iPhone 17 Pro landscapeLeft')).mode, StageMode.docked);
      expect(_plan(find('iPad landscape')).mode, StageMode.framed);
      expect(
        _plan(find('iPhone Duo inner half-folded')).mode,
        StageMode.tabletop,
      );
      expect(
        _plan(find('Galaxy Z Fold 4 inner tabletop')).mode,
        StageMode.tabletop,
      );
      // A book fold keeps the normal layout; the crease is an obstacle.
      final book = _plan(find('Galaxy Z Fold 4 inner book'));
      expect(book.mode, StageMode.column);
      expect(book.obstacles, isNotEmpty);
    });

    test('docked: the rail takes the trailing edge with its inset', () {
      final plan = _plan(
        find('iPhone 17 Pro landscapeLeft'),
        railExtra: 168,
      );
      expect(plan.railBeside, isTrue);
      expect(plan.railExtent, 76 + 62 + 168);
      expect(plan.overlayInsets.right, plan.railExtent);
      expect(plan.overlayInsets.left, 0);
      expect(plan.floatingMenu, isTrue);
      // The island is on the right: the menu has the left corner.
      expect(plan.menuStart, 8);
    });

    test('a hole gives back its side and the corner steps around it', () {
      final right = _plan(find('iPhone Duo cover landscapeLeft'));
      expect(right.safe.right, 0, reason: 'the 84 pt inset is the hole');
      // The hole is low in the rail's column: the rail ends above it.
      expect(right.railPadding.bottom, greaterThan(34));

      final left = _plan(find('iPhone Duo cover landscapeRight'));
      expect(left.safe.left, 0);
      // The hole is in the top-left corner: the menu starts past it.
      final hole = left.obstacles.single;
      expect(left.menuStart, greaterThan(hole.right));
      expect(left.badgeLeft, greaterThan(left.menuStart));
    });

    test('full screen: the actions step below a hole in their corner', () {
      final plan = _plan(find('iPhone Duo cover portrait'), fullscreen: true);
      final hole = plan.obstacles.single;
      expect(plan.actionsTop, greaterThan(hole.bottom));
    });

    test('tabletop: the deck keeps the home indicator', () {
      final plan = _plan(find('iPhone Duo inner half-folded'));
      expect(plan.fold, const TabletopFold(top: 475.5, bottom: 475.5));
      expect(plan.deckPadding.bottom, 34);
      expect(plan.floatingMenu, isTrue);
    });
  });

  group('stepPast', () {
    const hole = Rect.fromLTWH(100, 0, 20, 20);

    test('leaves a clear rect alone', () {
      const rect = Rect.fromLTWH(0, 0, 40, 40);
      expect(StagePlanner.stepPast(rect, [hole], AxisDirection.right), rect);
    });

    test('moves along the edge past the obstacle', () {
      const rect = Rect.fromLTWH(90, 0, 40, 40);
      final moved = StagePlanner.stepPast(rect, [hole], AxisDirection.right);
      expect(moved.left, 126);
      expect(moved.top, 0);
      final down = StagePlanner.stepPast(rect, [hole], AxisDirection.down);
      expect(down.top, 26);
    });

    test('past one obstacle and the next', () {
      const next = Rect.fromLTWH(130, 0, 20, 20);
      final moved = StagePlanner.stepPast(
        const Rect.fromLTWH(90, 0, 40, 40),
        [hole, next],
        AxisDirection.right,
      );
      expect(moved.left, 156);
    });
  });
}
