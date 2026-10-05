import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:maplibre_gl/maplibre_gl.dart' show LatLng;

import '../../data/gtfs/gtfs_models.dart';
import '../../data/gtfs/gtfs_repository.dart';
import '../../domain/arrival/arrival_models.dart';
import '../../domain/map/bus_tracking_state.dart';
import '../../domain/map/delayed_track_renderer.dart';
import '../../domain/map/follow_tracker.dart';
import '../../domain/map/heading_smoother.dart';
import '../../state/follow_providers.dart';
import '../../state/map_providers.dart';
import '../../state/providers.dart';
import '../copy/legal_copy.dart';
import '../kit/kit.dart';
import 'bus_card.dart';
import 'follow_camera.dart';
import 'follow_card.dart';
import 'map_hit_test.dart';
import 'map_layers.dart';
import 'map_style.dart';
import 'map_surface.dart';
import 'map_view.dart';
import 'my_stop_card.dart';
import 'route_filter_card.dart';
import 'stop_card.dart';

/// What the screen holds while a bus is being followed (spec §3.5): the
/// tracker and camera, whether a gesture has paused the camera, the card's
/// latest snapshot and the route line as last drawn.
class _Follow {
  _Follow(this.vehicleId)
      : snapshot = FollowSnapshot(
          vehicleId: vehicleId,
          bus: null,
          tripId: null,
          stale: false,
          lastSeenAgo: null,
          stops: const [],
          busIndex: -1,
          yourStopIndex: null,
          stopsToYourStop: null,
          arrived: false,
          ended: null,
        );

