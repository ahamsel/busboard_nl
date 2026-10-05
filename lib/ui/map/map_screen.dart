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
  static const _creditMaxTextScale = 1.3;
  static const _creditLeft = BBSpace.s + BBSpace.xs;

  MapSurface? _surface;
  MapCamera? _camera;
  MapLayers? _layers;
  Ticker? _ticker;
  Duration? _lastFrameElapsed;
  int _styleGeneration = 0;
  bool _tickersEnabled = true;
  final _controlsKey = GlobalKey();
  double _controlsHeight = 44 + BBSpace.m + 44;
  bool _measureScheduled = false;
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tickersEnabled = TickerMode.valuesOf(context).enabled;
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
    if (state == AppLifecycleState.resumed && _ticker != null && !_ticker!.isActive) _startTicker();
    if (state == AppLifecycleState.paused) _ticker?.stop();
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
    } catch (e) {
      _log('Could not install map layers: $e');
      return;
    }
    _layers = layers;
    _ticker ??= Ticker(_onTick);
    if (!_ticker!.isActive) _startTicker();
  }

  void _startTicker() {
    _lastFrameElapsed = null; // the ticker's clock restarts at zero
    _ticker!.start();
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
      final markers = busMarkers(
        tracking: ref.read(busTrackingStreamProvider).value ?? const {},
        drawn: drawn,
        routeFilter: ref.read(mapRouteFilterProvider),
        headings: _headings,
        now: now,
      );
      _lastMarkers = markers;
      await layers.updateBuses(markers);
    } catch (e) {
      _log('Could not draw buses: $e');
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
      final layers = _layers;
      if (prev != next && layers != null) unawaited(_updateMyStop(layers));
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
    final selectedStop = selection is StopSelection ? ref.watch(stopInfoProvider(selection.stopId)) : null;
    final buildMap = ref.watch(mapViewBuilderProvider);
    final media = MediaQuery.of(context);
    final navInset = BBNavBar.reservedHeight(context);
    _scheduleControlsMeasure();

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
      final peekPx = (168 * media.textScaler.scale(1)).clamp(140.0, 320.0);
      final peek = (peekPx / sheetArea).clamp(0.12, 0.45);
      final peekTop = navInset + BBSpace.s + peek * sheetArea; // from the bottom
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
                attributionMargin: math.Point(creditEnd * ratio, creditBottom * ratio),
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
                        child: BBChip(
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
            Positioned.fill(
              child: BBSheet(
                key: ValueKey(selection),
                controller: _sheetFor(selection),
                peekFraction: peek,
                bottomInset: navInset,
                semanticLabel: 'Map sheet',
                header: switch (selection) {
                  null => MyStopCard.header(),
                  StopSelection() => selectedStop == null ? const SizedBox.shrink() : StopCardHeader(stop: selectedStop),
                  BusSelection(:final vehicleId) => BusCardHeader(vehicleId: vehicleId),
                },
                slivers: [
                  SliverToBoxAdapter(
                    child: switch (selection) {
                      null => MyStopCard.body(),
                      StopSelection() => selectedStop == null ? const SizedBox.shrink() : StopCardBody(stop: selectedStop),
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
