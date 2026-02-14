import 'package:go_router/go_router.dart';
import '../ui/stop_picker/stop_picker_screen.dart';
import '../ui/board/arrival_board_screen.dart';
import '../ui/settings/settings_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (context, state) => const StopPickerScreen()),
    GoRoute(
      path: '/board/:stopId',
      builder: (context, state) {
        final stopId = state.pathParameters['stopId']!;
        return ArrivalBoardScreen(stopId: stopId);
      },
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsScreen(),
    ),
  ],
);
