import 'package:adaptive_viewport/adaptive_viewport.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // What UIKit gives an island iPhone on its side, whichever way it is turned.
  const landscape = MediaQueryData(
    size: Size(852, 393),
    padding: EdgeInsets.only(left: 59, right: 59, bottom: 21),
    viewPadding: EdgeInsets.only(left: 59, right: 59, bottom: 21),
  );

  test('keeps only the side the housing is on', () {
    // Home button side on the left: the top of the device is on the right.
    final islandRight = DisplayHousing.trim(landscape, 'landscapeLeft');
    expect(islandRight.padding, const EdgeInsets.only(right: 59, bottom: 21));
    expect(islandRight.viewPadding, islandRight.padding);

    final islandLeft = DisplayHousing.trim(landscape, 'landscapeRight');
    expect(islandLeft.padding, const EdgeInsets.only(left: 59, bottom: 21));
    expect(islandLeft.viewPadding, islandLeft.padding);
  });

  test('leaves everything else as it is', () {
    // No orientation known (Android, or before the first answer).
    expect(DisplayHousing.trim(landscape, null), same(landscape));

    // Portrait: the housing is along the top, not a side.
    const portrait = MediaQueryData(
      size: Size(393, 852),
      padding: EdgeInsets.only(top: 59, bottom: 34),
    );
    expect(DisplayHousing.trim(portrait, 'portrait'), same(portrait));

    // A screen with no side insets at all.
    const plain = MediaQueryData(size: Size(1024, 768));
    expect(DisplayHousing.trim(plain, 'landscapeLeft'), same(plain));

    // An inset that is already one-sided is the screen's own, not UIKit's
    // mirror of it.
    const oneSided = MediaQueryData(
      size: Size(951, 669),
      padding: EdgeInsets.only(left: 82),
    );
    expect(DisplayHousing.trim(oneSided, 'landscapeLeft'), same(oneSided));
  });

  group('punch hole', () {
    MediaQueryData window(Size size, EdgeInsets insets) =>
        MediaQueryData(size: size, padding: insets, viewPadding: insets);

    test('is in the corner it is in on the iPhone Duo cover screen', () {
      // Top of the device on the right: the hole is bottom right.
      expect(
        DisplayHousing.punchHoleOf(
          window(const Size(678, 466), const EdgeInsets.only(right: 84)),
        )!
            .center,
        const Offset(630, 418),
      );
      // The other way round: top left.
      expect(
        DisplayHousing.punchHoleOf(
          window(const Size(678, 466), const EdgeInsets.only(left: 84)),
        )!
            .center,
        const Offset(48, 48),
      );
      // Portrait: top right.
      expect(
        DisplayHousing.punchHoleOf(
          window(
            const Size(466, 678),
            const EdgeInsets.only(right: 84, bottom: 34),
          ),
        )!
            .center,
        const Offset(418, 48),
      );
    });

    test('upright, the read-outs under it take the top of the column only',
        () {
      final readOuts = DisplayHousing.statusReadOutsOf(
        window(
          const Size(466, 678),
          const EdgeInsets.only(right: 84, bottom: 34),
        ),
      )!;
      expect(readOuts.left, 466 - 84.0);
      expect(readOuts.right, 466);
      expect(readOuts.top, 48 + 18.5);
      expect(readOuts.bottom, 158);
      // On its side nothing has been measured beside the hole.
      expect(
        DisplayHousing.statusReadOutsOf(
          window(const Size(678, 466), const EdgeInsets.only(right: 84)),
        ),
        isNull,
      );
    });

    test('the Duo inner screen on its side has read-outs at the column top',
        () {
      final right = DisplayHousing.statusReadOutsOf(
        window(
          const Size(951, 669),
          const EdgeInsets.only(right: 82, bottom: 34),
        ),
      )!;
      expect(right, const Rect.fromLTRB(951 - 82.0, 24, 951, 100));
      final left = DisplayHousing.statusReadOutsOf(
        window(
          const Size(951, 669),
          const EdgeInsets.only(left: 82, bottom: 34),
        ),
      )!;
      expect(left, const Rect.fromLTRB(0, 24, 82, 100));
      // There is no hole, and a mirrored inset says nothing of the side.
      expect(
        DisplayHousing.punchHoleOf(
          window(const Size(951, 669), const EdgeInsets.only(right: 82)),
        ),
        isNull,
      );
      expect(
        DisplayHousing.statusReadOutsOf(
          window(
            const Size(951, 669),
            const EdgeInsets.only(left: 82, right: 82),
          ),
        ),
        isNull,
      );
    });

    test('is not guessed at on any other screen', () {
      // An iPhone 17 Pro in landscape: the Dynamic Island, not a hole.
      expect(
        DisplayHousing.punchHoleOf(
          window(
            const Size(874, 402),
            const EdgeInsets.only(left: 62, right: 62, bottom: 21),
          ),
        ),
        isNull,
      );
      // The Duo's cover screen with no side inset says nothing of which way
      // round it is.
      expect(
        DisplayHousing.punchHoleOf(
          window(const Size(678, 466), EdgeInsets.zero),
        ),
        isNull,
      );
    });
  });
}
