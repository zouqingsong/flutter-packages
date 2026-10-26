import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Which long edge of a landscape iPhone has the sensor housing (the Dynamic
/// Island or the notch) on it.
///
/// UIKit gives a landscape window the housing's inset on *both* sides, so a
/// layout that trusts the safe area leaves the same strip empty along the edge
/// that has nothing on it. The interface orientation is what says which edge
/// is which: it comes from this package's iOS plugin, which also pushes
/// a turn between the two landscapes — a turn that changes neither the
/// window's size nor its insets, so Flutter would not otherwise rebuild.
class DisplayHousing {
  DisplayHousing._();

  static const channelName = 'adaptive_viewport/display_housing';
  static const _channel = MethodChannel(channelName);

  /// The UIKit interface orientation's name, or null where there is none to
  /// read (any platform but iOS, or before the first answer).
  static final ValueNotifier<String?> orientation = ValueNotifier(null);

  static bool _started = false;

  /// Starts listening. Safe to call repeatedly; does nothing off iOS.
  static void ensureInitialized() {
    if (_started || kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }
    _started = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'interfaceOrientation') {
        orientation.value = call.arguments as String?;
      }
    });
    refresh();
  }

  /// Asks for the orientation again: a turn through a quarter does change the
  /// window, and the answer is wanted on that frame rather than after the
  /// rotation animation the native push waits for.
  static Future<void> refresh() async {
    if (!_started) return;
    try {
      orientation.value = await _channel.invokeMethod<String>(
        'interfaceOrientation',
      );
    } on MissingPluginException {
      // An older native build: the symmetric insets are kept.
    } on PlatformException catch (error) {
      debugPrint('display housing unavailable: $error');
    }
  }

  /// [data] with the inset along the edge without the housing removed.
  ///
  /// Only a landscape window whose two side insets are the same is touched:
  /// that symmetry is UIKit's doing, not the screen's. Anything else — portrait,
  /// a screen with no housing, an inset that is already one-sided — is
  /// returned as it is.
  static MediaQueryData trim(MediaQueryData data, String? orientation) {
    // `landscapeLeft` has the home button, and so the bottom of the device, on
    // the left: the housing at its top is on the right. `landscapeRight` is
    // the mirror image.
    final housingOnRight = switch (orientation) {
      'landscapeLeft' => true,
      'landscapeRight' => false,
      _ => null,
    };
    if (housingOnRight == null) return data;

    EdgeInsets trimSide(EdgeInsets insets) {
      if (insets.left <= 0 || (insets.left - insets.right).abs() > 0.5) {
        return insets;
      }
      return housingOnRight
          ? insets.copyWith(left: 0)
          : insets.copyWith(right: 0);
    }

    final padding = trimSide(data.padding);
    final viewPadding = trimSide(data.viewPadding);
    if (padding == data.padding && viewPadding == data.viewPadding) {
      return data;
    }
    return data.copyWith(padding: padding, viewPadding: viewPadding);
  }

  /// Where a punch-hole camera is in [data]'s window, for the screens known to
  /// have one; null on any other. See [ScreenViewport.holes] for every obstacle,
  /// including the cutouts Android reports.
  ///
  /// UIKit reserves a hole the way it reserves the Dynamic Island: the whole
  /// edge it is on, in landscape. The iPhone Duo's cover screen gives a 37 pt
  /// hole in one corner an 84 pt inset down the full height of the window. A
  /// layout that knows where the hole is can keep its controls clear of the hole
  /// itself and use the rest of that edge. Nothing in UIKit says where it is,
  /// so it is measured, per screen.
  static Rect? punchHoleOf(MediaQueryData data) {
    for (final hole in _punchHoles) {
      final found = hole.locate(data.size, data.viewPadding);
      if (found != null) return found;
    }
    return null;
  }

  /// Where the system draws its status read-outs (clock, signal) next to a
  /// punch hole in [data]'s window, for the screens where that is measured;
  /// null on any other.
  ///
  /// Upright, the iPhone Duo's cover screen has no status bar: it reports an
  /// 84 pt inset down its right-hand edge, and puts the clock and the signal
  /// ring in that column under the hole. Only that stretch of the column is
  /// taken; the rest of it is screen like any other, so the picture runs
  /// under it and controls lower down reach the edge.
  static Rect? statusReadOutsOf(MediaQueryData data) {
    for (final hole in _punchHoles) {
      final found = hole.readOuts(data.size);
      if (found != null) return found;
    }
    return null;
  }

  static const _punchHoles = [
    // iPhone Duo, cover screen: top-right in portrait, the clock and signal
    // ring under it to 158 pt from the top.
    _PunchHole(
      portrait: Size(466, 678),
      fromTop: 48,
      fromRight: 48,
      radius: 18.5,
      readOutsColumn: 84,
      readOutsBottom: 158,
    ),
  ];
}

/// A round camera hole in a screen, measured in portrait from the corner it
/// sits in.
class _PunchHole {
  const _PunchHole({
    required this.portrait,
    required this.fromTop,
    required this.fromRight,
    required this.radius,
    this.readOutsColumn = 0,
    this.readOutsBottom = 0,
  });

  /// The screen's size in portrait, which is how it is recognised.
  final Size portrait;

  /// The hole's centre, from the top and right edges in portrait.
  final double fromTop;
  final double fromRight;
  final double radius;

  /// Upright: the width of the column the status read-outs are drawn in under
  /// the hole, and how far down from the top they reach. Zero where the
  /// screen draws none there.
  final double readOutsColumn;
  final double readOutsBottom;

  /// The read-outs under the hole in an upright window of [size], or null.
  ///
  /// Measured upright only: on its side the cover screen has not been seen
  /// to draw them beside the hole.
  Rect? readOuts(Size size) {
    if (size != portrait || readOutsColumn <= 0) return null;
    return Rect.fromLTRB(
      size.width - readOutsColumn,
      fromTop + radius,
      size.width,
      readOutsBottom,
    );
  }

  /// The hole in a window of [size], or null if this is not its screen.
  ///
  /// The hole is at the top of the device, and the safe area is how a
  /// landscape window says which side that is: UIKit insets that side only.
  Rect? locate(Size size, EdgeInsets viewPadding) {
    final Offset centre;
    if (size == portrait) {
      centre = Offset(size.width - fromRight, fromTop);
    } else if (size == portrait.flipped &&
        viewPadding.right > viewPadding.left) {
      // Top of the device on the right (`landscapeLeft`): its right-hand edge
      // is along the bottom.
      centre = Offset(size.width - fromTop, size.height - fromRight);
    } else if (size == portrait.flipped &&
        viewPadding.left > viewPadding.right) {
      // Top on the left (`landscapeRight`): its right-hand edge is along the
      // top.
      centre = Offset(fromTop, fromRight);
    } else {
      return null;
    }
    return Rect.fromCircle(center: centre, radius: radius);
  }
}
