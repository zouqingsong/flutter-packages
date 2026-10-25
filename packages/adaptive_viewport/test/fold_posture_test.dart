import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:adaptive_viewport/adaptive_viewport.dart';

/// A Galaxy Z Flip in Flex Mode: 411 × 1006 with a seamless fold mid-height.
const _flip = Size(411, 1006);
const _flipFold = DisplayFeature(
  bounds: Rect.fromLTRB(0, 503, 411, 503),
  type: DisplayFeatureType.fold,
  state: DisplayFeatureState.postureHalfOpened,
);

Future<TabletopFold?> _foldFor(
  WidgetTester tester, {
  required Size size,
  List<DisplayFeature> features = const [],
}) async {
  TabletopFold? result;
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(size: size, displayFeatures: features),
      child: Builder(builder: (context) {
        result = FoldPosture.tabletopOf(context);
        return const SizedBox();
      }),
    ),
  );
  return result;
}

void main() {
  tearDown(() {
    FoldPosture.simulateTabletop.value = false;
    FoldPosture.hinge.value = null;
  });

  group('parseHingeEvent', () {
    test('decodes the plugin map', () {
      expect(
        FoldPosture.parseHingeEvent({'status': 2, 'angle': 1.5}),
        const HingeState(HingeStatus.partiallyOpen, 1.5),
      );
    });

    test('null and junk mean no hinge or unknown', () {
      expect(FoldPosture.parseHingeEvent(null), isNull);
      expect(
        FoldPosture.parseHingeEvent({'status': 99}),
        const HingeState(HingeStatus.unknown, 0.0),
      );
    });
  });

  group('tabletopOf', () {
    testWidgets('Android half-opened fold across a portrait window',
        (tester) async {
      expect(
        await _foldFor(tester, size: _flip, features: const [_flipFold]),
        const TabletopFold(top: 503, bottom: 503),
      );
    });

    testWidgets('Galaxy Z Fold: horizontal fold across a landscape window',
        (tester) async {
      // The inner screen held sideways in Flex Mode, as the Fold 4 reports it.
      const fold = DisplayFeature(
        bounds: Rect.fromLTRB(0, 345, 829, 345),
        type: DisplayFeatureType.fold,
        state: DisplayFeatureState.postureHalfOpened,
      );
      expect(
        await _foldFor(tester,
            size: const Size(829, 690), features: const [fold]),
        const TabletopFold(top: 345, bottom: 345),
      );
    });

    testWidgets('a flat or book-style fold is not a tabletop', (tester) async {
      const flat = DisplayFeature(
        bounds: Rect.fromLTRB(0, 503, 411, 503),
        type: DisplayFeatureType.fold,
        state: DisplayFeatureState.postureFlat,
      );
      expect(
          await _foldFor(tester, size: _flip, features: const [flat]), isNull);
      // A vertical fold (book posture) runs down the middle.
      const book = DisplayFeature(
        bounds: Rect.fromLTRB(414, 0, 414, 690),
        type: DisplayFeatureType.fold,
        state: DisplayFeatureState.postureHalfOpened,
      );
      expect(
        await _foldFor(tester,
            size: const Size(829, 690), features: const [book]),
        isNull,
      );
    });

    testWidgets('iPhone hinge half-open on the inner screen', (tester) async {
      FoldPosture.hinge.value =
          const HingeState(HingeStatus.partiallyOpen, 1.6);
      expect(
        await _foldFor(tester, size: const Size(669, 951)),
        const TabletopFold(top: 475.5, bottom: 475.5),
      );
      // The cover screen has no hinge across it.
      expect(await _foldFor(tester, size: const Size(466, 678)), isNull);

      // Landscape: the hinge would run down the middle.
      expect(await _foldFor(tester, size: const Size(951, 669)), isNull);

      FoldPosture.hinge.value = const HingeState(HingeStatus.fullyOpen, 3.1);
      expect(await _foldFor(tester, size: const Size(669, 951)), isNull);
    });

    testWidgets('iPhone hinge opened past an L keeps the normal layout',
        (tester) async {
      // The iPhone Duo simulator's Half fold: ~128°, still a tabletop.
      FoldPosture.hinge.value =
          const HingeState(HingeStatus.partiallyOpen, 2.2301);
      expect(await _foldFor(tester, size: const Size(669, 951)), isNotNull);

      // Opened most of the way, held like a tablet: ~150°.
      FoldPosture.hinge.value =
          const HingeState(HingeStatus.partiallyOpen, 2.62);
      expect(await _foldFor(tester, size: const Size(669, 951)), isNull);

      // Nearly shut.
      FoldPosture.hinge.value =
          const HingeState(HingeStatus.partiallyOpen, 0.3);
      expect(await _foldFor(tester, size: const Size(669, 951)), isNull);

      // Back to an L.
      FoldPosture.hinge.value =
          const HingeState(HingeStatus.partiallyOpen, 1.9);
      expect(await _foldFor(tester, size: const Size(669, 951)), isNotNull);
    });

    testWidgets('simulation splits a window of either orientation',
        (tester) async {
      FoldPosture.simulateTabletop.value = true;
      expect(
        await _foldFor(tester, size: const Size(390, 844)),
        const TabletopFold(top: 422, bottom: 422),
      );
      expect(
        await _foldFor(tester, size: const Size(829, 690)),
        const TabletopFold(top: 345, bottom: 345),
      );
    });
  });

  group('TabletopLayout', () {
    testWidgets('splits at the fold in its own coordinates and keeps the child',
        (tester) async {
      tester.view.physicalSize = _flip;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final childKey = GlobalKey();
      final deckKey = GlobalKey();
      Widget page(TabletopFold? fold) => MaterialApp(
            home: Column(
              children: [
                const SizedBox(height: 50), // a status bar / SafeArea inset
                Expanded(
                  child: TabletopLayout(
                    fold: fold,
                    deck: SizedBox.expand(key: deckKey),
                    child: _Counter(key: childKey),
                  ),
                ),
              ],
            ),
          );

      await tester.pumpWidget(page(null));
      await tester.pump();
      expect(tester.getSize(find.byKey(childKey)).height, 956);
      expect(find.byKey(deckKey), findsNothing);
      final state = tester.state<_CounterState>(find.byKey(childKey));

      await tester.pumpWidget(page(const TabletopFold(top: 503, bottom: 503)));
      await tester.pump();
      // 503 in the window is 453 into the layout, under the 50 px inset.
      expect(tester.getSize(find.byKey(childKey)).height, 453);
      expect(tester.getTopLeft(find.byKey(deckKey)).dy, 503);
      expect(tester.getSize(find.byKey(deckKey)).height, 503);
      // Same State: a video surface in the child would not restart.
      expect(tester.state<_CounterState>(find.byKey(childKey)), same(state));
    });
  });
}

class _Counter extends StatefulWidget {
  const _Counter({super.key});

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
