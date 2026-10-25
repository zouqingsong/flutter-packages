import 'package:adaptive_viewport/adaptive_viewport.dart';
import 'package:adaptive_viewport/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

ScreenProfile profile(String name) =>
    ScreenProfile.all.firstWhere((profile) => profile.name == name);

bool covers(Rect outer, Rect inner) =>
    inner.left >= outer.left - 0.01 &&
    inner.top >= outer.top - 0.01 &&
    inner.right <= outer.right + 0.01 &&
    inner.bottom <= outer.bottom + 0.01;

bool apart(Rect a, Rect b) {
  final overlap = a.intersect(b);
  return overlap.width <= 0.01 || overlap.height <= 0.01;
}

void main() {
  group('over every screen', () {
    for (final screen in ScreenProfile.all) {
      for (final detail in [false, true]) {
        for (final bodyTop in [0.0, 56.0]) {
          for (final direction in TextDirection.values) {
            final label = '$screen${detail ? ', detail' : ''}'
                '${bodyTop > 0 ? ', under an app bar' : ''}, $direction';
            test(label, () {
              final request = GalleryRequest(
                viewport: screen.viewport,
                detail: detail,
                bodyTop: bodyTop > 0 ? screen.padding.top + bodyTop : 0,
                bottomBarHeight: 64,
                textDirection: direction,
              );
              check(screen, request, GalleryPlanner.plan(request));
            });
          }
        }
      }
    }
  });

  test('columns follow the width, not the device', () {
    int columns(String name) =>
        GalleryPlanner.plan(GalleryRequest(viewport: profile(name).viewport))
            .columns;
    expect(columns('iPhone SE portrait'), 3);
    expect(columns('iPhone 17 Pro portrait'), 3);
    expect(columns('Galaxy Z Fold 4 cover portrait'), 3);
    expect(columns('iPad portrait'), greaterThanOrEqualTo(5));
    expect(columns('macOS full screen'), greaterThanOrEqualTo(9));
    // A third of an iPad is a phone's width, and gets a phone's grid.
    expect(columns('iPad Split View third'), columns('iPhone SE portrait'));
  });

  test('the open item goes beside the grid on a wide window', () {
    for (final name in [
      'iPad Pro 13 landscape',
      'macOS window',
      'iPhone Duo inner landscape',
    ]) {
      final plan = GalleryPlanner.plan(
        GalleryRequest(viewport: profile(name).viewport, detail: true),
      );
      expect(plan.mode, GalleryMode.split, reason: name);
      expect(plan.grid.left, 0, reason: name);
    }
    final rtl = GalleryPlanner.plan(
      GalleryRequest(
        viewport: profile('macOS window').viewport,
        detail: true,
        textDirection: TextDirection.rtl,
      ),
    );
    expect(rtl.grid.right, rtl.body.width);
  });

  test('a phone on its side keeps one pane', () {
    final plan = GalleryPlanner.plan(
      GalleryRequest(
        viewport: profile('iPhone 17 Pro landscapeLeft').viewport,
        detail: true,
      ),
    );
    expect(plan.mode, GalleryMode.single);
    expect(plan.detail, isNull);
  });

  test('a book fold splits at the crease', () {
    final screen = profile('Galaxy Z Fold 4 inner book');
    final plan = GalleryPlanner.plan(
      GalleryRequest(viewport: screen.viewport, detail: true),
    );
    expect(plan.mode, GalleryMode.split);
    expect(plan.grid.right, screen.viewport.crease!.left);
    expect(plan.detail!.left, screen.viewport.crease!.right);
  });

  test('half-folded, the open item is above the fold, the grid below', () {
    final screen = profile('Galaxy Z Fold 4 inner tabletop');
    final plan = GalleryPlanner.plan(
      GalleryRequest(viewport: screen.viewport, detail: true),
    );
    expect(plan.mode, GalleryMode.tabletop);
    expect(plan.detail!.bottom, screen.tabletop!.top);
    expect(plan.grid.top, screen.tabletop!.bottom);
  });

  test('under an app bar the grid leaves the top safe area to it', () {
    final screen = profile('iPhone 17 Pro portrait');
    final plan = GalleryPlanner.plan(
      GalleryRequest(viewport: screen.viewport, bodyTop: 62 + 56),
    );
    expect(plan.gridPadding.top, 12);
    expect(plan.gridPadding.bottom, 12 + 34);
  });
}

void check(ScreenProfile screen, GalleryRequest request, GalleryPlan plan) {
  final body = Offset.zero & plan.body;
  final padding = screen.viewport.padding;

  expect(covers(body, plan.grid), isTrue);
  expect(plan.columns, greaterThanOrEqualTo(2));
  expect(plan.tileExtent, greaterThan(0));
  // The tiles and their gaps fill the grid's width exactly.
  expect(
    plan.columns * plan.tileExtent +
        (plan.columns - 1) * plan.spacing +
        plan.gridPadding.horizontal,
    moreOrLessEquals(plan.grid.width, epsilon: 0.01),
  );
  // More columns where the tiles would still be big enough.
  if (plan.columns > 2) {
    expect(
      plan.tileExtent,
      greaterThanOrEqualTo(GalleryPlanner.minTileFor(plan.screen.width)),
    );
  }

  // The safe area is kept on every edge the grid reaches.
  final gp = plan.gridPadding;
  if (plan.grid.left == 0) expect(gp.left, greaterThanOrEqualTo(padding.left));
  if (plan.grid.right == body.right) {
    expect(gp.right, greaterThanOrEqualTo(padding.right));
  }
  if (plan.grid.bottom == body.bottom) {
    expect(gp.bottom, greaterThanOrEqualTo(padding.bottom + 64));
  }
  if (plan.grid.top == 0 && request.bodyTop == 0) {
    expect(gp.top, greaterThanOrEqualTo(padding.top));
  }

  final bar = plan.bottomBar!;
  expect(covers(plan.grid, bar), isTrue);
  expect(
    plan.bottomBarPadding.deflateRect(bar).height,
    moreOrLessEquals(64, epsilon: 0.01),
  );

  final detail = plan.detail;
  if (!request.detail) expect(detail, isNull);
  if (detail != null) {
    expect(covers(body, detail), isTrue);
    expect(apart(detail, plan.grid), isTrue);
    final crease = screen.viewport.crease;
    if (crease != null) {
      final shifted = crease.shift(Offset(0, -request.bodyTop));
      expect(apart(detail, shifted), isTrue);
      expect(apart(plan.grid, shifted), isTrue);
    }
  }
}
