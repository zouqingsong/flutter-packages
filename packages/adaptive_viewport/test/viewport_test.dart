import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:adaptive_viewport/adaptive_viewport.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    FoldPosture.simulateTabletop.value = false;
    FoldPosture.hinge.value = null;
  });

  group('ScreenViewport.fromMediaQuery', () {
    test('a known punch hole is an obstacle', () {
      final viewport = ScreenViewport.fromMediaQuery(
        const MediaQueryData(
          size: Size(678, 466),
          padding: EdgeInsets.only(right: 84, bottom: 34),
          viewPadding: EdgeInsets.only(right: 84, bottom: 34),
        ),
      );
      expect(viewport.holes, hasLength(1));
      expect(viewport.holes.single.center, const Offset(630, 418));
      expect(viewport.isLandscape, isTrue);
    });

    test('Android cutouts are holes; a half-open book fold is a crease', () {
      final viewport = ScreenViewport.fromMediaQuery(
        const MediaQueryData(
          size: Size(690, 829),
          displayFeatures: [
            DisplayFeature(
              bounds: Rect.fromLTRB(330, 0, 360, 30),
              type: DisplayFeatureType.cutout,
              state: DisplayFeatureState.unknown,
            ),
            DisplayFeature(
              bounds: Rect.fromLTRB(345, 0, 345, 829),
              type: DisplayFeatureType.fold,
              state: DisplayFeatureState.postureHalfOpened,
            ),
          ],
        ),
      );
      expect(viewport.holes, [const Rect.fromLTRB(330, 0, 360, 30)]);
      expect(viewport.crease, const Rect.fromLTRB(345, 0, 345, 829));
      expect(viewport.obstacles, hasLength(2));
    });

    test('a flat seamless fold is not in the way', () {
      final viewport = ScreenViewport.fromMediaQuery(
        const MediaQueryData(
          size: Size(690, 829),
          displayFeatures: [
            DisplayFeature(
              bounds: Rect.fromLTRB(345, 0, 345, 829),
              type: DisplayFeatureType.fold,
              state: DisplayFeatureState.postureFlat,
            ),
          ],
        ),
      );
      expect(viewport.crease, isNull);
      expect(viewport.obstacles, isEmpty);
    });
  });

  group('ViewportScope', () {
    testWidgets('rebuilds readers when the hinge folds', (tester) async {
      final seen = <TabletopFold?>[];
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(669, 951)),
          child: ViewportScope(
            child: Builder(
              builder: (context) {
                seen.add(ScreenViewport.of(context).tabletop);
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      expect(seen.last, isNull);

      FoldPosture.hinge.value = const HingeState(
        HingeStatus.partiallyOpen,
        2.2301,
      );
      await tester.pump();
      expect(seen.last, const TabletopFold(top: 475.5, bottom: 475.5));
    });

    testWidgets('trims the mirrored landscape inset', (tester) async {
      EdgeInsets? padding;
      DisplayHousing.orientation.value = 'landscapeLeft';
      addTearDown(() => DisplayHousing.orientation.value = null);
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(874, 402),
            padding: EdgeInsets.only(left: 62, right: 62, bottom: 21),
            viewPadding: EdgeInsets.only(left: 62, right: 62, bottom: 21),
          ),
          child: ViewportScope(
            child: Builder(
              builder: (context) {
                padding = ScreenViewport.of(context).padding;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      expect(padding, const EdgeInsets.only(right: 62, bottom: 21));
    });
  });

  group('ScreenViewport.within', () {
    const window = ScreenViewport(
      size: Size(402, 874),
      padding: EdgeInsets.only(top: 62, bottom: 34),
      holes: [Rect.fromLTWH(150, 10, 100, 40)],
      tabletop: TabletopFold(top: 437, bottom: 437),
    );

    test('a box below an app bar keeps only the insets reaching into it', () {
      final local = window.within(const Rect.fromLTWH(0, 118, 402, 756));
      expect(local.size, const Size(402, 756));
      expect(local.padding, const EdgeInsets.only(bottom: 34));
      // The island is above the box.
      expect(local.holes, isEmpty);
      expect(local.tabletop, const TabletopFold(top: 319, bottom: 319));
    });

    test('a box beside a sidebar loses the leading inset', () {
      const landscape = ScreenViewport(
        size: Size(1180, 820),
        padding: EdgeInsets.only(left: 20, top: 24, right: 20, bottom: 20),
        crease: Rect.fromLTWH(589, 0, 2, 820),
      );
      final local = landscape.within(const Rect.fromLTWH(300, 0, 880, 820));
      expect(
          local.padding, const EdgeInsets.only(top: 24, right: 20, bottom: 20));
      expect(local.crease, const Rect.fromLTWH(289, 0, 2, 820));
    });

    test('a fold outside the box is no fold of its', () {
      final local = window.within(const Rect.fromLTWH(0, 500, 402, 374));
      expect(local.tabletop, isNull);
    });

    test('the whole window is itself', () {
      final local = window.within(Offset.zero & window.size);
      expect(local, window);
    });
  });

  group('BoxViewportBuilder', () {
    testWidgets('fractional flex tiles keep their measured camera coordinates',
        (tester) async {
      tester.view.physicalSize = const Size(466, 678);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final seen = <String, ScreenViewport>{};
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(
          size: Size(466, 678),
          padding: EdgeInsets.only(right: 84, bottom: 34),
          viewPadding: EdgeInsets.only(right: 84, bottom: 34),
        ),
        child: ViewportScope(
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Stack(children: [
              Positioned(
                left: 73.6,
                top: 151,
                width: 325.3,
                height: 431.6666666666667,
                child: Column(children: [
                  for (var row = 0; row < 3; row++) ...[
                    if (row > 0) const SizedBox(height: 10),
                    Expanded(
                        child: Row(children: [
                      for (var col = 0; col < 3; col++) ...[
                        if (col > 0) const SizedBox(width: 6),
                        Expanded(
                            child: BoxViewportBuilder(
                          key: ValueKey('tile-$row-$col'),
                          builder: (context, viewport) {
                            seen['$row-$col'] = viewport;
                            return const SizedBox.expand();
                          },
                        )),
                      ],
                    ])),
                  ],
                ]),
              ),
            ]),
          ),
        ),
      ));
      for (var frame = 0; frame < 5; frame++) {
        await tester.pump();
      }
      final tile = seen['0-2']!;
      final rect = tester.getRect(find.byKey(const ValueKey('tile-0-2')));
      expect(tile.padding.bottom, 0);
      expect(tile.holes, hasLength(1));
      expect(tile.holes.single.left, closeTo(382 - rect.left, 0.001));
      expect(tile.holes.single.bottom, closeTo(158 - rect.top, 0.001));
      expect(tester.takeException(), isNull);
    });

    testWidgets('plans for the box below an app bar, not the window',
        (tester) async {
      tester.view.physicalSize = const Size(402, 874);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 62, bottom: 34);
      addTearDown(tester.view.reset);
      final seen = <ScreenViewport>[];
      await tester.pumpWidget(
        MediaQuery.fromView(
          view: tester.view,
          child: ViewportScope(
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Column(
                children: [
                  const SizedBox(height: 118),
                  Expanded(
                    child: Builder(
                      builder: (context) => MediaQuery.removePadding(
                        context: context,
                        removeTop: true,
                        child: BoxViewportBuilder(
                          builder: (context, viewport) {
                            seen.add(viewport);
                            return const SizedBox.expand();
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final viewport = seen.last;
      expect(viewport.size, const Size(402, 756));
      expect(viewport.padding, const EdgeInsets.only(bottom: 34));
    });

    testWidgets('a box at the top of the window keeps the status bar',
        (tester) async {
      tester.view.physicalSize = const Size(402, 874);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 62, bottom: 34);
      addTearDown(tester.view.reset);
      late ScreenViewport viewport;
      await tester.pumpWidget(
        MediaQuery.fromView(
          view: tester.view,
          child: ViewportScope(
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Column(
                children: [
                  Expanded(
                    child: BoxViewportBuilder(
                      builder: (context, v) {
                        viewport = v;
                        return const SizedBox.expand();
                      },
                    ),
                  ),
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(viewport.size, const Size(402, 774));
      expect(viewport.padding, const EdgeInsets.only(top: 62));
    });
  });

  group('LocalSafeArea.insetsOf', () {
    final hole = Rect.fromCircle(center: const Offset(418, 48), radius: 18.5);
    const readOuts = Rect.fromLTRB(382, 66.5, 466, 158);
    final portrait = ScreenViewport(
      size: const Size(466, 678),
      padding: const EdgeInsets.only(right: 84, bottom: 34),
      holes: [hole, readOuts],
    );
    final landscapeRight = ScreenViewport(
      size: const Size(678, 466),
      padding: const EdgeInsets.only(left: 84, bottom: 34),
      holes: [Rect.fromCircle(center: const Offset(48, 48), radius: 18.5)],
    );

    EdgeInsets insets(ScreenViewport window, Rect box,
            {bool left = true, bool top = true}) =>
        LocalSafeArea.insetsOf(window.within(box), window,
            left: left, top: top);

    test('a top bar steps sideways past the hole, not down', () {
      expect(insets(landscapeRight, const Rect.fromLTWH(0, 0, 678, 56)),
          const EdgeInsets.only(left: 70.5));
    });

    test('a box away from the hole fills the camera column', () {
      expect(insets(landscapeRight, const Rect.fromLTWH(0, 120, 300, 200)),
          EdgeInsets.zero);
      expect(insets(portrait, const Rect.fromLTWH(200, 300, 266, 200)),
          EdgeInsets.zero);
    });

    test('the home indicator inset is kept', () {
      expect(insets(landscapeRight, const Rect.fromLTWH(0, 300, 678, 166)),
          const EdgeInsets.only(bottom: 34));
    });

    test('a side turned off is not stepped to', () {
      final bar = insets(landscapeRight, const Rect.fromLTWH(0, 0, 678, 56),
          left: false);
      expect(bar.left, 0);
      expect(bar.top, 0);
    });

    test('content below a header steps down past the read-outs', () {
      expect(insets(portrait, const Rect.fromLTWH(0, 56, 466, 622)),
          const EdgeInsets.only(top: 106, bottom: 34));
    });

    test('an inset no hole explains is kept, as SafeArea would', () {
      const iphone = ScreenViewport(
        size: Size(874, 402),
        padding: EdgeInsets.only(left: 62, right: 62, bottom: 21),
      );
      expect(insets(iphone, Offset.zero & iphone.size),
          const EdgeInsets.only(left: 62, right: 62, bottom: 21));
    });
  });

  group('LocalSafeArea', () {
    testWidgets('settles around the Duo cover hole without overflowing',
        (tester) async {
      tester.view.physicalSize = const Size(466, 678);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const header = ValueKey('header');
      const body = ValueKey('body');
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(
          size: Size(466, 678),
          padding: EdgeInsets.only(right: 84, bottom: 34),
          viewPadding: EdgeInsets.only(right: 84, bottom: 34),
        ),
        child: ViewportScope(
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Column(children: [
              const LocalSafeArea(
                bottom: false,
                child:
                    SizedBox(key: header, width: double.infinity, height: 56),
              ),
              Expanded(
                child: LocalSafeArea(
                  child: Builder(
                    builder: (context) {
                      // Insets it applied are taken out of MediaQuery.
                      expect(MediaQuery.paddingOf(context), EdgeInsets.zero);
                      return const SizedBox.expand(key: body);
                    },
                  ),
                ),
              ),
            ]),
          ),
        ),
      ));
      for (var frame = 0; frame < 6; frame++) {
        await tester.pump();
      }
      expect(tester.takeException(), isNull);
      final bar = tester.getRect(find.byKey(header));
      final content = tester.getRect(find.byKey(body));
      // The bar keeps its full height and gives up only the hole's width.
      expect(bar.left, 0);
      expect(bar.top, 0);
      expect(bar.right, closeTo(466 - 70.5, 0.01));
      // The page below runs edge to edge and starts under the read-outs.
      expect(content.left, 0);
      expect(content.right, 466);
      expect(content.top, closeTo(162, 0.01));
      expect(content.bottom, 678 - 34);
    });
  });
}
