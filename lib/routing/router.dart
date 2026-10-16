import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../state/home_sheet_provider.dart';
import '../state/home_tab_provider.dart';
import '../state/map_pick_provider.dart';
import '../ui/alerts/alerts_screen.dart';
import '../ui/home/home_shell.dart';
import '../ui/kit/kit.dart';
import '../ui/search/search_screen.dart';
import '../ui/settings/settings_screen.dart';

/// The app's router.
final appRouter = buildAppRouter();

/// A Board link, and an arrival alert's notification (spec 2026-10-15 §2.3): the Board tab, showing [stopId].
String _toBoard(BuildContext context, GoRouterState state) {
  final id = state.pathParameters['stopId']!;
  final container = ProviderScope.containerOf(context, listen: false);
  // A redirect can run while the widget tree builds (the first route), when a provider may not change. The tab is
  // state, so a link that lands before home is built is shown once it is.
  Future.microtask(() => container.read(homeTabProvider.notifier).showBoard(id));
  return '/';
}

/// A stop link: the stop's card on the Map tab (spec 2026-10-12 §3.6).
String _toStopCard(BuildContext context, GoRouterState state) {
  final id = state.pathParameters['stopId']!;
  final container = ProviderScope.containerOf(context, listen: false);
  Future.microtask(() {
    container.read(homeSheetProvider.notifier).open(StopSheet(id));
    container.read(homeTabProvider.notifier).select(HomeTab.map);
  });
  return '/';
}

/// A map link: the Map tab, as it was (final review M7).
String _toMap(BuildContext context, GoRouterState state) {
  final container = ProviderScope.containerOf(context, listen: false);
  Future.microtask(() => container.read(homeTabProvider.notifier).select(HomeTab.map));
  return '/';
}

/// [child] as a page of Flutter's own [MaterialApp], so the theme's page transition (with its iOS edge swipe back)
/// runs. go_router 18 looks for `material_ui`'s MaterialApp, a different class from the one the app uses, and
/// without a page builder falls back to a page with no transition and no swipe back.
Page<void> _page(GoRouterState state, Widget child) => MaterialPage<void>(
      key: state.pageKey,
      name: state.name ?? state.path,
      arguments: <String, String>{...state.pathParameters, ...state.uri.queryParameters},
      restorationId: state.pageKey.value,
      child: child,
    );

/// A fresh router over the app's route tree (tests build their own so no state carries between them).
GoRouter buildAppRouter({String initialLocation = '/'}) {
  return GoRouter(
    initialLocation: initialLocation,
    errorPageBuilder: (context, state) => _page(state, const _NotFound()),
    routes: [
      GoRoute(
        path: '/',
        pageBuilder: (context, state) => _page(state, const HomeShell()),
      ),
      GoRoute(path: '/stop/:stopId', redirect: _toStopCard),
      GoRoute(path: '/board/:stopId', redirect: _toBoard),
      GoRoute(path: '/map', redirect: _toMap),
      GoRoute(
        path: '/plan',
        redirect: (_, _) => '/',
        routes: [GoRoute(path: 'journey', redirect: (_, _) => '/')],
      ),
      GoRoute(
        path: '/search',
        // ?end=from chooses the start; ?save=1 saves a place; ?keep=1 changes the destination of the trip being
        // planned (its start, mode and time stay) where a plain search starts a fresh trip; ?pickStop=1 chooses
        // your stop.
        pageBuilder: (context, state) => _page(
          state,
          SearchScreen(
            end: state.uri.queryParameters['end'] == 'from' ? MapPick.from : MapPick.to,
            save: state.uri.queryParameters['save'] == '1',
            keepStart: state.uri.queryParameters['keep'] == '1',
            pickStop: state.uri.queryParameters['pickStop'] == '1',
          ),
        ),
      ),
      GoRoute(
        path: '/alerts',
        pageBuilder: (context, state) => _page(state, const AlertsScreen()),
      ),
      GoRoute(
        path: '/settings',
        pageBuilder: (context, state) => _page(state, const SettingsScreen()),
      ),
    ],
  );
}

/// An unknown link: says so, and goes home (to the tab used last).
class _NotFound extends StatelessWidget {
  const _NotFound();

  @override
  Widget build(BuildContext context) => BBScaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(BBSpace.screen),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const BBEmptyState(
                    icon: BBIcons.error,
                    title: 'Page not found',
                    message: "This link doesn't go anywhere in BusBoard.",
                  ),
                  const SizedBox(height: BBSpace.l),
                  BBButton(label: 'Home', icon: BBIcons.board, onPressed: () => context.go('/')),
                ],
              ),
            ),
          ),
        ),
      );
}
