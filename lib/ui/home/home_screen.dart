import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:maplibre_gl/maplibre_gl.dart' show LatLng;

import '../../data/gtfs/gtfs_models.dart';
import '../../data/gtfs/gtfs_repository.dart';
import '../../domain/arrival/arrival_models.dart';
import '../../domain/location/locate_me.dart';
import '../../domain/map/bus_tracking_state.dart';
import '../../domain/map/delayed_track_renderer.dart';
import '../../domain/map/follow_tracker.dart';
import '../../domain/map/heading_smoother.dart';
import '../../domain/trip_planner/journey.dart';
import '../../state/follow_providers.dart';
import '../../state/home_sheet_provider.dart';
import '../../state/journey_on_map_provider.dart';
import '../../state/map_pick_provider.dart';
import '../../state/map_providers.dart';
import '../../state/providers.dart';
import '../../state/trip_planner_providers.dart';
import '../arrival_alerts/alert_bell.dart';
import '../copy/legal_copy.dart';
import '../kit/kit.dart';
import '../map/follow_camera.dart';
import '../map/follow_card.dart';
import '../map/journey_lines.dart';
import '../map/map_hit_test.dart';
import '../map/map_layers.dart';
import '../map/map_style.dart';
import '../map/map_surface.dart';
import '../map/map_view.dart';
import '../map/route_filter_card.dart';
import '../trip_planner/map_plan_sheet.dart';
import 'map_buttons.dart';
import 'options_sheet.dart';
import 'sheet_content.dart';

/// From this width the home's sheet is a fixed panel at the left instead of a pull-up sheet (spec §3, tablets).
const homeSidePanelBreakpoint = 700.0;

/// The side panel's width; the map's controls and camera framing shift right by this plus the edge gap.
const homeSidePanelWidth = 400.0;

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
  String? routeShapeId;
  ({List<List<double>> driven, List<List<double>> ahead, Color color})? route;
}