  final String vehicleId;
  final camera = FollowCamera();
  FollowTracker? tracker;
  bool paused = false;
  FollowSnapshot snapshot;
  DateTime? routeAt;
  double? routeProgress;
  ({List<List<double>> driven, List<List<double>> ahead, Color color})? route;
}

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
  static const _creditMaxTextScale = 1.3;
  static const _creditLeft = BBSpace.s + BBSpace.xs;
  static const _panPauseDistance = 18.0;
  static const _routeInterval = Duration(seconds: 1);
  static const _routeMoveMeters = 20.0;

  MapSurface? _surface;
  MapCamera? _camera;
  MapLayers? _layers;
  Ticker? _ticker;
  Duration? _lastFrameElapsed;
  int _styleGeneration = 0;
  Future<void>? _installing;
  bool _tickersEnabled = true;
  bool _appResumed = true;
  final _controlsKey = GlobalKey();
  // The sheet header's own key and height: one per sheet (a re-keyed sheet's
  // outgoing header is still mounted while the incoming one is built).
  var _headerKey = GlobalKey();
  double? _headerHeight;
  bool _headerMeasureScheduled = false;
  double _controlsHeight = 44 + BBSpace.m + 44;
  bool _measureScheduled = false;
  bool _frameInFlight = false;
  bool _myLocationEnabled = false;
  List<BusMarker> _lastMarkers = const [];
  final _headings = HeadingSmoother();

  _Follow? _follow;
  final _pointerStarts = <int, Offset>{};
  // Where the follow camera must keep the bus and your stop clear of the chips
  // and the peeking sheet; refreshed by every layout.
  EdgeInsets _fitPadding = const EdgeInsets.fromLTRB(48, 96, 48, 220);

  // One controller per selection: BBSheet is re-keyed on every selection, and a
  // DraggableScrollableController can be attached to a single sheet at a time.
  // The incoming sheet attaches before the outgoing one is disposed, so they
  // cannot share a controller. Retired ones are disposed after the frame.
  var _sheet = BBSheetController();
  Object? _sheetKey;
  final _retiredSheets = <BBSheetController>[];

  void _log(String msg) {
    if (kDebugMode) debugPrint('[Map] $msg');
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_enableMyLocation(request: false));
    // A follow set before the map existed (the Board's live row): its card
    // replaces any selection.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ref.read(followProvider) != null) {
        ref.read(mapSelectionProvider.notifier).clear();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final enabled = TickerMode.valuesOf(context).enabled;
    if (enabled == _tickersEnabled) return;
    _tickersEnabled = enabled;
    // An offstage map tab asks for no frames at all.
    if (!enabled) {
      _ticker?.stop();
    } else {
      _resumeTicker();
    }
  }

  /// Starts the draw ticker once there is something to draw on and the app is
  /// on screen.
  void _resumeTicker() {
    final ticker = _ticker;
    if (ticker == null || ticker.isActive || _layers == null || !_appResumed || !_tickersEnabled) return;
    _startTicker();
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _sheet.dispose();
    for (final retired in _retiredSheets) {
      retired.dispose();
    }
    _retiredSheets.clear();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _appResumed = true;
      _resumeTicker();
    }
    if (state == AppLifecycleState.paused) {
      _appResumed = false;
      _ticker?.stop();
    }
  }

  // ─── Map lifecycle ────────────────────────────────────────

  void _onReady(MapSurface surface, MapCamera camera) {
    _surface = surface;
    _camera = camera;
  }

  Future<void> _onStyleLoaded() async {
    // A style (re)load clears everything native: never draw on the old layers,
    // and drop the result of any install that a newer load has overtaken.
    _layers = null;
    final generation = ++_styleGeneration;
    // Two installs must not interleave on one native style ("already exists"):
    // wait for the previous one to finish, whatever its outcome.
    final previous = _installing;
    final done = Completer<void>();
    _installing = done.future;
    try {
      if (previous != null) {
        await previous.catchError((Object _) {});
        if (!mounted || generation != _styleGeneration) return;
      }
      await _install(generation);
    } finally {
      done.complete();
    }
  }

  Future<void> _install(int generation) async {
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
      if (!mounted || generation != _styleGeneration) return;
      await layers.updateMyStop(_myStop());
      if (!mounted || generation != _styleGeneration) return;
      // A new style starts without the route line: draw the last one again.
      final follow = _follow;
      final route = follow?.route;
      if (route != null) {
        await layers.updateRoute(driven: route.driven, ahead: route.ahead, color: route.color);
        if (!mounted || generation != _styleGeneration) return;
        // The follow ended (or moved to another bus) while the line was being
        // drawn: this style must not keep it. The next frame draws the new one.
        if (!identical(follow, _follow)) await layers.clearRoute();
      }
    } catch (e) {
      _log('Could not install map layers: $e');
      return;
    }
    _layers = layers;
    _ticker ??= Ticker(_onTick);
    _resumeTicker();
  }

  void _startTicker() {
    _lastFrameElapsed = null; // the ticker's clock restarts at zero
    _ticker!.start();
  }

  /// A newly chosen stop brings the map to it.
  Future<void> _recentreOn(String stopId) async {
    final camera = _camera;
    final stop = ref.read(stopInfoProvider(stopId));
    if (camera == null || stop == null || !mounted) return;
    try {
      await camera.moveTo(LatLng(stop.stopLat, stop.stopLon), 15, animate: !MediaQuery.disableAnimationsOf(context));
    } catch (e) {
      _log('Could not recentre on the new stop: $e');
    }
  }

  Future<void> _updateMyStop(MapLayers layers) async {
    try {
      await layers.updateMyStop(_myStop());
    } catch (e) {
      _log('Could not update your stop: $e');
    }
  }

  StopInfo? _myStop() {
    final id = ref.read(settingsProvider).selectedStopId;
    return id == null ? null : ref.read(stopInfoProvider(id));
  }

  void _onTick(Duration elapsed) {
    if (!mounted || !_tickersEnabled) return; // an offstage map tab draws nothing
    final last = _lastFrameElapsed;
    if (last != null && elapsed - last < _frameInterval) return;
    _lastFrameElapsed = elapsed;
    if (_frameInFlight) return;
    _frameInFlight = true;
    unawaited(_drawFrame(DateTime.now()).whenComplete(() => _frameInFlight = false));
  }

  Future<void> _drawFrame(DateTime now) async {
    try {
      final layers = _layers;
      final renderer = ref.read(busTrackRendererProvider);
      final store = ref.read(busTrackStoreProvider);
      if (layers == null || renderer == null || store == null) return;
      // The renderer is stateful per vehicle: every track, once per frame; the
      // output is filtered (route filter) after.
      final drawn = renderer.renderAll(store.tracks.values, now);
      final follow = _follow;
      final tracking = ref.read(busTrackingStreamProvider).value ?? const <String, BusTrackingState>{};
      final markers = busMarkers(
        tracking: tracking,
        drawn: drawn,
        routeFilter: ref.read(mapRouteFilterProvider),
        headings: _headings,
        now: now,
        followedVehicleId: follow?.vehicleId,
      );
      _lastMarkers = markers;
      await layers.updateBuses(markers);
      // Follow work rides on the frame, after the buses: the card and camera
      // never see a position the map has not drawn. The follow may have been
      // stopped, or the style reloaded, while the buses were being published.
      if (follow != null && mounted && identical(follow, _follow)) {
        _followFrame(follow, layers, tracking, drawn, now);
      }
    } catch (e) {
      _log('Could not draw buses: $e');
    }
  }

  // ─── Following (spec §3.5) ────────────────────────────────

  void _syncFollow(FollowTarget? target) {
    if (target?.vehicleId == _follow?.vehicleId) return;
    _follow = target == null ? null : _Follow(target.vehicleId);
  }

  /// A new follow, a different one or none: the old route line goes.
  void _onFollowChanged(FollowTarget? next) {
    _syncFollow(next);
    final layers = _layers;
    if (layers != null) {
      unawaited(layers.clearRoute().catchError((Object e) => _log('Could not clear the route line: $e')));
    }
    if (next != null) ref.read(mapSelectionProvider.notifier).clear();
  }

  void _followFrame(
    _Follow f,
    MapLayers layers,
    Map<String, BusTrackingState> tracking,
    Map<String, RenderedBus> drawn,
    DateTime now,
  ) {
    final repo = ref.read(gtfsRepositoryProvider).value;
    final geometry = ref.read(routeGeometryProvider);
    if (repo == null || geometry == null) return;
    final id = f.vehicleId;
    final bus = tracking[id];
    final snap = (f.tracker ??= FollowTracker(vehicleId: id, stopsFor: geometry.tripStops)).update(
      bus: bus,
      drawnProgress: drawn[id]?.progress,
      yourStopId: ref.read(settingsProvider).selectedStopId,
      now: now,
    );
    final changed = snap != f.snapshot;
    f.snapshot = snap;
    if (changed) setState(() {});

    final ended = snap.ended;
    if (ended != null) return _endFollow(ended, id);
    if (bus == null) return;

    final tripId = snap.tripId;
    // After an arrival the bus may roll on to its next trip: the line stays.
    final onTrip = bus.currentTripId == null || bus.currentTripId == tripId;
    if (tripId != null && onTrip && identical(layers, _layers)) {
      final shapeId = bus.shapeId ?? repo.tripsById[tripId]?.shapeId;
      final progress = drawn[id]?.progress ?? bus.progress;
      final routeAt = f.routeAt;
      final lastProgress = f.routeProgress;
      final due = routeAt == null ||
          now.difference(routeAt) >= _routeInterval ||
          (lastProgress != null && progress != null && (progress - lastProgress).abs() >= _routeMoveMeters);
      if (shapeId != null && progress != null && due) {
        final split = geometry.splitShape(shapeId, progress);
        if (split != null) {
          f.routeAt = now;
          f.routeProgress = progress;
          final color = RoutePalette.ofName(_routeLabel(repo, snap) ?? busLabel(bus)).line;
          f.route = (driven: split.driven, ahead: split.ahead, color: color);
          unawaited(layers
              .updateRoute(driven: split.driven, ahead: split.ahead, color: color)
              .catchError((Object e) => _log('Could not draw the route line: $e')));
        }
      }
    }

    final camera = _camera;
    if (f.paused || camera == null) return;
    final at = drawn[id];
    final yourIndex = snap.yourStopIndex;
    final yourStop = yourIndex != null && !snap.arrived && yourIndex < snap.stops.length
        ? repo.stopsById[snap.stops[yourIndex].stopId]
        : null;
    final move = f.camera.next(
      bus: LatLng(at?.lat ?? bus.lat, at?.lon ?? bus.lon),
      stop: yourStop == null ? null : LatLng(yourStop.stopLat, yourStop.stopLon),
      now: now,
    );
    if (move != null) unawaited(_moveCamera(camera, move, animate: !MediaQuery.disableAnimationsOf(context)));
  }

  Future<void> _moveCamera(MapCamera camera, CameraMove move, {required bool animate}) async {
    try {
      switch (move) {
        case FitMove(:final bus, :final stop):
          await camera.fitBounds(bus, stop, padding: _fitPadding, animate: animate);
        case CenterMove(:final target, :final zoom):
          await camera.moveTo(target, zoom, animate: animate);
      }
    } catch (e) {
      _log('Could not move the camera: $e');
    }
  }

  /// The follow is over: stop it (the listener clears the route and drops the
  /// camera) and say why, unless the bus simply arrived.
  void _endFollow(FollowEnd why, String id) {
    ref.read(followProvider.notifier).stop();
    final message = followEndMessage(why, id, _myStop()?.stopName);
    if (message != null && mounted) BBToast.show(context, message);
  }

  /// The followed trip's route number or name (the bus may already be on the
  /// next trip after an arrival).
  String? _routeLabel(GtfsRepository repo, FollowSnapshot snap) {
    final trip = snap.tripId == null ? null : repo.tripsById[snap.tripId!];
    return trip == null ? null : repo.routesById[trip.routeId]?.routeShortName;
  }

  void _resumeFollow(_Follow f) {
    f.camera.reset(); // the next frame moves the camera at once
    if (f.paused) setState(() => f.paused = false);
  }

  void _onPointerMove(PointerMoveEvent e) {
    final f = _follow;
    final start = _pointerStarts[e.pointer];
    if (f == null || f.paused || start == null) return;
    if ((e.position - start).distance > _panPauseDistance) setState(() => f.paused = true);
  }

  void _onPointerEnd(PointerEvent e) => _pointerStarts.remove(e.pointer);

  // ─── Interaction ──────────────────────────────────────────

  void _onTap(LatLng tap) {
    final radius = tapRadiusMeters(_camera?.zoom ?? _defaultZoom);
    final selection = ref.read(mapSelectionProvider.notifier);
    final markers = _lastMarkers.isNotEmpty ? _lastMarkers : _markersFromTracking();
    if (_follow != null) {
      // The follow card owns the sheet: a tap on a bus or a stop does nothing;
      // a tap on empty map brings the sheet back to peek.
      final repo = ref.read(gtfsRepositoryProvider).value;
      final hit = nearestBus(tap, radius, markers) != null ||
          (repo != null && nearestStop(tap, radius, repo.stopsById.values) != null);
      if (!hit) unawaited(_sheet.collapse());
      return;
    }
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
    final wasEnabled = _myLocationEnabled;
    await _enableMyLocation(request: true);
    if (!mounted) return;
    final camera = _camera;
    if (!_myLocationEnabled || camera == null) return;
    // Right after the permission is granted the map has not started its
    // location engine yet: let it build the puck, then ask a few times.
    if (!wasEnabled) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
    }
    final here = await _locate(camera, attempts: wasEnabled ? 1 : 3);
    if (here == null || !mounted) return;
    await camera.moveTo(here, 15, animate: !MediaQuery.disableAnimationsOf(context));
  }

  Future<LatLng?> _locate(MapCamera camera, {required int attempts}) async {
    for (var i = 0; i < attempts; i++) {
      if (i > 0) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        if (!mounted) return null;
      }
      try {
        final here = await camera.myLocation();
        if (!mounted) return null;
        if (here != null) return here;
      } catch (e) {
        _log('Map location failed: $e');
      }
    }
    try {
      final position = await Geolocator.getCurrentPosition();
      return LatLng(position.latitude, position.longitude);
    } catch (e) {
      _log('Device location failed: $e');
      return null;
    }
  }

  /// The controller for the sheet showing [key] (the selection, or the follow);
  /// a new key gets a fresh one.
  BBSheetController _sheetFor(Object? key) {
    if (key != _sheetKey) {
      _sheetKey = key;
      _headerKey = GlobalKey();
      _headerHeight = null;
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
      if (prev == next) return;
      final layers = _layers;
      if (layers != null) unawaited(_updateMyStop(layers));
      if (next != null) unawaited(_recentreOn(next));
    });
    // Keep the live feed subscribed (it drives the track store and the taps)
    // without rebuilding the screen on every poll.
    ref.listen(busTrackingStreamProvider, (_, _) {});
    ref.listen<FollowTarget?>(followProvider, (prev, next) {
      if (prev != next) _onFollowChanged(next);
    });
    _syncFollow(ref.watch(followProvider));
    final follow = _follow;
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
    final selectedStop = selection is StopSelection ? ref.watch(stopInfoProvider(selection.stopId)) : null;
    final repo = gtfs.value!;
    // Minutes to your stop from the live predictions, for the followed bus.
    final yourStopArrivals = follow == null || settings.selectedStopId == null
        ? const <ArrivalRow>[]
        : ref.watch(stopArrivalsProvider(settings.selectedStopId!)).value ?? const <ArrivalRow>[];
    final buildMap = ref.watch(mapViewBuilderProvider);
    final media = MediaQuery.of(context);
    final navInset = BBNavBar.reservedHeight(context);
    final Object? sheetKey = follow == null ? selection : 'follow:${follow.vehicleId}';
    _scheduleControlsMeasure();
    if (_headerHeight == null) _scheduleHeaderMeasure();

    // The credit link: one line, text size capped, measured so MapLibre's own
    // attribution button can sit right after it.
    final creditScaler = media.textScaler.clamp(maxScaleFactor: _creditMaxTextScale);
    final creditPainter = TextPainter(
      text: TextSpan(text: _creditText, style: bb.text.caption),
      textDirection: TextDirection.ltr,
      textScaler: creditScaler,
      maxLines: 1,
    )..layout();
    final creditTextWidth = creditPainter.width;
    final creditTextHeight = creditPainter.height;
    creditPainter.dispose();

    return LayoutBuilder(builder: (context, constraints) {
      // BBSheet pads top + s above and bottomInset + s below, and its fractions
      // apply to what is left: this is where the peeking card's top really is.
      final sheetArea = math.max(1.0, constraints.maxHeight - (media.padding.top + BBSpace.s) - (navInset + BBSpace.s));
      // The peek shows the whole header: handle (8 + 4 + 8) and a little air
      // under it. Until the header has been measured, an estimate.
      final measured = _headerHeight;
      final peekPx = measured == null ? (168 * media.textScaler.scale(1)).clamp(140.0, 320.0) : measured + 20 + BBSpace.s;
      final peek = (peekPx / sheetArea).clamp(0.12, 0.45);
      final peekTop = navInset + BBSpace.s + peek * sheetArea; // from the bottom
      _fitPadding = EdgeInsets.fromLTRB(48, media.padding.top + BBSpace.s + _controlsHeight + 16, 48, peekTop + 16);
      // Just above the card, but below the chips and the my-location pill. With
      // no room, stay on screen and overlap the card's top edge instead.
      final belowControls =
          constraints.maxHeight - (media.padding.top + BBSpace.s + _controlsHeight + BBSpace.s) - creditTextHeight;
      final creditBottom = math.min(
        math.max(math.min(peekTop + BBSpace.xs, belowControls), peekTop - BBSpace.s),
        constraints.maxHeight - creditTextHeight,
      );
      final creditWidth = math.min(creditTextWidth, math.max(0.0, constraints.maxWidth - _creditLeft - BBSpace.s));
      final creditEnd = _creditLeft + creditWidth + BBSpace.s;
      // iOS (MLNMapView) measures the attribution margin from the safe area, so
      // the bottom inset is already in it; Android measures from the view edge.
      final attributionBottom = defaultTargetPlatform == TargetPlatform.iOS
          ? math.max(0.0, creditBottom - media.padding.bottom)
          : creditBottom;

      return ColoredBox(
        color: bb.colors.bg,
        child: Stack(
          children: [
            Positioned.fill(
              // Translucent: the map still gets every touch. Moving a pointer
              // far enough (a pan or a pinch) pauses the follow camera.
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (e) => _pointerStarts[e.pointer] = e.position,
                onPointerMove: _onPointerMove,
                onPointerUp: _onPointerEnd,
                onPointerCancel: _onPointerEnd,
                child: buildMap(MapViewConfig(
                styleString: MapStyle.assetFor(bb.brightness, settings.mapThemeMode),
                initialTarget: myStop == null ? _defaultTarget : LatLng(myStop.stopLat, myStop.stopLon),
                initialZoom: _defaultZoom,
                myLocationEnabled: _myLocationEnabled,
                attributionMargin: math.Point(creditEnd, attributionBottom),
                attributionColor: bb.colors.muted,
                onReady: _onReady,
                onStyleLoaded: () => unawaited(_onStyleLoaded()),
                onTap: _onTap,
                )),
              ),
            ),
            Positioned(
              top: media.padding.top + BBSpace.s,
              left: BBSpace.s,
              right: BBSpace.s,
              child: Column(
                key: _controlsKey,
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Flexible(
                        flex: 3,
                        child: follow != null
                            ? _followChip(follow)
                            : BBChip(
                                label: myStop == null ? 'Choose a stop' : '${myStop.stopName} · ${myStop.stopId}',
                                icon: myStop == null ? BBIcons.search : BBIcons.star,
                                chevron: true,
                                semanticLabel:
                                    myStop == null ? 'Choose a stop' : 'Your stop, ${myStop.stopName}. Change stop',
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
                  const SizedBox(height: BBSpace.m),
                  Align(
                    alignment: Alignment.centerRight,
                    child: BBControlPill(items: [
                      BBControlPillItem(icon: BBIcons.location, semanticLabel: 'My location', onPressed: _goToMyLocation),
                    ]),
                  ),
                ],
              ),
            ),
            Positioned(
              left: _creditLeft,
              right: BBSpace.s,
              bottom: creditBottom,
              // The Align keeps the opaque tap target as wide as the text only: the
              // rest of the band belongs to the map.
              child: Align(
                alignment: Alignment.bottomLeft,
                child: BBPressable(
                  onTap: _openCredits,
                  semanticLabel: 'Map credits',
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 44),
                    child: Align(
                      alignment: Alignment.bottomLeft,
                      widthFactor: 1,
                      child: MediaQuery.withClampedTextScaling(
                        maxScaleFactor: _creditMaxTextScale,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(_creditText, maxLines: 1, overflow: TextOverflow.ellipsis, style: bb.text.caption),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: BBSheet(
                key: ValueKey(sheetKey),
                controller: _sheetFor(sheetKey),
                peekFraction: peek,
                bottomInset: navInset,
                semanticLabel: 'Map sheet',
                header: _measuredHeader(follow != null
                    ? _followHeader(follow, repo, myStop, yourStopArrivals)
                    : switch (selection) {
                        null => MyStopCard.header(),
                        StopSelection() => selectedStop == null ? const SizedBox.shrink() : StopCardHeader(stop: selectedStop),
                        BusSelection(:final vehicleId) => BusCardHeader(vehicleId: vehicleId),
                      }),
                slivers: [
                  SliverToBoxAdapter(
                    child: follow != null
                        ? FollowCardBody(snapshot: follow.snapshot)
                        : switch (selection) {
                            null => MyStopCard.body(),
                            StopSelection() => selectedStop == null ? const SizedBox.shrink() : StopCardBody(stop: selectedStop),
                            BusSelection(:final vehicleId) => BusCardBody(vehicleId: vehicleId),
                          },
                  ),
                ],
              ),
            ),
            if (follow != null && follow.paused)
              Positioned(
                left: 0,
                right: 0,
                // Last in the stack, so it comes and goes without disturbing the sheet.
                // Above the credit link, which sits just over the peeking card.
                bottom: creditBottom + 44 + BBSpace.xs,
                child: Center(child: _backChip(follow)),
              ),
          ],
        ),
      );
    });
  }

  Widget _followChip(_Follow f) => BBChip(
        leading: BBGlyph(BBGlyphKind.liveDot, size: 12, color: context.bb.colors.live),
        label: 'Following bus ${f.vehicleId}',
        onTap: () {
          _resumeFollow(f);
          unawaited(_sheet.collapse());
        },
      );

  Widget _backChip(_Follow f) => BBChip(
        label: 'Back to bus ${f.vehicleId}',
        icon: BBIcons.bus,
        onTap: () => _resumeFollow(f),
      );

  /// The follow card at peek. Its destination, route and delay come from the
  /// followed trip: after an arrival the bus may already be on its next one.
  Widget _followHeader(_Follow f, GtfsRepository repo, StopInfo? myStop, List<ArrivalRow> yourStopArrivals) {
    final snap = f.snapshot;
    final bus = snap.bus;
    final busOnTrip = bus != null && (bus.currentTripId == null || bus.currentTripId == snap.tripId);
    final tripHeadsign = busOnTrip && bus.headsign.isNotEmpty
        ? bus.headsign
        : (snap.tripId == null ? null : repo.tripsById[snap.tripId!]?.tripHeadsign);
    final live = yourStopArrivals.where((a) => a.vehicleNumber == f.vehicleId);
    return FollowCardHeader(
      snapshot: snap,
      yourStopName: myStop?.stopName,
      minutesToYourStop: live.isEmpty ? null : live.first.minutesAway,
      tripHeadsign: tripHeadsign,
      routeLabel: _routeLabel(repo, snap),
      onStop: () => ref.read(followProvider.notifier).stop(),
      onSeeAll: () => unawaited(_sheet.animateToDetent(BBSheetDetent.full)),
    );
  }

  /// Reports the header's height whenever it changes (arrivals load, text
  /// wraps), so the peek can show all of it.
  Widget _measuredHeader(Widget header) => NotificationListener<SizeChangedLayoutNotification>(
        onNotification: (_) {
          _scheduleHeaderMeasure();
          return false;
        },
        child: SizeChangedLayoutNotifier(key: _headerKey, child: header),
      );

  void _scheduleHeaderMeasure() {
    if (_headerMeasureScheduled) return;
    _headerMeasureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _headerMeasureScheduled = false;
      if (!mounted) return;
      final height = _headerKey.currentContext?.size?.height;
      final previous = _headerHeight;
      if (height != null && (previous == null || (height - previous).abs() > 0.5)) {
        setState(() => _headerHeight = height);
      }
    });
  }

  /// The chips and the my-location pill are taller at large text sizes: measure
  /// them after layout so the credit link can stay clear of them.
  void _scheduleControlsMeasure() {
    if (_measureScheduled) return;
    _measureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureScheduled = false;
      if (!mounted) return;
      final height = _controlsKey.currentContext?.size?.height;
      if (height != null && (height - _controlsHeight).abs() > 0.5) setState(() => _controlsHeight = height);
    });
  }
}
