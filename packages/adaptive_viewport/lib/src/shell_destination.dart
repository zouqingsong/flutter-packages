import 'package:flutter/widgets.dart';

/// Marks a page shown by an app shell as one of its destinations — picked
/// from the shell's sidebar, rail or bottom bar rather than pushed.
///
/// The shell's navigation is the way between its destinations, so a page
/// shown here has no back button: popping from it would pop the shell's own
/// route and leave a blank screen. The same page pushed on its own route
/// (from a phone's home grid, say) is not inside the marker and keeps its
/// back button. Ask [needsBackButton] instead of the screen size or
/// `Navigator.canPop`, which is also true when the shell itself was pushed.
class ShellDestination extends StatelessWidget {
  const ShellDestination({super.key, required this.child});

  final Widget child;

  /// Whether [context] is in a page the shell shows on its own route.
  ///
  /// A route pushed from inside the page — a nested navigator's included —
  /// is a page of its own, not the shell's destination.
  static bool contains(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<_ShellDestinationScope>();
    if (scope == null) return false;
    return scope.route == null || scope.route == ModalRoute.of(context);
  }

  /// Whether the page at [context] should offer a back button: it was
  /// pushed on top of another route and is not one of a shell's
  /// destinations.
  static bool needsBackButton(BuildContext context) {
    if (contains(context)) return false;
    return ModalRoute.of(context)?.impliesAppBarDismissal ?? false;
  }

  @override
  Widget build(BuildContext context) => _ShellDestinationScope(
        route: ModalRoute.of(context),
        child: child,
      );
}

class _ShellDestinationScope extends InheritedWidget {
  const _ShellDestinationScope({required this.route, required super.child});

  final ModalRoute<Object?>? route;

  @override
  bool updateShouldNotify(_ShellDestinationScope oldWidget) =>
      route != oldWidget.route;
}
