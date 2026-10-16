import 'package:busboard_nl/routing/push_once.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  late GoRouter router;

  Future<void> pump(WidgetTester tester) async {
    router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(
          body: PushOnce(
            builder: (context, push) => TextButton(onPressed: () => push('/page'), child: const Text('OPEN')),
          ),
        ),
        // Both above '/', so the page with the button (and its guard) stays in the stack under them.
        routes: [
          GoRoute(path: 'page', builder: (_, _) => const Scaffold(body: Text('PAGE'))),
          GoRoute(path: 'other', builder: (_, _) => const Scaffold(body: Text('OTHER'))),
        ],
      ),
    ]);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  }

  Future<void> doubleTap(WidgetTester tester) async {
    await tester.tap(find.text('OPEN'));
    await tester.tap(find.text('OPEN'));
    await tester.pumpAndSettle();
  }

  testWidgets('a quick double tap pushes the page once', (tester) async {
    await pump(tester);
    await doubleTap(tester);
    expect(find.text('PAGE', skipOffstage: false), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('OPEN'), findsOneWidget);
    expect(router.canPop(), isFalse, reason: 'one back was enough');
  });

  testWidgets('it works again once the page is popped', (tester) async {
    await pump(tester);
    await doubleTap(tester);
    router.pop();
    await tester.pumpAndSettle();
    await doubleTap(tester);
    expect(find.text('PAGE'), findsOneWidget);
  });

  testWidgets('it works again when a link replaced the page instead of a pop', (tester) async {
    await pump(tester);
    await doubleTap(tester);
    router.go('/other'); // the pushed page goes without a pop, so its push never completes
    await tester.pumpAndSettle();
    expect(find.text('OTHER'), findsOneWidget);
    await tester.pumpAndSettle();
    router.go('/');
    await tester.pumpAndSettle();
    await doubleTap(tester);
    expect(find.text('PAGE'), findsOneWidget, reason: 'the guard reset although the push never completed');
  });
}
