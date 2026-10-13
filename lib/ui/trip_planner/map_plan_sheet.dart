import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:maplibre_gl/maplibre_gl.dart' show LatLng;

import '../../data/gtfs/gtfs_repository.dart';
import '../../domain/location/locate_me.dart';
import '../../domain/trip_planner/place.dart';
import '../../state/home_sheet_provider.dart';
import '../../state/providers.dart';
import '../../state/trip_planner_providers.dart';
import '../kit/kit.dart';
import '../map/map_hit_test.dart';

/// A press this close to a stop means the stop.
const mapPlanStopRadiusMeters = 50.0;

/// The place a press on the map at [at] stands for: the stop within [mapPlanStopRadiusMeters], else a pin.
Place mapPlaceAt(GtfsRepository? repo, LatLng at) {
  final stop = repo == null ? null : nearestStop(at, mapPlanStopRadiusMeters, repo.stopsById.values);
  return stop == null
      ? PinPlace(lat: at.latitude, lon: at.longitude, label: 'Dropped pin')
      : StopPlace(stopId: stop.stopId, name: stop.stopName);
}

/// The long-press sheet (spec §2.1): "Plan from here" starts a trip from the press and opens the search for where
/// to (which keeps that start); "Plan to here" starts a fresh trip to it and opens its options, from the phone's
/// position (Ruling 14).
Future<void> showMapPlanSheet(BuildContext context, WidgetRef ref, LatLng at) async {
  final place = mapPlaceAt(ref.read(gtfsRepositoryProvider).value, at);
  final fromHere = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: BBScrim.soft,
    transitionDuration: BBMotion.of(context, BBMotion.standard),
    pageBuilder: (_, _, _) => _MapPlanCard(title: place.label),
    transitionBuilder: (_, animation, _, child) =>
        FadeTransition(opacity: CurvedAnimation(parent: animation, curve: BBMotion.curve), child: child),
  );
  if (fromHere == null || !context.mounted) return;
  final q = ref.read(planQueryProvider.notifier);
  if (fromHere) {
    q.startFrom(place);
    await GoRouter.of(context).push('/search?keep=1');
  } else {
    q.startFresh(place);
    ref.read(homeSheetProvider.notifier).open(const OptionsSheet());
    final here = await locateMe();
    // A start the rider chose while the fix was awaited wins.
    if (here != null) q.fillStart(here);
  }
}

class _MapPlanCard extends StatelessWidget {
  const _MapPlanCard({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    final nav = Navigator.of(context);
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.all(BBSpace.s),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            // Taps on the card's own padding stay on the card instead of reaching the barrier.
            child: Listener(
              behavior: HitTestBehavior.opaque,
              child: DecoratedBox(
                decoration: bb.floating(radius: BBRadius.sheet),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(BBSpace.l),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Semantics(header: true, child: Text(title, style: bb.text.headline)),
                          ),
                          BBIconButton(icon: BBIcons.close, semanticLabel: 'Close', onPressed: () => nav.pop()),
                        ],
                      ),
                      const SizedBox(height: BBSpace.m),
                      BBButton(
                        label: 'Plan from here',
                        icon: BBIcons.plan,
                        kind: BBButtonKind.quiet,
                        expand: true,
                        wrap: true,
                        onPressed: () => nav.pop(true),
                      ),
                      const SizedBox(height: BBSpace.s),
                      BBButton(
                        label: 'Plan to here',
                        icon: BBIcons.pin,
                        expand: true,
                        wrap: true,
                        onPressed: () => nav.pop(false),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
