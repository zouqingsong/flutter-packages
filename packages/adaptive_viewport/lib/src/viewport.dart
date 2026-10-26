import 'dart:math' as math;
import 'dart:ui' show DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'display_housing.dart';
import 'fold_posture.dart';

/// What the screen leaves a layout to work with, read from what the system
/// reports rather than from a list of devices.
///
/// * [padding] — the safe area, with UIKit's mirrored landscape inset
///   removed from the edge that has no housing (see [DisplayHousing.trim]).
/// * [holes] — small obstacles inside the window: a punch-hole camera and
///   the status read-outs drawn beside it (measured, per screen, on iOS;
///   [DisplayHousing.punchHoleOf], [DisplayHousing.statusReadOutsOf]) and the
///   display cutouts Android reports. A control steps around one of these
///   rather than standing a whole inset in from the edge it is on.
/// * [tabletop] — the fold of a foldable half-open like a laptop, which
///   splits the window into a picture above and a deck below.
/// * [crease] — a fold or hinge running *down* the window (a book), which
///   controls keep off.
@immutable
class ScreenViewport {
  const ScreenViewport({
    required this.size,
    this.padding = EdgeInsets.zero,
    this.holes = const [],
    this.tabletop,
    this.crease,
    this.platform,
  });

  /// [data]'s screen, with the [tabletop] fold worked out by the caller (it
  /// needs the hinge, which [data] does not carry).
  factory ScreenViewport.fromMediaQuery(MediaQueryData data,
      {TabletopFold? tabletop, TargetPlatform? platform}) {
    final holes = <Rect>[];
    final hole = DisplayHousing.punchHoleOf(data);
    if (hole != null) holes.add(hole);
    final readOuts = DisplayHousing.statusReadOutsOf(data);
    if (readOuts != null) holes.add(readOuts);
    Rect? crease;
    for (final feature in data.displayFeatures) {
      switch (feature.type) {
        case DisplayFeatureType.cutout:
          if (!feature.bounds.isEmpty) holes.add(feature.bounds);
        case DisplayFeatureType.fold:
        case DisplayFeatureType.hinge:
          final vertical = feature.bounds.height > feature.bounds.width;
          // A seamless fold lying flat is just screen; a physical hinge is a
          // gap in it whatever the posture.
          final inTheWay = feature.type == DisplayFeatureType.hinge ||
              feature.state == DisplayFeatureState.postureHalfOpened;
          if (vertical && inTheWay) crease = feature.bounds;
        case DisplayFeatureType.unknown:
          break;
      }
    }
    return ScreenViewport(
      size: data.size,
      padding: data.padding,
      holes: List.unmodifiable(holes),
      tabletop: tabletop,
      crease: crease,
      platform: platform,
    );
  }

  /// The viewport of the window [context] is in, kept current by the nearest
  /// [ViewportScope] (which also trims the safe area). Without one, the hinge
  /// is still read but a change to it does not rebuild [context].
  static ScreenViewport of(BuildContext context) {
    context.dependOnInheritedWidgetOfExactType<_ViewportMarker>();
    return ScreenViewport.fromMediaQuery(
      MediaQuery.of(context),
      tabletop: FoldPosture.tabletopOf(context),
    );
  }

  /// The whole window's viewport, whatever box [context] is laid out in.
  ///
  /// [of] reads the nearest `MediaQuery`, whose size is the window's but
  /// whose padding an app bar, a `SafeArea` or a sidebar may already have
  /// taken away. This one is what [ViewportScope] put at the top, so it can be
  /// cut down to a box with [within] without counting anything twice.
  static ScreenViewport windowOf(BuildContext context) {
    final marker =
        context.dependOnInheritedWidgetOfExactType<_ViewportMarker>();
    final data = marker?.data ??
        MediaQuery.maybeOf(context) ??
        MediaQueryData.fromView(View.of(context));
    return ScreenViewport.fromMediaQuery(
      data,
      tabletop: FoldPosture.tabletopOf(context),
    );
  }

