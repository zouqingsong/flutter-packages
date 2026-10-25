// Tabletop posture for foldable phones.
//
// A foldable stood half-open on a table — Samsung's *Flex Mode*, the
// iPhone Duo held the same way — makes two screens out of one: the upper
// half faces the user like a monitor, the lower half lies flat like a
// keyboard. Apps that know this put the picture above the fold and the
// controls below it, and nothing on the crease.
//
// [TabletopBuilder] hands its builder a [TabletopFold] while the device is in
// that posture and `null` otherwise. Where the information comes from:
//
// * **Android** — Flutter's `MediaQuery.displayFeatures`, which carries the
//   fold's bounds and `postureHalfOpened` (Jetpack WindowManager). Exact.
//   Samsung's *Flex mode panel* (Labs) hides the fold from an app it is
//   switched on for: it squeezes the app into the upper half and draws a
//   touchpad below. It has to be off for the app to get its own layout.
// * **iOS 27.1+** — `UIHinge` through this package's plugin
//   (`AdaptiveViewportPlugin`). UIKit reports the hinge's status and angle
//   but not where it is, so the fold is taken
//   to cross the middle of a full-screen window on the inner (tablet-class)
//   screen, held so the crease runs across it (portrait).
// * **Anywhere** — [FoldPosture.simulateTabletop], for simulators, which
//   cannot fold.
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Mirrors `UIHingeStatus`.
enum HingeStatus { unknown, closed, partiallyOpen, fullyOpen }

/// One reading of an iPhone hinge.
@immutable
class HingeState {
  const HingeState(this.status, this.angle);

  final HingeStatus status;

  /// In radians, as UIKit reports it. UIKit makes no promise about how often
  /// or how finely this updates; prefer [status].
  final double angle;

  @override
  bool operator ==(Object other) =>
      other is HingeState && other.status == status && other.angle == angle;

  @override
  int get hashCode => Object.hash(status, angle);

  @override
  String toString() => 'HingeState($status, $angle rad)';
}

/// Where a horizontal fold crosses the window, in logical pixels from its
/// top. [top] equals [bottom] for a seamless fold; a physical hinge has
/// height.
@immutable
class TabletopFold {
  const TabletopFold({required this.top, required this.bottom})
      : assert(bottom >= top);

  final double top;
  final double bottom;

  double get thickness => bottom - top;

  @override
  bool operator ==(Object other) =>
      other is TabletopFold && other.top == top && other.bottom == bottom;

  @override
  int get hashCode => Object.hash(top, bottom);

  @override
  String toString() => 'TabletopFold($top–$bottom)';
}

abstract final class FoldPosture {
  /// Shortest side, in logical pixels, of a screen that unfolds: anything
  /// smaller is a cover screen or an ordinary phone, which have no hinge
  /// across them.
  static const double innerScreenShortestSide = 600.0;

  static const EventChannel _channel = EventChannel('adaptive_viewport/hinge');

  /// The latest iPhone hinge reading, or `null` where there is none (no
  /// hinge, an older iOS, not iOS at all).
  static final ValueNotifier<HingeState?> hinge = ValueNotifier(null);

  /// Pretend the device is half-folded. For simulators, and for trying the
  /// layout on a phone that does not fold. Not persisted.
  static final ValueNotifier<bool> simulateTabletop = ValueNotifier(false);

  /// Fires when either of the above changes. Display-feature changes on
  /// Android arrive through `MediaQuery` instead.
  static final Listenable changes = Listenable.merge([hinge, simulateTabletop]);

  static StreamSubscription<Object?>? _subscription;

  /// Starts listening to the iPhone hinge. Safe to call repeatedly; does
  /// nothing off iOS.
  static void ensureInitialized() {
    if (_subscription != null) return;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    _subscription = _channel.receiveBroadcastStream().listen(
          (event) => hinge.value = parseHingeEvent(event),
          onError: (Object _) => hinge.value = null,
        );
  }

  /// Decodes one event from the plugin. Visible for tests.
  @visibleForTesting
  static HingeState? parseHingeEvent(Object? event) {
    if (event is! Map) return null;
    final status = event['status'];
    final angle = event['angle'];
    return HingeState(
      status is int && status >= 0 && status < HingeStatus.values.length
          ? HingeStatus.values[status]
          : HingeStatus.unknown,
      angle is num ? angle.toDouble() : 0.0,
    );
  }

