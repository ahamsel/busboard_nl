import 'dart:async';
import 'dart:math' show Point;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:maplibre_gl/maplibre_gl.dart' show LatLng;

import '../../data/gtfs/gtfs_models.dart';
import '../../domain/map/bus_tracking_state.dart';
import '../../domain/map/heading_smoother.dart';
import '../../state/map_providers.dart';
import '../../state/providers.dart';
import '../copy/legal_copy.dart';
import '../kit/kit.dart';
import 'bus_card.dart';
import 'map_hit_test.dart';
import 'map_layers.dart';
import 'map_style.dart';
import 'map_surface.dart';
import 'map_view.dart';
import 'my_stop_card.dart';
import 'route_filter_card.dart';
import 'stop_card.dart';

/// The Map tab (spec §3.3): full-screen Harbour map with your-stop and route
/// chips, a my-location control and one floating sheet whose card follows the
/// selection (your stop / a stop / a bus).
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> with WidgetsBindingObserver {
  static const _defaultTarget = LatLng(47.5615, -52.7126);
  static const _defaultZoom = 13.0;
  static const _frameInterval = Duration(milliseconds: 120);
  static const _creditText = '© OpenStreetMap · OpenFreeMap';

  MapSurface? _surface;
  MapCamera? _camera;
  MapLayers? _layers;
  Ticker? _ticker;
  DateTime? _lastFrame;
  bool _frameInFlight = false;
  bool _myLocationEnabled = false;
  List<BusMarker> _lastMarkers = const [];
  final _headings = HeadingSmoother();

  // One controller per selection: BBSheet is re-keyed on every selection, and a
  // DraggableScrollableController can be attached to a single sheet at a time.
  // The incoming sheet attaches before the outgoing one is disposed, so they
  // cannot share a controller. Retired ones are disposed after the frame.
  var _sheet = BBSheetController();
  MapSelection? _sheetSelection;
  final _retiredSheets = <BBSheetController>[];

  void _log(String msg) {
    if (kDebugMode) debugPrint('[Map] $msg');
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_enableMyLocation(request: false));
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _sheet.dispose();
    for (final retired in _retiredSheets) {
      retired.dispose();
    }
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _ticker != null && !_ticker!.isActive) _ticker!.start();
    if (state == AppLifecycleState.paused) _ticker?.stop();
  }

  // ─── Map lifecycle ────────────────────────────────────────

  void _onReady(MapSurface surface, MapCamera camera) {
    _surface = surface;
    _camera = camera;
  }

  Future<void> _onStyleLoaded() async {
    final surface = _surface;
    final repo = ref.read(gtfsRepositoryProvider).value;
    if (surface == null || repo == null || !mounted) return;
    final settings = ref.read(settingsProvider);
    final layers = MapLayers(
      surface,
      brightness: MapStyle.brightnessFor(context.bb.brightness, settings.mapThemeMode),
      pixelRatio: MediaQuery.devicePixelRatioOf(context),
    );
    try {
      await layers.install(stops: repo.stopsById.values);
      await layers.updateMyStop(_myStop());
    } catch (e) {
      _log('Could not install map layers: $e');
      return;
    }
    _layers = layers;
    _ticker ??= Ticker(_onTick);
    if (!_ticker!.isActive) _ticker!.start();
  }

  StopInfo? _myStop() {
    final id = ref.read(settingsProvider).selectedStopId;
    return id == null ? null : ref.read(stopInfoProvider(id));
  }

  void _onTick(Duration _) {
    final now = DateTime.now();
    if (_lastFrame != null && now.difference(_lastFrame!) < _frameInterval) return;
    _lastFrame = now;
    if (_frameInFlight) return;
    _frameInFlight = true;
    unawaited(_drawFrame(now).whenComplete(() => _frameInFlight = false));
  }

  Future<void> _drawFrame(DateTime now) async {
    final layers = _layers;
    final renderer = ref.read(busTrackRendererProvider);
    final store = ref.read(busTrackStoreProvider);
    if (layers == null || renderer == null || store == null) return;
    // The renderer is stateful per vehicle: every track, once per frame; the
    // output is filtered (route filter) after.
    final drawn = renderer.renderAll(store.tracks.values, now);
    final markers = busMarkers(
      tracking: ref.read(busTrackingStreamProvider).value ?? const {},
      drawn: drawn,
      routeFilter: ref.read(mapRouteFilterProvider),
      headings: _headings,
      now: now,
    );
    _lastMarkers = markers;
    try {
      await layers.updateBuses(markers);
    } catch (e) {
      _log('Could not update buses: $e');
    }
  }

  // ─── Interaction ──────────────────────────────────────────

  void _onTap(LatLng tap) {
    final radius = tapRadiusMeters(_camera?.zoom ?? _defaultZoom);
    final selection = ref.read(mapSelectionProvider.notifier);
    final markers = _lastMarkers.isNotEmpty ? _lastMarkers : _markersFromTracking();
    final bus = nearestBus(tap, radius, markers);
    if (bus != null) return _select(BusSelection(bus));
    final repo = ref.read(gtfsRepositoryProvider).value;
    final stop = repo == null ? null : nearestStop(tap, radius, repo.stopsById.values);
    if (stop != null) return _select(StopSelection(stop.stopId));
    if (ref.read(mapSelectionProvider) == null) {
      unawaited(_sheet.collapse());
    } else {
      // Clearing re-keys the sheet, which starts back at peek.
      selection.clear();
    }
  }

  /// Before the first frame is drawn, hit-test the latest fixes.
  List<BusMarker> _markersFromTracking() => busMarkers(
        tracking: ref.read(busTrackingStreamProvider).value ?? const {},
        drawn: const {},
        routeFilter: ref.read(mapRouteFilterProvider),
        headings: HeadingSmoother(),
        now: DateTime.now(),
      );

  void _select(MapSelection selection) {
    ref.read(mapSelectionProvider.notifier).select(selection);
    // The sheet is re-keyed by selection; open the new card at half once built.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_sheet.animateToDetent(BBSheetDetent.half));
    });
  }

  Future<void> _enableMyLocation({required bool request}) async {
    try {
      var permission = await Geolocator.checkPermission();
      if (request && permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      final granted = permission == LocationPermission.whileInUse || permission == LocationPermission.always;
      if (granted && mounted && !_myLocationEnabled) setState(() => _myLocationEnabled = true);
    } catch (e) {
      // No location service on this device: the map simply has no puck.
      _log('Location permission check failed: $e');
    }
  }

  Future<void> _goToMyLocation() async {
    await _enableMyLocation(request: true);
    final camera = _camera;
    if (!_myLocationEnabled || camera == null) return;
    final here = await camera.myLocation();
    if (here == null || !mounted) return;
    await camera.moveTo(here, 15, animate: !MediaQuery.disableAnimationsOf(context));
  }

  /// The controller for the sheet showing [selection]; a new selection gets a
  /// fresh one.
  BBSheetController _sheetFor(MapSelection? selection) {
    if (selection != _sheetSelection) {
      _sheetSelection = selection;
      _retiredSheets.add(_sheet);
      _sheet = BBSheetController();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final retired in _retiredSheets) {
          retired.dispose();
        }
        _retiredSheets.clear();
      });
    }
    return _sheet;
  }

  void _openRouteFilter() {
    final tracking = ref.read(busTrackingStreamProvider).value ?? const <String, BusTrackingState>{};
    final routes = {for (final s in tracking.values) if (s.routeNumber > 0) s.routeNumber}.toList()..sort();
    unawaited(showRouteFilterCard(context, routes: routes));
  }

  void _openCredits() => unawaited(BBDialog.show<void>(
        context,
        title: 'Map credits',
        message: LegalCopy.mapCredit,
        actions: const [BBDialogAction(label: 'OK', value: null, primary: true)],
      ));

  // ─── Layout ───────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(settingsProvider.select((s) => s.selectedStopId), (prev, next) {
      if (prev != next) unawaited(_layers?.updateMyStop(_myStop()));
    });
    // Keep the live feed subscribed (it drives the track store and the taps)
    // without rebuilding the screen on every poll.
    ref.listen(busTrackingStreamProvider, (_, _) {});
    final bb = context.bb;
    final gtfs = ref.watch(gtfsRepositoryProvider);
    if (gtfs.value == null) {
      return ColoredBox(
        color: bb.colors.bg,
        child: Center(
          child: gtfs.hasError
              ? const BBEmptyState(
                  icon: BBIcons.error,
                  title: "Couldn't load the schedule",
                  message: 'Check your connection and try again from Settings.',
                  tone: BBEmptyTone.error,
                )
              : const BBLoading(label: 'Loading the map'),
        ),
      );
    }

    final settings = ref.watch(settingsProvider);
    final myStop = settings.selectedStopId == null ? null : ref.watch(stopInfoProvider(settings.selectedStopId!));
    final filter = ref.watch(mapRouteFilterProvider);
    final selection = ref.watch(mapSelectionProvider);
    final buildMap = ref.watch(mapViewBuilderProvider);
    final media = MediaQuery.of(context);
    final navInset = BBNavBar.reservedHeight(context);

    return LayoutBuilder(builder: (context, constraints) {
      final available = constraints.maxHeight - navInset - media.padding.top;
      final peekPx = (168 * media.textScaler.scale(1)).clamp(140.0, 320.0);
      final peek = (peekPx / available).clamp(0.12, 0.45);
      final creditBottom = navInset + peekPx + BBSpace.s;
      final ratio = defaultTargetPlatform == TargetPlatform.android ? media.devicePixelRatio : 1.0;

      return ColoredBox(
        color: bb.colors.bg,
        child: Stack(
          children: [
            Positioned.fill(
              child: buildMap(MapViewConfig(
                styleString: MapStyle.assetFor(bb.brightness, settings.mapThemeMode),
                initialTarget: myStop == null ? _defaultTarget : LatLng(myStop.stopLat, myStop.stopLon),
                initialZoom: _defaultZoom,
                myLocationEnabled: _myLocationEnabled,
                attributionMargin: Point(BBSpace.s * ratio + 200 * ratio, creditBottom * ratio),
                attributionColor: bb.colors.muted,
                onReady: _onReady,
                onStyleLoaded: () => unawaited(_onStyleLoaded()),
                onTap: _onTap,
              )),
            ),
            Positioned(
              top: media.padding.top + BBSpace.s,
              left: BBSpace.s,
              right: BBSpace.s,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Flexible(
                    flex: 3,
                    child: BBChip(
                      label: myStop == null ? 'Choose a stop' : '${myStop.stopName} · ${myStop.stopId}',
                      icon: myStop == null ? BBIcons.search : BBIcons.star,
                      chevron: true,
                      semanticLabel: myStop == null ? 'Choose a stop' : 'Your stop, ${myStop.stopName}. Change stop',
                      onTap: () => context.go('/'),
                    ),
                  ),
                  const SizedBox(width: BBSpace.s),
                  Flexible(
                    flex: 2,
                    child: BBChip(
                      label: filter.isEmpty ? 'All routes' : 'Routes ${(filter.toList()..sort()).join(', ')}',
                      icon: BBIcons.filter,
                      chevron: true,
                      selected: filter.isNotEmpty,
                      onTap: _openRouteFilter,
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              right: BBSpace.s,
              top: media.padding.top + BBSpace.s + 44 + BBSpace.m,
              child: BBControlPill(items: [
                BBControlPillItem(icon: BBIcons.location, semanticLabel: 'My location', onPressed: _goToMyLocation),
              ]),
            ),
            Positioned(
              left: BBSpace.s + BBSpace.xs,
              bottom: creditBottom,
              child: BBPressable(
                onTap: _openCredits,
                semanticLabel: 'Map credits',
                child: Text(_creditText, style: bb.text.caption),
              ),
            ),
            Positioned.fill(
              child: BBSheet(
                key: ValueKey(selection),
                controller: _sheetFor(selection),
                peekFraction: peek,
                bottomInset: navInset,
                semanticLabel: 'Map sheet',
                header: switch (selection) {
                  null => MyStopCard.header(),
                  StopSelection(:final stopId) => _stopHeader(stopId),
                  BusSelection(:final vehicleId) => BusCardHeader(vehicleId: vehicleId),
                },
                slivers: [
                  SliverToBoxAdapter(
                    child: switch (selection) {
                      null => MyStopCard.body(),
                      StopSelection(:final stopId) => _stopBody(stopId),
                      BusSelection(:final vehicleId) => BusCardBody(vehicleId: vehicleId),
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }

  Widget _stopHeader(String stopId) {
    final stop = ref.watch(stopInfoProvider(stopId));
    return stop == null ? const SizedBox.shrink() : StopCardHeader(stop: stop);
  }

  Widget _stopBody(String stopId) {
    final stop = ref.watch(stopInfoProvider(stopId));
    return stop == null ? const SizedBox.shrink() : StopCardBody(stop: stop);
  }
}
