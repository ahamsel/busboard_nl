import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../data/gtfs/gtfs_models.dart';
import '../../data/gtfs/gtfs_repository.dart';
import '../../domain/trip_planner/place.dart';
import '../../state/providers.dart';
import '../kit/kit.dart';

/// What the rider chose in [showPlacePicker].
sealed class PlacePick {
  const PlacePick();
}

/// A stop, or the phone's position.
class PickedPlace extends PlacePick {
  const PickedPlace(this.place);
  final Place place;
}

/// The rider wants to drop a pin on the map.
class PickOnMap extends PlacePick {
  const PickOnMap();
}

/// How long "My location" waits for a fix before it gives up.
const locateTimeLimit = Duration(seconds: 10);

/// The most stops the picker lists.
const maxPlaceMatches = 20;

/// Stops whose id starts with [query] or whose name contains it (any case), at most [maxPlaceMatches], by stop id.
List<StopInfo> matchStops(GtfsRepository repo, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const [];
  final out =
      repo.stopsById.values
          .where((s) => s.stopId.toLowerCase().startsWith(q) || s.stopName.toLowerCase().contains(q))
          .toList()
        ..sort((a, b) => _compareIds(a.stopId, b.stopId));
  return out.take(maxPlaceMatches).toList();
}

int _compareIds(String a, String b) {
  final ai = int.tryParse(a);
  final bi = int.tryParse(b);
  if (ai != null && bi != null) return ai.compareTo(bi);
  if (ai != null) return -1;
  if (bi != null) return 1;
  return a.compareTo(b);
}

/// A sheet for one end of the trip: a stop by number or name, "My location" or "Pick on map".
Future<PlacePick?> showPlacePicker(BuildContext context, {required bool forFrom}) {
  return showGeneralDialog<PlacePick>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: const Color(0x33000000),
    transitionDuration: BBMotion.of(context, BBMotion.standard),
    pageBuilder: (_, _, _) => _PlacePickerCard(forFrom: forFrom),
    transitionBuilder: (_, animation, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: BBMotion.curve),
      child: child,
    ),
  );
}

class _PlacePickerCard extends ConsumerStatefulWidget {
  const _PlacePickerCard({required this.forFrom});

  final bool forFrom;

  @override
  ConsumerState<_PlacePickerCard> createState() => _PlacePickerCardState();
}

class _PlacePickerCardState extends ConsumerState<_PlacePickerCard> {
  String _query = '';

  /// Location services are off, or the rider said no for good (or this phone has none).
  bool _locationOff = false;
  bool _locating = false;

  /// The last try got no fix within [locateTimeLimit]; the row can be tapped again.
  bool _locateFailed = false;

  @override
  void initState() {
    super.initState();
    _checkLocation();
  }

  Future<void> _checkLocation() async {
    var off = false;
    try {
      off =
          !await Geolocator.isLocationServiceEnabled() ||
          await Geolocator.checkPermission() == LocationPermission.deniedForever;
    } catch (_) {
      off = true;
    }
    if (mounted && off) setState(() => _locationOff = true);
  }

  /// The same permission handling as the near-me list ([nearestStopsProvider]).
  Future<void> _useMyLocation() async {
    setState(() {
      _locating = true;
      _locateFailed = false;
    });
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        if (mounted) setState(() => _locationOff = true);
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: locateTimeLimit),
      );
      if (!mounted) return;
      Navigator.of(context)
          .pop(PickedPlace(PinPlace(lat: position.latitude, lon: position.longitude, label: myLocationLabel)));
    } on TimeoutException {
      if (mounted) setState(() => _locateFailed = true);
    } catch (_) {
      if (mounted) setState(() => _locationOff = true);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    final nav = Navigator.of(context);
    final repo = ref.watch(gtfsRepositoryProvider).value;
    final matches = repo == null ? const <StopInfo>[] : matchStops(repo, _query);
    final media = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SafeArea(
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
                  child: Padding(
                    padding: const EdgeInsets.all(BBSpace.l),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Semantics(
                                header: true,
                                child: Text(
                                  widget.forFrom ? 'Choose a starting point' : 'Choose a destination',
                                  style: bb.text.headline,
                                ),
                              ),
                            ),
                            BBIconButton(icon: BBIcons.close, semanticLabel: 'Close', onPressed: () => nav.pop()),
                          ],
                        ),
                        const SizedBox(height: BBSpace.s),
                        BBTextField(
                          hint: 'Stop number or name',
                          leadingIcon: BBIcons.search,
                          autofocus: true,
                          textInputAction: TextInputAction.search,
                          onChanged: (v) => setState(() => _query = v),
                        ),
                        const SizedBox(height: BBSpace.s),
                        Flexible(
                          child: ListView(
                            shrinkWrap: true,
                            padding: EdgeInsets.zero,
                            children: [
                              for (final s in matches)
                                _PickRow(
                                  icon: BBIcons.stop,
                                  label: '${s.stopName} (${s.stopId})',
                                  semanticLabel: '${s.stopName}, stop ${s.stopId}',
                                  onTap: () => nav.pop(PickedPlace(StopPlace(stopId: s.stopId, name: s.stopName))),
                                ),
                              if (matches.isNotEmpty) const BBDivider(),
                              _PickRow(
                                icon: BBIcons.nearMe,
                                label: _locationOff
                                    ? 'Location is off'
                                    : _locating
                                    ? 'Finding you…'
                                    : _locateFailed
                                    ? "Couldn't find your location"
                                    : myLocationLabel,
                                onTap: _locationOff || _locating ? null : _useMyLocation,
                              ),
                              _PickRow(
                                icon: BBIcons.map,
                                label: 'Pick on map',
                                onTap: () => nav.pop(const PickOnMap()),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
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

class _PickRow extends StatelessWidget {
  const _PickRow({required this.icon, required this.label, required this.onTap, this.semanticLabel});

  final IconData icon;
  final String label;
  final String? semanticLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    return BBPressable(
      onTap: onTap,
      semanticLabel: semanticLabel ?? label,
      child: Opacity(
        opacity: onTap == null ? 0.45 : 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: BBSpace.s),
            child: Row(
              children: [
                Icon(icon, size: 20, color: bb.colors.muted),
                const SizedBox(width: BBSpace.m),
                Expanded(child: Text(label, style: bb.text.body)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