/// The app's home (spec 2026-10-12 §3): the map, the floating controls and one sheet whose content
/// follows the selection. A long-press plans from or to that point; while [mapPickProvider] is set the next
/// tap chooses that end of the trip; a journey from the trip options is drawn on top.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with WidgetsBindingObserver {
  static const _defaultTarget = LatLng(47.5615, -52.7126);
  static const _defaultZoom = 13.0;
  static const _frameInterval = Duration(milliseconds: 120);
  static const _creditText = '© OpenStreetMap · OpenFreeMap';
  static const _creditMaxTextScale = 1.3;
  static const _creditLeft = BBSpace.s + BBSpace.xs;

  /// Follow-camera air at the screen edges: 16 plus half a followed (1.35×)
  /// marker, so a fitted bus or stop badge is never cut by an edge.
  static const double _fitMargin = 64;

  /// Tallest peek for a header, as a share of the sheet area: below the half
  /// detent. Only the follow card's actions may stretch it, up to
  /// [_maxActionsPeek], lifting the half detent above it.
  static const double _maxPeek = 0.45;

  /// The home sheet's own, taller cap.
  static const double _maxHomePeek = 0.55;
  static const double _maxActionsPeek = 0.8;
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
  // After a pause the feed is as old as the pause (iOS stops polling): the
  // follow is not judged until a poll newer than this snapshot arrives.
  bool _awaitingFreshFeed = false;
  Map<String, BusTrackingState>? _feedAtResume;
  // The top row of chips (and the map-pick banner above it): the part of the controls the camera and the
  // credit link keep clear of. The Alerts/Settings/my-location column below it sits at the edge and is cleared
  // sideways by the fit padding's margin.
  final _controlsKey = GlobalKey();
  // The sheet header's own key and height: one per sheet (a re-keyed sheet's
  // outgoing header is still mounted while the incoming one is built).
  var _headerKey = GlobalKey();
  double? _headerHeight;
  // The follow card's actions and how far down the header they end: the peek
  // always shows them.
  var _actionsKey = GlobalKey();
  double? _actionsBottom;
  bool _headerMeasureScheduled = false;
  double _controlsHeight = 44;
  // The "Hide trip" chip, one row under the chips while a journey is drawn: the fit keeps clear of it too.
  final _hideTripKey = GlobalKey();
  double _hideTripHeight = 44;
  bool _measureScheduled = false;
  bool _frameInFlight = false;
  bool _myLocationEnabled = false;
  List<BusMarker> _lastMarkers = const [];
  final _headings = HeadingSmoother();

  _Follow? _follow;
  final _pointerStarts = <int, Offset>{};

  // A planned journey (spec §2.3): drawn one update at a time, each with the
  // journey as it is then, and fitted once the camera can move.
  Future<void> _journeyDraw = Future.value();
  bool _journeyFitPending = false;
  // Where the follow camera must keep the bus and your stop clear of the chips
  // and the peeking sheet; refreshed by every layout.
  EdgeInsets _fitBase = const EdgeInsets.fromLTRB(48, 96, 48, 220);

  /// What the "Hide trip" chip adds under the chips, once a journey is drawn.
  double get _hideTripExtra => BBSpace.m + _hideTripHeight;

  /// [_fitBase] with room for the Hide-trip chip when a journey is drawn. Read when the camera moves, so a journey
  /// that has just been shown (the chip not built yet) already counts.
  EdgeInsets get _fitPadding => ref.read(journeyOnMapProvider) == null
      ? _fitBase
      : _fitBase.copyWith(top: _fitBase.top + _hideTripExtra);

  /// The map's size, for the follow camera's fit.
  Size _mapSize = const Size(390, 844);

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
    _journeyFitPending = ref.read(journeyOnMapProvider) != null;
    // A follow set before the map existed (the Board's live row): its card
    // replaces any selection.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ref.read(followProvider) != null) {
        ref.read(homeSheetProvider.notifier).home();
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
      if (!_appResumed) {
        _awaitingFreshFeed = true;
        _feedAtResume = ref.read(busTrackingStreamProvider).value;
      }
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
    _fitJourneyIfDue();
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
      await layers.updateMyStop(_followStop());
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
    _queueJourneyDraw();
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

  /// Your stop's marker: the follow's own stop while it has one, else the saved stop.
  Future<void> _updateMyStop(MapLayers layers) async {
    try {
      await layers.updateMyStop(_followStop());
    } catch (e) {
      _log('Could not update your stop: $e');
    }
  }

  /// "Your stop" for the follow: the stop it was started for (a planned trip's boarding stop), else the saved one.
  String? _followStopId() => ref.read(followProvider)?.stopId ?? ref.read(settingsProvider).selectedStopId;

  StopInfo? _followStop() {
    final id = _followStopId();
    return id == null ? null : ref.read(stopInfoProvider(id));
  }

  void _onTick(Duration elapsed) {
    if (!mounted || !_tickersEnabled) return; // an offstage map tab draws nothing
    final last = _lastFrameElapsed;
    if (last != null && elapsed - last < _frameInterval) return;
    _lastFrameElapsed = elapsed;
    if (_frameInFlight) return;
    _frameInFlight = true;
    unawaited(_drawFrame(ref.read(mapClockProvider)()).whenComplete(() => _frameInFlight = false));
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
      if (follow != null && mounted && identical(follow, _follow) && _feedIsFresh(follow, now)) {
        _followFrame(follow, layers, tracking, drawn, now);
      }
    } catch (e) {
      _log('Could not draw buses: $e');
    }
  }

  // ─── Following (spec §3.5) ────────────────────────────────

  /// False until the first poll after an app pause (spec §3.5, amended in
  /// the 3b-3 final review): lost contact and not found are never judged on
  /// the snapshot from before the pause. The not-found clock restarts at that
  /// poll, as the pause said nothing about the bus.
  bool _feedIsFresh(_Follow f, DateTime now) {
    if (!_awaitingFreshFeed) return true;
    if (identical(ref.read(busTrackingStreamProvider).value, _feedAtResume)) return false;
    _awaitingFreshFeed = false;
    _feedAtResume = null;
    f.tracker?.restartClock(now);
    return true;
  }

  void _syncFollow(FollowTarget? target) {
    if (target?.vehicleId == _follow?.vehicleId) return;
    _follow = target == null ? null : _Follow(target.vehicleId);
  }

  /// A new follow, a different one or none: the old route line goes. The same
  /// bus for another stop keeps its line (the line is the bus's trip, not the stop's).
  void _onFollowChanged(FollowTarget? next) {
    final sameBus = next != null && next.vehicleId == _follow?.vehicleId;
    _syncFollow(next);
    final layers = _layers;
    if (layers != null && !sameBus) {
      unawaited(layers.clearRoute().catchError((Object e) => _log('Could not clear the route line: $e')));
    }
    if (next != null) ref.read(homeSheetProvider.notifier).home();
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
    final snap = (f.tracker ??= FollowTracker(vehicleId: id, stopsFor: geometry.tripStops, snap: geometry.snap)).update(
      bus: bus,
      drawnProgress: drawn[id]?.progress,
      drawnTripId: drawn[id]?.tripId,
      yourStopId: _followStopId(),
      now: now,
    );
    final changed = snap != f.snapshot;
    f.snapshot = snap;
    if (changed) setState(() {});

    final ended = snap.ended;
    if (ended != null) return _endFollow(ended, id);
    if (bus == null) return;

    final tripId = snap.tripId;
    // The line is the tracker's trip and shape: it stays on the old trip
    // while the bus, relabelled early, is still driving it, and is left as it
    // was once the bus rolls on to its next trip after an arrival.
    if (tripId != null && snap.onTrip && identical(layers, _layers)) {
      final shapeId = snap.shapeId ?? repo.tripsById[tripId]?.shapeId;
      final progress = snap.progress;
      final routeAt = f.routeAt;
      final lastProgress = f.routeProgress;
      // First push, a new shape, or moved 20 m and at least a second since.
      final due = routeAt == null ||
          shapeId != f.routeShapeId ||
          (now.difference(routeAt) >= _routeInterval &&
              (lastProgress == null || (progress != null && (progress - lastProgress).abs() >= _routeMoveMeters)));
      if (shapeId != null && progress != null && due) {
        final split = geometry.splitShape(shapeId, progress);
        if (split != null) {
          f.routeAt = now;
          f.routeProgress = progress;
          f.routeShapeId = shapeId;
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
      padding: _fitPadding,
    );
    if (move != null) unawaited(_moveCamera(camera, move, animate: !MediaQuery.disableAnimationsOf(context)));
  }

  Future<void> _moveCamera(MapCamera camera, CameraMove move, {required bool animate}) async {
    try {
      switch (move) {
        case FitMove(:final bus, :final stop):
          await camera.fitBounds(bus, stop,
              padding: _fitPadding, view: _mapSize, maxZoom: FollowCamera.nearZoom, animate: animate);
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
    final yourStop = _followStop();
    ref.read(followProvider.notifier).stop();
    final message = followEndMessage(why, id, yourStop?.stopName);
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

  // ─── A planned journey (spec §2.3) ────────────────────────

  void _onJourneyChanged(Journey? next) {
    _journeyFitPending = next != null;
    _queueJourneyDraw();
    _fitJourneyIfDue();
  }

  JourneyLines? _journeyLines(Journey j) {
    final repo = ref.read(gtfsRepositoryProvider).value;
    final geometry = ref.read(routeGeometryProvider);
    if (repo == null || geometry == null) return null;
    final shown = ref.read(journeyOnMapProvider.notifier);
    return journeyLines(j, repo, geometry, from: shown.from, to: shown.to);
  }

  /// Draws the journey as it is when this update's turn comes (none clears it).
  void _queueJourneyDraw() {
    _journeyDraw = _journeyDraw.then((_) async {
      final layers = _layers;
      if (!mounted || layers == null) return;
      final j = ref.read(journeyOnMapProvider);
      try {
        final lines = j == null ? null : _journeyLines(j);
        if (lines == null) {
          await layers.clearJourney();
        } else {
          await layers.updateJourney(rides: lines.rides, walks: lines.walks);
        }
      } catch (e) {
        _log('Could not draw the journey: $e');
      }
    });
  }

  /// Brings the whole journey into view, clear of the chips and the sheet. A
  /// follow's camera is paused, so it doesn't pull the view straight back.
  void _fitJourneyIfDue() {
    final camera = _camera;
    final j = ref.read(journeyOnMapProvider);
    if (!_journeyFitPending || camera == null || j == null || !mounted) return;
    final bounds = _journeyLines(j)?.bounds;
    if (bounds == null) return;
    _journeyFitPending = false;
    final f = _follow;
    if (f != null && !f.paused) setState(() => f.paused = true);
    unawaited(_moveCamera(camera, FitMove(bounds.$1, bounds.$2), animate: !MediaQuery.disableAnimationsOf(context)));
  }

  // ─── Interaction ──────────────────────────────────────────

  /// The tap sets the end being picked. A start keeps the sheet as it is; a destination opens its options, starting
  /// from the phone's position when there is no start yet. Everything is taken from [ref] before the fix is awaited.
  void _finishPick(bool forFrom, LatLng tap) {
    final place = mapPlaceAt(ref.read(gtfsRepositoryProvider).value, tap);
    final q = ref.read(planQueryProvider.notifier);
    ref.read(mapPickProvider.notifier).clear();
    if (forFrom) {
      q.setFrom(place);
      return;
    }
    q.setDestination(place);
    ref.read(homeSheetProvider.notifier).open(const OptionsSheet());
    if (ref.read(planQueryProvider).from == null) {
      unawaited(locateMe().then((p) {
        // A start the rider chose while the fix was awaited wins.
        if (p != null && mounted && ref.read(planQueryProvider).from == null) q.setFrom(p);
      }));
    }
  }

  void _onTap(LatLng tap) {
    final pick = ref.read(mapPickProvider);
    if (pick != null) return _finishPick(pick == MapPick.from, tap);
    final radius = tapRadiusMeters(_camera?.zoom ?? _defaultZoom);
    final sheetStack = ref.read(homeSheetProvider.notifier);
    final markers = _lastMarkers.isNotEmpty ? _lastMarkers : _markersFromTracking();
    if (_follow != null && ref.read(homeSheetProvider) is HomeSheetHome) {
      // The follow card is in the sheet: a tap on a bus or a stop does nothing;
      // a tap on empty map brings the sheet back to peek.
      final repo = ref.read(gtfsRepositoryProvider).value;
      final hit = nearestBus(tap, radius, markers) != null ||
          (repo != null && nearestStop(tap, radius, repo.stopsById.values) != null);
      if (!hit) unawaited(_sheet.collapse());
      return;
    }
    final bus = nearestBus(tap, radius, markers);
    if (bus != null) return _open(BusSheet(bus));
    final repo = ref.read(gtfsRepositoryProvider).value;
    final stop = repo == null ? null : nearestStop(tap, radius, repo.stopsById.values);
    if (stop != null) return _open(StopSheet(stop.stopId));
    switch (ref.read(homeSheetProvider)) {
      // A stop's or a bus's card goes: going back re-keys the sheet, which starts back at peek.
      case StopSheet() || BusSheet():
        sheetStack.back();
      // The trip stays drawn while the rider looks at the map (Ruling 13).
      case HomeSheetHome() || OptionsSheet() || JourneySheet():
        unawaited(_sheet.collapse());
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

  void _open(HomeSheet sheet) {
    ref.read(homeSheetProvider.notifier).open(sheet);
    _toHalfAfterBuild();
  }

  /// The sheet is re-keyed by what it shows: opens the new card at half once built.
  void _toHalfAfterBuild() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_sheet.animateToDetent(BBSheetDetent.half));
    });
  }

  /// System back: ends a map pick first, then walks the sheet back (leaving the options takes their drawn trip).
  void _onBack() {
    if (ref.read(mapPickProvider) != null) {
      ref.read(mapPickProvider.notifier).clear();
    } else if (ref.read(homeSheetProvider) is OptionsSheet) {
      leaveOptions(ref);
    } else {
      ref.read(homeSheetProvider.notifier).back();
    }
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
      _actionsKey = GlobalKey();
      _actionsBottom = null;
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

  /// "Choose your stop", "See all stops": the sheet is pulled up to the rest of its content; the side panel is
  /// scrolled down past its header to it.
  void _showMore({required bool wide}) {
    if (!wide) return unawaited(_sheet.animateToDetent(BBSheetDetent.full));
    final header = _headerKey.currentContext;
    final scrollable = header == null ? null : Scrollable.maybeOf(header);
    final headerHeight = _headerHeight;
    if (scrollable == null || headerHeight == null) return;
    final position = scrollable.position;
    unawaited(position.animateTo(
      math.min(headerHeight, position.maxScrollExtent),
      duration: BBMotion.of(context, BBMotion.sheet),
      curve: BBMotion.curve,
    ));
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
      // While following, the follow camera frames the new stop itself.
      if (next != null && _follow == null) unawaited(_recentreOn(next));
    });
    // Keep the live feed subscribed (it drives the track store and the taps)
    // without rebuilding the screen on every poll.
    ref.listen(busTrackingStreamProvider, (_, _) {});
    ref.listen<FollowTarget?>(followProvider, (prev, next) {
      if (prev != next) _onFollowChanged(next);
      // A planned trip's boarding stop is marked for the follow, the saved one after it.
      final layers = _layers;
      if (prev?.stopId != next?.stopId && layers != null) unawaited(_updateMyStop(layers));
    });
    ref.listen<Journey?>(journeyOnMapProvider, (prev, next) {
      if (!identical(prev, next)) _onJourneyChanged(next);
    });
    // Trip options and a journey's steps open at half (spec §3.4), however they were reached.
    ref.listen<HomeSheet>(homeSheetProvider, (prev, next) {
      if (prev != next && (next is OptionsSheet || next is JourneySheet)) _toHalfAfterBuild();
    });
    final journey = ref.watch(journeyOnMapProvider);
    final pick = ref.watch(mapPickProvider);
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
    final sheet = ref.watch(homeSheetProvider);
    final repo = gtfs.value!;
    // The follow's own stop when it was started for one (a planned trip's boarding stop), else the saved stop.
    final followStopId = ref.watch(followProvider)?.stopId ?? settings.selectedStopId;
    final followStop = followStopId == null ? null : ref.watch(stopInfoProvider(followStopId));
    // Minutes to your stop from the live predictions, for the followed bus.
    final followShowing = follow != null && sheet is HomeSheetHome;
    final yourStopArrivals = !followShowing || followStopId == null
        ? const <ArrivalRow>[]
        : ref.watch(stopArrivalsProvider(followStopId)).value ?? const <ArrivalRow>[];
    final buildMap = ref.watch(mapViewBuilderProvider);
    final media = MediaQuery.of(context);
    final navInset = media.padding.bottom;
    final Object sheetKey = followShowing ? 'follow:${follow.vehicleId}' : sheet;
    _scheduleControlsMeasure();
    // While following, the actions move without the header changing size.
    if (_headerHeight == null || followShowing) _scheduleHeaderMeasure();

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
      // On a tablet the sheet is a fixed panel at the left and everything else is laid out to its right.
      final wide = constraints.maxWidth >= homeSidePanelBreakpoint;
      // The panel stands clear of a notch on its side, and everything else of the panel.
      final panelLeft = media.padding.left + BBSpace.s;
      final panelInset = wide ? panelLeft + homeSidePanelWidth : 0.0;
      final hideTripExtra = journey == null ? 0.0 : _hideTripExtra;
      // BBSheet pads top + s above and bottomInset + s below, and its fractions
      // apply to what is left: this is where the peeking card's top really is.
      final sheetArea = math.max(1.0, constraints.maxHeight - (media.padding.top + BBSpace.s) - (navInset + BBSpace.s));
      // The peek shows the whole header: handle (8 + 4 + 8) and a little air
      // under it. Until the header has been measured, an estimate.
      final measured = _headerHeight;
      final peekPx = measured == null ? (168 * media.textScaler.scale(1)).clamp(140.0, 320.0) : measured + 20 + BBSpace.s;
      // Too tall to peek in full: the follow card moves its actions up, and the
      // peek grows (if it must) to keep them in it.
      // The home sheet peeks taller (Where to?, places, alerts and your stop): spec §3.1.
      final maxPeek = sheet is HomeSheetHome && !followShowing ? _maxHomePeek : _maxPeek;
      final headerOverflows = peekPx > maxPeek * sheetArea;
      final actionsPx = !followShowing || _actionsBottom == null ? 0.0 : _actionsBottom! + 20 + BBSpace.s;
      final peek = math.max((peekPx / sheetArea).clamp(0.12, maxPeek), math.min(actionsPx / sheetArea, _maxActionsPeek));
      final peekTop = navInset + BBSpace.s + peek * sheetArea; // from the bottom
      // Just above the card, but below the chips and the my-location pill. With
      // no room, stay on screen and overlap the card's top edge instead.
      final belowControls =
          constraints.maxHeight - (media.padding.top + BBSpace.s + _controlsHeight + hideTripExtra + BBSpace.s) - creditTextHeight;
      // The panel has no peek: the credit sits in the bottom corner of the map beside it.
      final creditBottom = wide
          ? navInset + BBSpace.s
          : math.min(
              math.max(math.min(peekTop + BBSpace.xs, belowControls), peekTop - BBSpace.s),
              constraints.maxHeight - creditTextHeight,
            );
      _mapSize = constraints.biggest;
      // The follow camera keeps the bus and your stop clear of the chips, the
      // credit and the card, with room for half a followed marker on each side.
      _fitBase = EdgeInsets.fromLTRB(
        _fitMargin + panelInset,
        media.padding.top + BBSpace.s + _controlsHeight + _fitMargin / 2,
        _fitMargin,
        wide ? _fitMargin : math.max(peekTop, creditBottom + creditTextHeight) + _fitMargin / 2,
      );
      final creditLeft = _creditLeft + panelInset;
      final creditWidth = math.min(creditTextWidth, math.max(0.0, constraints.maxWidth - creditLeft - BBSpace.s));
      final creditEnd = creditLeft + creditWidth + BBSpace.s;
      // iOS (MLNMapView) measures the attribution margin from the safe area, so
      // the bottom inset is already in it; Android measures from the view edge.
      final attributionBottom = defaultTargetPlatform == TargetPlatform.iOS
          ? math.max(0.0, creditBottom - media.padding.bottom)
          : creditBottom;

      // The same header and body for the pull-up sheet and the side panel. (_sheetFor first: a new selection
      // gets its own header key and sheet controller.)
      final sheetController = _sheetFor(sheetKey);
      final panelHeader = _measuredHeader(followShowing
          ? _followHeader(follow, repo, followStop, yourStopArrivals, actionsFirst: headerOverflows, wide: wide)
          : selectionHeader(sheet, onChooseStop: () => _showMore(wide: wide)));
      final panelSlivers = followShowing
          ? [SliverToBoxAdapter(child: FollowCardBody(snapshot: follow.snapshot))]
          : selectionSlivers(sheet);

      return PopScope(
        canPop: sheet is HomeSheetHome && pick == null,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _onBack();
        },
        child: ColoredBox(
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
                onLongPress: (at) => unawaited(showMapPlanSheet(context, ref, at)),
                )),
              ),
            ),
            Positioned(
              top: media.padding.top + BBSpace.s,
              left: BBSpace.s + panelInset,
              right: BBSpace.s,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Column(
                    key: _controlsKey,
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (pick != null) ...[_pickBanner(pick == MapPick.from), const SizedBox(height: BBSpace.s)],
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          follow != null ? Flexible(flex: 3, child: _followChip(follow)) : const Spacer(flex: 3),
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
                    ],
                  ),
                  const SizedBox(height: BBSpace.m),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: journey == null
                              ? const SizedBox.shrink()
                              : BBChip(
                                  key: _hideTripKey,
                                  label: 'Hide trip',
                                  icon: BBIcons.close,
                                  semanticLabel: 'Hide the trip from the map',
                                  onTap: () => ref.read(journeyOnMapProvider.notifier).clear(),
                                ),
                        ),
                      ),
                      const SizedBox(width: BBSpace.s),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const MapButtons(),
                          const SizedBox(height: BBSpace.s),
                          BBControlPill(items: [
                            BBControlPillItem(icon: BBIcons.location, semanticLabel: 'My location', onPressed: _goToMyLocation),
                          ]),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Positioned(
              left: creditLeft,
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
            if (wide)
              Positioned(
                key: const ValueKey('home-side-panel'),
                left: panelLeft,
                top: media.padding.top + BBSpace.s,
                bottom: media.padding.bottom + BBSpace.s,
                width: homeSidePanelWidth,
                child: Semantics(
                  container: true,
                  label: 'Map sheet',
                  child: DecoratedBox(
                    decoration: bb.floating(radius: BBRadius.sheet),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(BBRadius.sheet),
                      // A new selection starts at the top of a fresh list.
                      child: CustomScrollView(
                        key: ValueKey(sheetKey),
                        slivers: [SliverToBoxAdapter(child: panelHeader), ...panelSlivers],
                      ),
                    ),
                  ),
                ),
              )
            else
              Positioned.fill(
                child: BBSheet(
                  key: ValueKey(sheetKey),
                  controller: sheetController,
                  peekFraction: peek,
                  halfFraction: math.max(0.5, peek + 0.05),
                  bottomInset: navInset,
                  semanticLabel: 'Map sheet',
                  header: panelHeader,
                  slivers: panelSlivers,
                ),
              ),
            if (follow != null && follow.paused)
              Positioned(
                left: panelInset,
                right: 0,
                // Last in the stack, so it comes and goes without disturbing the sheet.
                // Above the credit link, which sits just over the peeking card.
                bottom: creditBottom + 44 + BBSpace.xs,
                child: Center(child: _backChip(follow)),
              ),
          ],
        ),
        ),
      );
    });
  }

  /// What the next tap chooses, and a way out without choosing.
  Widget _pickBanner(bool forFrom) {
    final bb = context.bb;
    void cancel() => ref.read(mapPickProvider.notifier).clear();
    return DecoratedBox(
      decoration: bb.floating(radius: BBRadius.sheet),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(BBSpace.l, BBSpace.xs, BBSpace.xs, BBSpace.xs),
        child: Row(
          children: [
            Icon(BBIcons.pin, size: 20, color: bb.colors.brand),
            const SizedBox(width: BBSpace.s),
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: Text(
                  'Tap the map to choose ${forFrom ? 'your starting point' : 'your destination'}',
                  style: bb.text.body,
                ),
              ),
            ),
            Semantics(
              button: true,
              label: 'Cancel choosing on the map',
              onTap: cancel,
              excludeSemantics: true,
              child: BBButton(label: 'Cancel', kind: BBButtonKind.quiet, wrap: true, onPressed: cancel),
            ),
          ],
        ),
      ),
    );
  }

  Widget _followChip(_Follow f) => BBChip(
        leading: BBGlyph(BBGlyphKind.liveDot, size: 12, color: context.bb.colors.live),
        label: 'Following bus ${f.vehicleId}',
        semanticLabel: 'Following bus ${f.vehicleId}. Back to the bus',
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
  Widget _followHeader(_Follow f, GtfsRepository repo, StopInfo? myStop, List<ArrivalRow> yourStopArrivals,
      {required bool actionsFirst, required bool wide}) {
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
      onSeeAll: () => _showMore(wide: wide),
      actionsFirst: actionsFirst,
      actionsKey: _actionsKey,
      alertAction: live.isEmpty || myStop == null
          ? null
          : AlertBell(arrival: live.first, stopId: myStop.stopId, stopName: myStop.stopName),
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
      final header = _headerKey.currentContext?.findRenderObject();
      final actions = _actionsKey.currentContext?.findRenderObject();
      final actionsBottom = header is RenderBox && actions is RenderBox && actions.attached
          ? actions.localToGlobal(Offset(0, actions.size.height), ancestor: header).dy
          : null;
      final previous = _headerHeight;
      final heightChanged = height != null && (previous == null || (height - previous).abs() > 0.5);
      final actionsChanged = (actionsBottom == null) != (_actionsBottom == null) ||
          (actionsBottom != null && (actionsBottom - _actionsBottom!).abs() > 0.5);
      if (heightChanged || actionsChanged) {
        setState(() {
          if (heightChanged) _headerHeight = height;
          _actionsBottom = actionsBottom;
        });
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
      final hideHeight = _hideTripKey.currentContext?.size?.height;
      final controlsChanged = height != null && (height - _controlsHeight).abs() > 0.5;
      final hideChanged = hideHeight != null && (hideHeight - _hideTripHeight).abs() > 0.5;
      if (controlsChanged || hideChanged) {
        setState(() {
          if (controlsChanged) _controlsHeight = height;
          if (hideChanged) _hideTripHeight = hideHeight;
        });
      }
    });
  }
}
