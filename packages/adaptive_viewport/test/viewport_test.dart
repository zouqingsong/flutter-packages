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
}
