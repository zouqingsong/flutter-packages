import 'package:adaptive_viewport/adaptive_viewport.dart';
import 'package:adaptive_viewport/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

ScreenProfile profile(String name) =>
    ScreenProfile.all.firstWhere((profile) => profile.name == name);

/// Contains [inner], allowing for rounding.
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
      for (final chromeShown in [true, false]) {
        for (final aspect in <double?>[null, 16 / 9, 3 / 4]) {
          for (final panel in [false, true]) {
            for (final direction in TextDirection.values) {
              final label = '$screen, ${chromeShown ? 'bars' : 'full screen'}'
                  ', aspect $aspect${panel ? ', panel' : ''}, $direction';
              test(label, () {
                final plan = ViewerPlanner.plan(
                  ViewerRequest(
                    viewport: screen.viewport,
                    chromeShown: chromeShown,
                    mediaAspect: aspect,
                    panel: panel,
                    filmstripHeight: 56,
                    textDirection: direction,
                  ),
                );
                check(screen, plan, panel: panel);
              });
            }
          }
        }
      }
    }
  });

  test('upright, a wide picture is letterboxed and the bars sit in the band',
      () {
    final plan = ViewerPlanner.plan(
      ViewerRequest(
        viewport: profile('iPhone 17 Pro portrait').viewport,
        mediaAspect: 16 / 9,
      ),
    );
    expect(plan.mode, ViewerMode.docked);
    expect(plan.overlayInsets.top, 0);
  });

  test('on its side, the bars float over a picture they would shrink', () {
    for (final name in [
      'iPhone 17 Pro landscapeLeft',
      'Pixel 9 landscape',
      'iPhone Duo cover landscapeRight',
    ]) {
      final plan = ViewerPlanner.plan(
        ViewerRequest(viewport: profile(name).viewport, mediaAspect: 16 / 9),
      );
      expect(plan.mode, ViewerMode.overlay, reason: name);
      expect(plan.picture, Offset.zero & plan.window, reason: name);
    }
  });

  test('a picture that must stay clear keeps its bars beside it', () {
    final plan = ViewerPlanner.plan(
      ViewerRequest(
        viewport: profile('iPhone 17 Pro landscapeLeft').viewport,
        mediaAspect: 16 / 9,
        keepPictureClear: true,
      ),
    );
    expect(plan.mode, ViewerMode.docked);
    expect(apart(plan.picture, plan.topBar!), isTrue);
    expect(apart(plan.picture, plan.bottomBar!), isTrue);
  });

  test('a desktop window docks its bars when the shape is unknown', () {
    final plan = ViewerPlanner.plan(
      ViewerRequest(viewport: profile('macOS window').viewport),
    );
    expect(plan.mode, ViewerMode.docked);
    expect(plan.chrome, ChromePolicy.pointer);
  });

  test('the panel goes beside the picture where there is room', () {
    for (final name in ['iPad Pro 13 landscape', 'macOS window']) {
      final plan = ViewerPlanner.plan(
        ViewerRequest(viewport: profile(name).viewport, panel: true),
      );
      expect(plan.panel, isNotNull, reason: name);
      expect(plan.panel!.right, plan.window.width, reason: name);
    }
    for (final name in ['iPhone 17 Pro landscapeLeft', 'iPad portrait']) {
      final plan = ViewerPlanner.plan(
        ViewerRequest(viewport: profile(name).viewport, panel: true),
      );
      expect(plan.panel, isNull, reason: name);
    }
  });

  test('a book fold puts the panel on its far half', () {
    final screen = profile('Galaxy Z Fold 4 inner book');
    final plan = ViewerPlanner.plan(
      ViewerRequest(viewport: screen.viewport, panel: true),
    );
    final crease = screen.viewport.crease!;
    expect(plan.picture.right, lessThanOrEqualTo(crease.left));
    expect(plan.panel!.left, greaterThanOrEqualTo(crease.right));
  });

  test('half-folded, every bar is on the deck', () {
    for (final name in [
      'Galaxy Z Fold 4 inner tabletop',
      'iPhone Duo inner half-folded',
    ]) {
      final screen = profile(name);
      final plan = ViewerPlanner.plan(ViewerRequest(viewport: screen.viewport));
      expect(plan.mode, ViewerMode.tabletop, reason: name);
      // The picture has the upright half to itself; the back button and
      // the name come first from the fold, then the transport.
      expect(plan.topBar!.top, plan.fold!.bottom, reason: name);
      expect(plan.bottomBar!.top, greaterThanOrEqualTo(plan.topBar!.bottom),
          reason: name);
      expect(
          plan.bottomBar!.bottom,
          lessThanOrEqualTo(
              screen.size.height - screen.viewport.padding.bottom),
          reason: name);
      expect(plan.topBar!.overlaps(plan.picture), isFalse, reason: name);
      expect(plan.tools, isNull, reason: name);
    }
  });

  test('half-folded, an open palette is between the bars, as on live', () {
    for (final name in [
      'Galaxy Z Fold 4 inner tabletop',
      'iPhone Duo inner half-folded',
    ]) {
      final screen = profile(name);
      final plan = ViewerPlanner.plan(
        ViewerRequest(viewport: screen.viewport, toolsHeight: 96),
      );
      final tools = plan.tools!;
      expect(tools.height, 96, reason: name);
      expect(tools.top, greaterThan(plan.topBar!.bottom), reason: name);
      expect(plan.bottomBar!.top, greaterThan(tools.bottom), reason: name);
      expect(tools.overlaps(plan.picture), isFalse, reason: name);
      expect(
          plan.bottomBar!.bottom,
          lessThanOrEqualTo(
              screen.size.height - screen.viewport.padding.bottom),
          reason: name);
    }
  });

  test('an open palette sits just above the bottom bar, inside the safe area',
      () {
    for (final screen in ScreenProfile.all) {
      final plan = ViewerPlanner.plan(
        ViewerRequest(viewport: screen.viewport, toolsHeight: 52),
      );
      if (plan.mode == ViewerMode.tabletop) continue;
      final tools = plan.tools!;
      final safe =
          screen.viewport.padding.deflateRect(Offset.zero & screen.size);
      expect(tools.bottom, lessThan(plan.bottomBar!.top), reason: screen.name);
      // Inside the safe area, or past a side inset only where the hole that
      // accounts for it is not.
      final holes = screen.viewport.holes;
      if (tools.left < safe.left || tools.right > safe.right) {
        expect(holes, isNotEmpty, reason: screen.name);
        for (final hole in holes) {
          expect(apart(tools, hole), isTrue, reason: screen.name);
        }
      }
    }
  });

  test('upright on the Duo cover screen, only the top bar keeps the column',
      () {
    // The 84 pt column down the right holds the hole and the clock at its
    // top; below them it is screen like any other.
    final screen = profile('iPhone Duo cover portrait');
    final plan = ViewerPlanner.plan(
      ViewerRequest(
        viewport: screen.viewport,
        mediaAspect: 16 / 9,
        toolsHeight: 52,
      ),
    );
    expect(plan.picture.width, screen.size.width);
    expect(plan.topBarPadding.right, 84);
    expect(plan.bottomBarPadding.right, 0);
    expect(plan.tools!.right, screen.size.width - ViewerPlanner.toolsSide);
  });
}