  /// This window's viewport as seen from [box], a rectangle in window
  /// coordinates — a page below an app bar, beside a sidebar — in [box]'s own
  /// coordinates.
  ///
  /// The safe area is what of it reaches into [box]; holes and the crease are
  /// kept where they overlap [box]; the tabletop fold is kept while it
  /// crosses [box], so a deck that would fall outside it is not planned.
  ScreenViewport within(Rect box) {
    Rect? local(Rect r) =>
        r.overlaps(box) ? r.intersect(box).shift(-box.topLeft) : null;
    double inset(double edge, double gap) => math.max(0.0, edge - gap);
    TabletopFold? fold;
    final t = tabletop;
    if (t != null) {
      final top = t.top - box.top;
      final bottom = t.bottom - box.top;
      if (top > 0 && bottom < box.height) {
        fold = TabletopFold(top: top, bottom: bottom);
      }
    }
    return ScreenViewport(
      size: box.size,
      padding: EdgeInsets.fromLTRB(
        inset(padding.left, box.left),
        inset(padding.top, box.top),
        inset(padding.right, size.width - box.right),
        inset(padding.bottom, size.height - box.bottom),
      ),
      holes: List.unmodifiable([
        for (final hole in holes)
          if (local(hole) case final h?) h,
      ]),
      tabletop: fold,
      crease: crease == null ? null : local(crease!),
      platform: platform,
    );
  }

  final Size size;
  final EdgeInsets padding;
  final List<Rect> holes;
  final TabletopFold? tabletop;
  final Rect? crease;

  /// The platform the window is on, for its input; null for the one the app
  /// is running on.
  final TargetPlatform? platform;

  bool get isLandscape => size.width > size.height;

  /// Everything a control must stay off, in window coordinates.
  List<Rect> get obstacles => [...holes, if (crease != null) crease!];

  @override
  bool operator ==(Object other) =>
      other is ScreenViewport &&
      other.size == size &&
      other.padding == padding &&
      listEquals(other.holes, holes) &&
      other.tabletop == tabletop &&
      other.crease == crease &&
      other.platform == platform;

  @override
  int get hashCode => Object.hash(
      size, padding, Object.hashAll(holes), tabletop, crease, platform);

  @override
  String toString() =>
      'ScreenViewport($size, padding: $padding, holes: $holes, '
      'tabletop: $tabletop, crease: $crease, platform: $platform)';
}

/// Put once above the app (in `MaterialApp.builder`): starts the native
/// readings, gives everything below it the safe area of the screen it is
/// actually on, and rebuilds [ScreenViewport.of] readers when the hinge or the
/// interface orientation changes — neither of which changes `MediaQuery` by
/// itself.
class ViewportScope extends StatefulWidget {
  const ViewportScope({super.key, required this.child});

  final Widget child;

  @override
  State<ViewportScope> createState() => _ViewportScopeState();
}

class _ViewportScopeState extends State<ViewportScope>
    with WidgetsBindingObserver {
  static final Listenable _changes = Listenable.merge([
    DisplayHousing.orientation,
    FoldPosture.changes,
  ]);

  @override
  void initState() {
    super.initState();
    DisplayHousing.ensureInitialized();
    FoldPosture.ensureInitialized();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() => DisplayHousing.refresh();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _changes,
      builder: (context, child) {
        final data = DisplayHousing.trim(
          MediaQuery.of(context),
          DisplayHousing.orientation.value,
        );
        return MediaQuery(
          data: data,
          child: _ViewportMarker(
            data: data,
            orientation: DisplayHousing.orientation.value,
            hinge: FoldPosture.hinge.value,
            simulateTabletop: FoldPosture.simulateTabletop.value,
            child: child!,
          ),
        );
      },
      child: widget.child,
    );
  }
}

class _ViewportMarker extends InheritedWidget {
  const _ViewportMarker({
    required this.data,
    required this.orientation,
    required this.hinge,
    required this.simulateTabletop,
    required super.child,
  });

  final MediaQueryData data;
  final String? orientation;
  final HingeState? hinge;
  final bool simulateTabletop;

