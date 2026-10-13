import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../state/home_sheet_provider.dart';
import '../state/map_pick_provider.dart';
import '../ui/alerts/alerts_screen.dart';
import '../ui/home/home_screen.dart';
import '../ui/kit/kit.dart';
import '../ui/search/search_screen.dart';
import '../ui/settings/settings_screen.dart';

/// The app's router.
final appRouter = buildAppRouter();

/// Opens [stopId]'s sheet on home: links and notifications for a stop land here (spec 2026-10-12 §3.6).
String _toStopSheet(BuildContext context, GoRouterState state) {
  final id = state.pathParameters['stopId']!;
  final container = ProviderScope.containerOf(context, listen: false);
  // A redirect can run while the widget tree builds (the first route), when a provider may not change.
  Future.microtask(() => container.read(homeSheetProvider.notifier).open(StopSheet(id)));
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
        pageBuilder: (context, state) => _page(state, const HomeScreen()),
      ),
      GoRoute(path: '/stop/:stopId', redirect: _toStopSheet),
      GoRoute(path: '/board/:stopId', redirect: _toStopSheet),
      GoRoute(path: '/map', redirect: (_, _) => '/'),
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

/// An unknown link: says so, and goes back to the map.
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