void check(ScreenProfile screen, ViewerPlan plan, {required bool panel}) {
  final window = Offset.zero & screen.size;
  final viewport = screen.viewport;
  final safe = viewport.padding.deflateRect(window);
  final fold = plan.fold;

  expect(plan.picture.isEmpty, isFalse);
  expect(covers(window, plan.picture), isTrue);

  if (plan.fullscreen) {
    expect(plan.bottomBar, isNull);
    expect(plan.panel, isNull);
    expect(
      plan.picture,
      fold == null ? window : Rect.fromLTRB(0, 0, window.width, fold.top),
    );
    return;
  }

  final bars = [plan.topBar!, plan.bottomBar!];
  for (final (bar, padding) in [
    (plan.topBar!, plan.topBarPadding),
    (plan.bottomBar!, plan.bottomBarPadding),
  ]) {
    expect(covers(window, bar), isTrue, reason: '$bar');
    // What is in a bar keeps the safe area, so it meets no hole — or, past a
    // side inset a hole accounts for, stays clear of the hole itself.
    final content = padding.deflateRect(bar);
    expect(content.isEmpty, isFalse, reason: '$bar');
    expect(
      covers(safe, content) ||
          (viewport.holes.isNotEmpty &&
              covers(
                Rect.fromLTRB(
                    window.left, safe.top, window.right, safe.bottom),
                content,
              )),
      isTrue,
      reason: '$content in $safe',
    );
    for (final hole in viewport.holes) {
      expect(apart(content, hole), isTrue, reason: '$content on $hole');
    }
  }

  if (plan.mode == ViewerMode.docked) {
    for (final bar in bars) {
      expect(apart(plan.picture, bar), isTrue, reason: '$bar');
    }
  }

  if (fold != null) {
    expect(plan.picture.bottom, lessThanOrEqualTo(fold.top));
    for (final bar in bars) {
      expect(bar.top, greaterThanOrEqualTo(fold.bottom));
      expect(covers(plan.deck!, bar), isTrue);
    }
  }

  final shownPanel = plan.panel;
  if (!panel) expect(shownPanel, isNull);
  if (shownPanel != null) {
    expect(covers(window, shownPanel), isTrue);
    expect(apart(shownPanel, plan.picture), isTrue);
    for (final bar in bars) {
      expect(apart(shownPanel, bar), isTrue);
    }
    expect(shownPanel.width, greaterThanOrEqualTo(ViewerPlanner.minPanelWidth));
    final crease = viewport.crease;
    if (crease != null) {
      expect(apart(shownPanel, crease), isTrue);
      expect(apart(plan.picture, crease), isTrue);
    }
  }
}