  @override
  bool updateShouldNotify(_ViewportMarker oldWidget) =>
      oldWidget.data != data ||
      oldWidget.orientation != orientation ||
      oldWidget.hinge != hinge ||
      oldWidget.simulateTabletop != simulateTabletop;
}

/// Builds with the [ScreenViewport] of the box it is given rather than of the
/// whole window: a page below an app bar or beside a sidebar is planned for
/// the room it actually has, so nothing it places falls outside it.
///
/// The box's place in the window is measured after layout (from layout
/// offsets, so a route sliding or zooming in does not move it). Until then —
/// the first frame, or the first after the box changes size — the box is
/// taken to sit in the window's bottom trailing corner, which is where an app
/// bar above and a sidebar on the leading side leave it.
class BoxViewportBuilder extends StatefulWidget {
  const BoxViewportBuilder({super.key, required this.builder});

  final Widget Function(BuildContext context, ScreenViewport viewport) builder;

  @override
  State<BoxViewportBuilder> createState() => _BoxViewportBuilderState();
}

class _BoxViewportBuilderState extends State<BoxViewportBuilder> {
  Rect? _measured;

  /// Where [box] is in the window, by the offsets its ancestors laid it out
  /// at. Paint-time transforms — a route's slide, a zoom transition — are
  /// left out on purpose: they are on their way to this position.
  static Offset _layoutOrigin(RenderBox box) {
    var origin = Offset.zero;
    RenderObject? node = box;
    while (node != null) {
      final data = node.parentData;
      if (data is BoxParentData) origin += data.offset;
      node = node.parent;
    }
    return origin;
  }

  void _measure() {
    if (!mounted) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    final rect = _layoutOrigin(box) & box.size;
    final old = _measured;
    if (old == null ||
        (rect.left - old.left).abs() > 0.5 ||
        (rect.top - old.top).abs() > 0.5 ||
        rect.size != old.size) {
      setState(() => _measured = rect);
    }
  }

  @override
  Widget build(BuildContext context) {
    final window = ScreenViewport.windowOf(context);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return LayoutBuilder(
      builder: (context, constraints) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
        final size = Size(
          constraints.hasBoundedWidth
              ? constraints.maxWidth
              : window.size.width,
          constraints.hasBoundedHeight
              ? constraints.maxHeight
              : window.size.height,
        );
        final measured = _measured;
        // Flex arithmetic can differ from the laid-out size by a fraction.
        final origin = measured != null &&
                (measured.width - size.width).abs() < 0.5 &&
                (measured.height - size.height).abs() < 0.5
            ? measured.topLeft
            : Offset(
                rtl ? 0 : math.max(0.0, window.size.width - size.width),
                math.max(0.0, window.size.height - size.height),
              );
        return widget.builder(context, window.within(origin & size));
      },
    );
  }
}

/// A [SafeArea] for one bar, control or target of a scene, never for the
/// scene itself (README rule 2).
///
/// It pads [child] by what of the safe area actually reaches into its own
/// box. A side inset that a camera hole accounts for — the iPhone Duo cover
/// screen's 84 pt column — is treated as the hole it is: [child] moves clear
/// of the hole (and the read-outs beside it) only where its box overlaps
/// them, by the shortest way out, instead of standing the whole column in
/// from that edge. Keeping off a book fold's crease is the layout's job
/// (rule 3), not this widget's.
class LocalSafeArea extends StatefulWidget {
  const LocalSafeArea({
    super.key,
    required this.child,
    this.left = true,
    this.top = true,
    this.right = true,
    this.bottom = true,
    this.minimum = EdgeInsets.zero,
    this.gap = 4,
  });

  final Widget child;
  final bool left;
  final bool top;
  final bool right;
  final bool bottom;

  /// The least padding on each side, as for [SafeArea.minimum].
  final EdgeInsets minimum;

  /// How far [child] keeps from a hole it steps around.
  final double gap;

