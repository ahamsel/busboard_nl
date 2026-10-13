import 'router.dart';

final _boardRoute = RegExp(r'^/board/[^/?#]+$');

/// Opens the Board an alert notification points at (spec §2.2) with [go]; any other payload is ignored.
/// True when it navigated.
bool openNotificationRoute(String? route, void Function(String location) go) {
  if (route == null || !_boardRoute.hasMatch(route)) return false;
  go(route);
  return true;
}

/// [openNotificationRoute] on the app's router. True when it navigated.
bool openAlertRoute(String? route) => openNotificationRoute(route, appRouter.go);
