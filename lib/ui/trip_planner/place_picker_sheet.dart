import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../data/gtfs/gtfs_models.dart';
import '../../domain/location/locate_me.dart';
import '../../domain/trip_planner/place.dart';
import '../../state/providers.dart';
import '../kit/kit.dart';
import '../search/search_screen.dart';

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

/// A sheet for one end of the trip: a stop by number or name, "My location" or "Pick on map".
Future<PlacePick?> showPlacePicker(BuildContext context, {required bool forFrom}) {
  return showGeneralDialog<PlacePick>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: const Color(0x331C2A3A),
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
                                BBPickRow(
                                  icon: BBIcons.stop,
                                  label: '${s.stopName} (${s.stopId})',
                                  semanticLabel: '${s.stopName}, stop ${s.stopId}',
                                  onTap: () => nav.pop(PickedPlace(StopPlace(stopId: s.stopId, name: s.stopName))),
                                ),
                              if (matches.isNotEmpty) const BBDivider(),
                              BBPickRow(
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
                              BBPickRow(
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