  /// The padding a box seen as [box] needs in a window seen as [window]:
  /// the safe area that reaches into it, less any side inset that only a
  /// hole accounts for, plus a step around each hole that the box overlaps.
  /// A side turned off is neither padded nor stepped to.
  static EdgeInsets insetsOf(ScreenViewport box, ScreenViewport window,
      {double gap = 4,
      bool left = true,
      bool top = true,
      bool right = true,
      bool bottom = true}) {
    final size = window.size;
    final safe = window.padding;
    bool explained(Rect strip) =>
        !strip.isEmpty && window.holes.any((hole) => hole.overlaps(strip));
    var padding = box.padding;
    if (explained(Rect.fromLTWH(0, 0, safe.left, size.height))) {
      padding = padding.copyWith(left: 0);
    }
    if (explained(
        Rect.fromLTWH(size.width - safe.right, 0, safe.right, size.height))) {
      padding = padding.copyWith(right: 0);
    }
    padding = EdgeInsets.fromLTRB(
      left ? padding.left : 0,
      top ? padding.top : 0,
      right ? padding.right : 0,
      bottom ? padding.bottom : 0,
    );
    final width = box.size.width;
    final height = box.size.height;
    final allowed = [left, right, top, bottom];
    if (width <= 0 || height <= 0 || !allowed.contains(true)) return padding;
    for (final hole in box.holes) {
      final steps = [
        hole.right + gap - padding.left,
        width - hole.left + gap - padding.right,
        hole.bottom + gap - padding.top,
        height - hole.top + gap - padding.bottom,
      ];
      // The shortest way out, as a share of the room it takes away: a bar is
      // not squashed to step over a hole beside it, and a full-width box is
      // not halved to step round a notch above it.
      final costs = [
        steps[0] / width,
        steps[1] / width,
        steps[2] / height,
        steps[3] / height,
      ];
      var side = allowed.indexOf(true);
      for (var i = side + 1; i < costs.length; i++) {
        if (allowed[i] && costs[i] < costs[side]) side = i;
      }
      if (steps[side] <= 0) continue;
      padding = switch (side) {
        0 => padding.copyWith(left: hole.right + gap),
        1 => padding.copyWith(right: width - hole.left + gap),
        2 => padding.copyWith(top: hole.bottom + gap),
        _ => padding.copyWith(bottom: height - hole.top + gap),
      };
    }
    return padding;
  }

  @override
  State<LocalSafeArea> createState() => _LocalSafeAreaState();
}

class _LocalSafeAreaState extends State<LocalSafeArea> {
  /// This widget's own box in the window, padding included, as last laid
  /// out. Measured rather than taken from the constraints, so a rail in a
  /// `Row` (unbounded along it) is placed where it really is.
  Rect? _box;

  void _measure() {
    if (!mounted) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    final rect = _BoxViewportBuilderState._layoutOrigin(box) & box.size;
    final old = _box;
    if (old == null ||
        (rect.left - old.left).abs() > 0.5 ||
        (rect.top - old.top).abs() > 0.5 ||
        (rect.width - old.width).abs() > 0.5 ||
        (rect.height - old.height).abs() > 0.5) {
      setState(() => _box = rect);
    }
  }

  @override
  Widget build(BuildContext context) {
    final window = ScreenViewport.windowOf(context);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    final box = _box;
    // Until it has been laid out, where it is is unknown: pad by nothing but
    // [LocalSafeArea.minimum] for that one frame. Guessing more for every
    // bar at once would overflow the page they share.
    final insets = box == null
        ? EdgeInsets.zero
        : LocalSafeArea.insetsOf(window.within(box), window,
            gap: widget.gap,
            left: widget.left,
            top: widget.top,
            right: widget.right,
            bottom: widget.bottom);
    final minimum = widget.minimum;
    final padding = EdgeInsets.fromLTRB(
      math.max(insets.left, minimum.left),
      math.max(insets.top, minimum.top),
      math.max(insets.right, minimum.right),
      math.max(insets.bottom, minimum.bottom),
    );
    return Padding(
      padding: padding,
      child: MediaQuery.removePadding(
        context: context,
        removeLeft: widget.left,
        removeTop: widget.top,
        removeRight: widget.right,
        removeBottom: widget.bottom,
        child: widget.child,
      ),
    );
  }
}
