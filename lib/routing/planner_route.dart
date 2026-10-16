import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Back to the trip planner after choosing a place on the map, or giving up: the planner opens over the Map tab, whose
/// map is the plain map again, so back from the planner lands there.
void reopenPlannerOverMap(BuildContext context) {
  final router = GoRouter.of(context);
  router.go('/map');
  router.push('/plan');
}
