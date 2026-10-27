import 'package:adaptive_viewport/adaptive_viewport.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late bool needsBack;
  final probe = Builder(builder: (context) {
    needsBack = ShellDestination.needsBackButton(context);
    return const SizedBox();
  });

  testWidgets(
      'a shell destination has no back button, even when the shell '
      'itself was pushed', (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigator,
      home: const SizedBox(),
    ));
    navigator.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => ShellDestination(child: probe),
    ));
    await tester.pumpAndSettle();
    expect(needsBack, isFalse);
  });

  testWidgets('the same page pushed on its own route has a back button',
      (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigator,
      home: const ShellDestination(child: SizedBox()),
    ));
    navigator.currentState!
        .push(MaterialPageRoute<void>(builder: (_) => probe));
    await tester.pumpAndSettle();
    expect(needsBack, isTrue);
  });

  testWidgets('a route pushed on a navigator inside the shell is its own page',
      (tester) async {
    final nested = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      home: ShellDestination(
        child: Navigator(
          key: nested,
          onGenerateRoute: (_) =>
              MaterialPageRoute<void>(builder: (_) => const SizedBox()),
        ),
      ),
    ));
    nested.currentState!.push(MaterialPageRoute<void>(builder: (_) => probe));
    await tester.pumpAndSettle();
    expect(needsBack, isTrue);
  });

  testWidgets('the first route has nothing to go back to', (tester) async {
    await tester.pumpWidget(MaterialApp(home: probe));
    expect(needsBack, isFalse);
  });
}