  /// The fold to lay out around, or `null` when the window should get its
  /// normal layout.
  ///
  /// Only a crease that runs across the window splits it, leaving a picture
  /// above and a control deck below. Half-folded the other way (a book) the
  /// halves are side by side, and the normal layout — which keeps its
  /// controls off the centre line — is the better fit.
  ///
  /// * An Android fold says which way it runs, so it is taken in either
  ///   window orientation: a Galaxy Z Flip stands up in portrait, a Galaxy Z
  ///   Fold's inner screen in landscape.
  /// * The iOS hinge has no position; it is taken to cross a portrait
  ///   window only, and only while folded to roughly an L
  ///   ([isTabletopHinge]). Flat, closed, or opened past
  ///   [tabletopMaxAngle], the window keeps its normal layout.
  /// * The simulate switch splits a window of either orientation, to preview
  ///   both.
  static TabletopFold? tabletopOf(BuildContext context) {
    final size = MediaQuery.sizeOf(context);

    for (final feature in MediaQuery.displayFeaturesOf(context)) {
      final isFold = feature.type == DisplayFeatureType.fold ||
          feature.type == DisplayFeatureType.hinge;
      if (isFold &&
          feature.state == DisplayFeatureState.postureHalfOpened &&
          feature.bounds.width > feature.bounds.height) {
        return TabletopFold(
          top: feature.bounds.top,
          bottom: feature.bounds.bottom,
        );
      }
    }

    final middle = TabletopFold(top: size.height / 2, bottom: size.height / 2);
    if (simulateTabletop.value) return middle;
    if (size.height > size.width &&
        size.shortestSide >= innerScreenShortestSide &&
        isTabletopHinge(hinge.value)) {
      return middle;
    }
    return null;
  }

  /// Hinge angles, in radians, that count as half-folded: 0 is shut, π is
  /// flat. UIKit calls everything between closed and fully open
  /// `partiallyOpen` — a phone opened most of the way and held like a
  /// tablet included — so the status alone is not enough. Only a fold
  /// around an L, one half standing on the other, gets the split. The
  /// upper bound takes in the iPhone Duo's own half-fold position (the
  /// simulator's *Half fold* reports ~128°).
  static const double tabletopMinAngle = 30 * math.pi / 180;
  static const double tabletopMaxAngle = 135 * math.pi / 180;

  /// Whether [state] is a half fold that should split the window.
  static bool isTabletopHinge(HingeState? state) =>
      state != null &&
      state.status == HingeStatus.partiallyOpen &&
      state.angle >= tabletopMinAngle &&
      state.angle <= tabletopMaxAngle;
}

/// Rebuilds with the current [TabletopFold] — on a hinge reading, on the
/// simulate switch, and on any `MediaQuery` change (rotation, Android
/// posture).
class TabletopBuilder extends StatefulWidget {
  const TabletopBuilder({super.key, required this.builder});

  final Widget Function(BuildContext context, TabletopFold? fold) builder;

  @override
  State<TabletopBuilder> createState() => _TabletopBuilderState();
}

class _TabletopBuilderState extends State<TabletopBuilder> {
  @override
  void initState() {
    super.initState();
    FoldPosture.ensureInitialized();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: FoldPosture.changes,
      builder: (context, _) =>
          widget.builder(context, FoldPosture.tabletopOf(context)),
    );
  }
}

/// The standard tabletop arrangement: [child] above the fold, [deck] below
/// it, nothing on the crease. With [fold] `null`, [child] has the whole box.
///
/// [child] keeps the same place in the tree in both postures, so folding
/// does not rebuild it — a live video surface keeps playing.
///
/// [fold] is in window coordinates; the layout finds where it sits in the
/// window itself, so it works under a `SafeArea` or an app bar.
class TabletopLayout extends StatefulWidget {
  const TabletopLayout({
    super.key,
    required this.fold,
    required this.child,
    required this.deck,
  });

  final TabletopFold? fold;
  final Widget child;
  final Widget deck;

  @override
  State<TabletopLayout> createState() => _TabletopLayoutState();
}

class _TabletopLayoutState extends State<TabletopLayout> {
  /// Distance from the window's top to this box's, from the last frame.
  /// Measured on every frame, folded or not, so it is already known on the
  /// first folded one.
  double _originY = 0.0;

  void _measure() {
    if (!mounted) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    final y = box.localToGlobal(Offset.zero).dy;
    if ((y - _originY).abs() > 0.5) setState(() => _originY = y);
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        final fold = widget.fold;
        var top = height;
        var bottom = height;
        if (fold != null && height.isFinite) {
          top = (fold.top - _originY).clamp(0.0, height);
          bottom = (fold.bottom - _originY).clamp(top, height);
        }
        final hasDeck = bottom < height;
        return Column(
          children: [
            SizedBox(
              height: height.isFinite ? top : null,
              width: double.infinity,
              child: widget.child,
            ),
            SizedBox(height: height.isFinite ? bottom - top : 0.0),
            SizedBox(
              height: height.isFinite ? height - bottom : 0.0,
              width: double.infinity,
              child: hasDeck ? widget.deck : const SizedBox.shrink(),
            ),
          ],
        );
      },
    );
  }
}
