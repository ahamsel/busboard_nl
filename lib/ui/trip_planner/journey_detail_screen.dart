import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/trip_planner/journey.dart';
import '../../state/providers.dart';
import '../kit/kit.dart';
import 'journey_card.dart';

/// One planned trip, leg by leg. A minimal list for now; the full detail comes later (spec §2.3).
class JourneyDetailScreen extends ConsumerWidget {
  const JourneyDetailScreen({super.key, required this.journey});

  final Journey journey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(gtfsRepositoryProvider).value;
    final use24h = BBTime.use24h(context);
    String clock(int s) => BBTime.of(journey.at(s), use24h: use24h);
    return BBScaffold(
      body: ListView(
        children: [
          BBTopBar(title: 'Your trip', onBack: () => context.pop()),
          for (final leg in journey.legs)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: BBSpace.screen, vertical: BBSpace.s),
              child: Text(switch (leg) {
                WalkLeg() => 'Walk ${planMinutes(leg.seconds)} min',
                RideLeg() => 'Route ${routeNameOf(leg.routeId, repo)} · ${clock(leg.departs)} → ${clock(leg.arrives)}',
              }),
            ),
          SizedBox(height: BBNavBar.reservedHeight(context) + BBSpace.l),
        ],
      ),
    );
  }
}
