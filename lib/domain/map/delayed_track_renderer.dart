import 'dart:math' as math;

import '../location/nearest_stop_service.dart';
import 'bus_track.dart';
import 'route_geometry.dart';

/// Where to draw one bus this frame.
class RenderedBus {
  const RenderedBus({
    required this.vehicleId,
    required this.lat,
    required this.lon,
    required this.heading,
    this.progress,
    this.shapeId,
    this.tripId,
  });

  final String vehicleId;
  final double lat;
  final double lon;
  final double heading;
  final double? progress;
  final String? shapeId;
  final String? tripId;
}

/// Draws each bus behind live by D (feed latency plus about one fix interval,
/// see [delayFor]), gliding along its route
/// between two real fixes (spec §3.4): render time = now − D, interpolated by
/// distance along the shape, never backward on the same trip; geographic
/// interpolation across a trip change, off route or a backward step of more
/// than 150 m (a pass correction, not motion). Past the newest fix the bus
/// dead-reckons along the shape at the last pair's speed, decaying (see
/// [_beyondLast]), for at most [deadReckonHorizon] and
/// [maxDeadReckonMeters], then holds.
///
/// The last stage is a continuity limiter: the drawn bus never moves faster
/// than [_maxCatchUpMps] (30 m/s) between two consecutive frames of one
/// vehicle. A target further away (a start-up jump, a catch-up after a skipped
/// fix, a pass correction) is approached at that speed, along the shape when
/// both places are on the same trip's shape and the target is ahead, else in a
/// straight line (progress null). The first frame of a vehicle, and a frame
/// more than [_continuityGap] after the previous one (an app resume, a clock
/// jump), snap straight to the target. So does the frame on which a data
/// discontinuity shows: a track re-created for the vehicle (a route change),
/// or a newest fix more than [_dataGapSnap] after the previous newest one (a
/// resumed stream, a feed outage, a stale bus coming back) unless the gap is
/// short, at most [_longDataGap]. A short gap is no reason to jump: it keeps
/// the never-backward rules (so a target behind the mark of the same trip
/// and shape is held, never snapped back), and the limiter catches up at
/// [_gapCatchUpMps] until it reaches the target, along the shape or across
/// a trip change in a straight line.
///
/// [render] updates per-vehicle state (the never-backward mark and the
/// smoothed delay), so call it once per bus per frame with a monotonic
/// `now`; a second call at the same `now` returns the frame already drawn.
/// [renderAll] also drops the state of vehicles it was not given.
class DelayedTrackRenderer {
  DelayedTrackRenderer(this._geometry);

  final RouteGeometry _geometry;

  final Map<String, _VehicleState> _state = {};

  /// The shortest delay: below it a fix arriving a little late already
  /// leaves the bus nothing to glide toward.
  static const Duration minDelay = Duration(seconds: 8);

  /// The longest delay: covers the feed's p90 lag (39 s on the 2026-10-05
  /// rush hour, when 30 s left 13% of frames past the newest fix), at the cost
  /// of drawing the bus that much behind real time.
  static const Duration maxDelay = Duration(seconds: 40);
  static const Duration _delayMargin = Duration(seconds: 1);

  /// Dead-reckoning past the newest fix stops growing after this much render
  /// time: by then the next fix is late, and guessing further is noise.
  static const Duration deadReckonHorizon = Duration(seconds: 20);

  /// Time constant of the dead-reckoning's decay, seconds: the bus is drawn
  /// at the last pair's speed at first, slowing as the guess gets older, so
  /// it eases into a stop rather than halting.
  static const double deadReckonTauSeconds = 7;

  /// Dead-reckoning never runs further than this past the newest fix: under
  /// the [_jitterMeters] hold, so if the bus in fact stopped there, the next
  /// fix is held, never drawn as a step back.
  static const double maxDeadReckonMeters = 55;

  /// With a single fix there is no interval to measure: assume this one.
  static const double _singleFixIntervalSeconds = 15;
  static const int _delaySamples = 8;

  /// How far the drawn delay may move toward its target, per second of wall time.
  static const double _delaySlewPerSecond = 0.1;

  /// Never-backward hold: backward moves up to this far are jitter, held.
  static const double _jitterMeters = 60;

  /// A pair of fixes on one trip whose progress falls by more than this is a
  /// pass correction or a glitch, not motion: the bus glides across the map
  /// between the two snapped points instead of along the shape.
  static const double _glideBackwardMeters = 150;

  /// A forward step along the shape is believed only up to this many times
  /// the map distance between its two places, or that distance plus
  /// [_alongSlackMeters] if more: a bigger step went round a loop or spur the
  /// bus skipped (or the snap reacquired the other pass), so the bus glides
  /// across the map instead. 1.6 covers the winding of a real street between
  /// two fixes.
  static const double _alongStretch = 1.6;

  /// See [_alongStretch]: the slack lets a short turnaround (a terminal loop)
  /// still be drawn along the shape.
  static const double _alongSlackMeters = 200;

  /// A backward jump whose two places are this close on the map is the same
  /// road seen from the other pass: accepted at once.
  static const double _relabelMeters = 40;

  /// A hold of a backward move of more than [_glideBackwardMeters] lasts at
  /// most this long (render time). Smaller backward moves hold until the bus
  /// passes the mark (or the mark is dropped).
  static const Duration _maxHold = Duration(seconds: 15);

  /// The fastest the drawn bus may move between two frames, m/s.
  static const double _maxCatchUpMps = 30;

  /// A newest fix this much later than the previous newest one is a data gap:
  /// the frame that sees it snaps to the target, unless the gap is short on a
  /// continuing track (see [_longDataGap]).
  static const Duration _dataGapSnap = Duration(seconds: 60);

  /// A data gap up to this long glides instead of snapping: the bus is still
  /// near where its track says. Longer, the old place is too stale to glide
  /// from.
  static const Duration _longDataGap = Duration(minutes: 3);

  /// The limiter's speed while catching up after a short data gap, m/s: the
  /// bus may be several hundred metres ahead, and at 30 m/s the catch-up
  /// would take most of a minute.
  static const double _gapCatchUpMps = 60;

  /// Frames further apart than this (wall time) are not continuous.
  static const Duration _continuityGap = Duration(seconds: 2);

  /// A mark whose last use is older than this is from another session of the
  /// bus (a reused trip ID, a re-created track, a resumed app).
  static const Duration _markLifetime = Duration(seconds: 60);

  /// A clock this far behind a mark's last use has moved back.
  static const Duration _clockBackTolerance = Duration(seconds: 1);

  /// The render delay D for [track].
  ///
  /// Smooth motion needs render time (now - D) to stay at or before the newest
  /// GPS time until the next fix arrives, so D must cover the feed's latency
  /// plus one fix interval. Each consecutive pair of the last [_delaySamples]
  /// + 1 fixes gives `lag = next.fetchTime - previous.gpsTime`: how old the
  /// older fix of the pair was when the newer one arrived. D is the
  /// second-largest lag (the largest with fewer than three), plus 1 s, so a
  /// single late fix does not set the delay. With one fix, D is that fix's age
  /// plus 15 s (a typical interval). Clamped to [minDelay]..[maxDelay].
  Duration delayFor(BusTrack track) {
    final fixes = track.fixes;
    final double targetSeconds;
    if (fixes.length < 2) {
      final f = fixes.last;
      targetSeconds = f.fetchTime.difference(f.gpsTime).inMilliseconds / 1000.0 + _singleFixIntervalSeconds;
    } else {
      final lags = <int>[];
      for (var i = fixes.length - 1; i > 0 && lags.length < _delaySamples; i--) {
        lags.add(fixes[i].fetchTime.difference(fixes[i - 1].gpsTime).inMilliseconds);
      }
      lags.sort((a, b) => b.compareTo(a));
      final pick = lags.length >= 3 ? lags[1] : lags[0];
      targetSeconds = pick / 1000.0 + _delayMargin.inMilliseconds / 1000.0;
    }
    final ms = (targetSeconds * 1000).round().clamp(minDelay.inMilliseconds, maxDelay.inMilliseconds);
    return Duration(milliseconds: ms);
  }

  Map<String, RenderedBus> renderAll(Iterable<BusTrack> tracks, DateTime now) {
    final result = {for (final t in tracks) t.vehicleId: render(t, now)};
    _state.removeWhere((id, _) => !result.containsKey(id));
    return result;
  }

  void forget(String vehicleId) => _state.remove(vehicleId);

  /// The delay currently applied to [vehicleId]: [delayFor] eased in at
  /// 0.1 s per second. Null before the bus's first render.
  Duration? currentDelayFor(String vehicleId) {
    final s = _state[vehicleId]?.delaySeconds;
    return s == null ? null : Duration(microseconds: (s * 1e6).round());
  }

  /// How many vehicles hold state; for tests.
  int get debugStateCount => _state.length;

  RenderedBus render(BusTrack track, DateTime now) {
    final fixes = track.fixes;
    final state = _state.putIfAbsent(track.vehicleId, _VehicleState.new);
    // Rendering again at the instant already drawn (two views of one frame)
    // repeats that frame: no recompute, no change to the mark or the delay.
    final drawn = state.drawn;
    if (drawn != null && state.drawnAt == now) return drawn;
    final at = now.subtract(_slewedDelay(track, state, now));
    final discontinuity = _dataDiscontinuity(track, state);
    if (discontinuity == _Discontinuity.shortGap) state.catchingUp = true;
    final snap = discontinuity == _Discontinuity.gap || discontinuity == _Discontinuity.recreated;
    // A track re-created for the vehicle starts afresh: nothing of the old
    // one (mark, anchor) applies to it.
    if (discontinuity == _Discontinuity.recreated) {
      state.mark = null;
      state.anchor = null;
    }
    RenderedBus bus;
    if (!at.isAfter(fixes.first.gpsTime)) {
      bus = _atFix(track.vehicleId, fixes.first);
    } else if (!at.isBefore(fixes.last.gpsTime)) {
      bus = _beyondLast(track, at);
    } else {
      var i = fixes.length - 2;
      while (i > 0 && fixes[i].gpsTime.isAfter(at)) {
        i--;
      }
      final a = fixes[i];
      final b = fixes[i + 1];
      final span = b.gpsTime.difference(a.gpsTime).inMicroseconds;
      final f = span <= 0 ? 1.0 : at.difference(a.gpsTime).inMicroseconds / span;
      bus = _between(track.vehicleId, a, b, f.clamp(0.0, 1.0), at, state.anchor);
    }
    final guarded = snap ? _startMark(bus, at, state) : _neverBackward(bus, at, state);
    if (state.mark != null) state.anchor = state.mark;
    return _limitStep(guarded, now, state, snap: snap);
  }

  /// Whether this frame sees a break in the vehicle's data: a new newest fix
  /// more than [_dataGapSnap] after the previous newest (a short gap when it
  /// is at most [_longDataGap]), or one whose track no longer holds the
  /// previous newest fix (a track re-created for the vehicle; the store trims
  /// only the oldest fixes, so a continuing track always keeps it). Records
  /// the newest fix seen.
  _Discontinuity _dataDiscontinuity(BusTrack track, _VehicleState state) {
    final latest = track.fixes.last.gpsTime;
    final previous = state.latestGps;
    if (previous == latest) return _Discontinuity.none;
    state.latestGps = latest;
    if (previous == null) return _Discontinuity.none;
    if (!track.fixes.any((f) => f.gpsTime == previous)) return _Discontinuity.recreated;
    final gap = latest.difference(previous);
    if (gap <= _dataGapSnap) return _Discontinuity.none;
    return gap <= _longDataGap ? _Discontinuity.shortGap : _Discontinuity.gap;
  }

  /// A snap draws the target as is and starts the never-backward mark at it.
  /// The one exception is a target at most [_jitterMeters] behind the mark of
  /// the same trip and shape (after a long gap on a continuing track): that
  /// is the dead-reckoning overshoot the jitter band exists for, so it is
  /// held.
  RenderedBus _startMark(RenderedBus bus, DateTime at, _VehicleState state) {
    final p = bus.progress;
    final shapeId = bus.shapeId;
    if (p == null || shapeId == null) {
      state.mark = null;
      return bus;
    }
    final mark = state.mark;
    if (mark != null &&
        mark.tripId == bus.tripId &&
        mark.shapeId == shapeId &&
        p < mark.progress &&
        mark.progress - p <= _jitterMeters &&
        !at.isBefore(mark.at.subtract(_clockBackTolerance)) &&
        !at.isAfter(mark.at.add(_markLifetime))) {
      mark.at = at;
      return _onShape(bus.vehicleId, shapeId, mark.progress, bus.tripId) ?? bus;
    }
    state.mark = _Mark(tripId: bus.tripId, shapeId: shapeId, progress: p, at: at);
    return bus;
  }

  /// The delay for this frame: the target, approached at most
  /// [_delaySlewPerSecond] per second of wall time since the previous render.
  Duration _slewedDelay(BusTrack track, _VehicleState state, DateTime now) {
    final target = delayFor(track).inMicroseconds / 1e6;
    var current = state.delaySeconds ?? target;
    final last = state.lastNow;
    if (last != null) {
      final elapsed = now.difference(last).inMicroseconds / 1e6;
      if (elapsed > 0) {
        final step = elapsed * _delaySlewPerSecond;
        current = target > current ? (current + step < target ? current + step : target) : (current - step > target ? current - step : target);
      }
    }
    state.delaySeconds = current;
    state.lastNow = now;
    return Duration(microseconds: (current * 1e6).round());
  }

  /// Final stage: the drawn bus moves at most [_maxCatchUpMps] per second
  /// ([_gapCatchUpMps] while catching up after a short data gap) from where
  /// this vehicle was last drawn toward [target]. See the class doc.
  RenderedBus _limitStep(RenderedBus target, DateTime now, _VehicleState state, {bool snap = false}) {
    final prev = state.drawn;
    final prevNow = state.drawnAt;
    var out = target;
    if (!snap && prev != null && prevNow != null) {
      final gap = now.difference(prevNow);
      if (gap > Duration.zero && gap <= _continuityGap) {
        final mps = state.catchingUp ? _gapCatchUpMps : _maxCatchUpMps;
        out = _towards(prev, target, mps * gap.inMicroseconds / 1e6);
      }
    }
    // The fast catch-up ends once the bus is drawn where it should be.
    if (identical(out, target)) state.catchingUp = false;
    state.drawn = out;
    state.drawnAt = now;
    return out;
  }

  RenderedBus _towards(RenderedBus prev, RenderedBus target, double maxStep) {
    final prevP = prev.progress;
    final targetP = target.progress;
    final shapeId = target.shapeId;
    // Along the shape only when the target is ahead, by a step that fits the
    // map (see [_alongStretch]): a backward target (a relabel to the other
    // pass, a hold expiry) or one round a spur can be far away along the
    // shape yet close or at least straight-line reachable on the map.
    if (prevP != null &&
        targetP != null &&
        shapeId != null &&
        prev.shapeId == shapeId &&
        prev.tripId == target.tripId &&
        targetP >= prevP &&
        _plausibleAlong(targetP - prevP, prev.lat, prev.lon, target.lat, target.lon)) {
      if (targetP - prevP <= maxStep) return target;
      return _onShape(target.vehicleId, shapeId, prevP + maxStep, target.tripId) ?? target;
    }
    final d = NearestStopService.haversineDistance(prev.lat, prev.lon, target.lat, target.lon);
    if (d <= maxStep) return target;
    final f = maxStep / d;
    return RenderedBus(
      vehicleId: target.vehicleId,
      lat: prev.lat + (target.lat - prev.lat) * f,
      lon: prev.lon + (target.lon - prev.lon) * f,
      heading: bearingDegrees(prev.lat, prev.lon, target.lat, target.lon),
      tripId: target.tripId,
    );
  }

  /// Whether a forward step of [along] metres along the shape between two
  /// places fits their map distance (see [_alongStretch]).
  static bool _plausibleAlong(double along, double aLat, double aLon, double bLat, double bLon) {
    if (along <= _alongSlackMeters) return true;
    final geo = NearestStopService.haversineDistance(aLat, aLon, bLat, bLon);
    return along <= math.max(_alongStretch * geo, geo + _alongSlackMeters);
  }

  RenderedBus _atFix(String id, TrackFix f) {
    if (f.progress != null && f.shapeId != null) {
      return _onShape(id, f.shapeId!, f.progress!, f.tripId) ?? _raw(id, f.lat, f.lon, f.heading, f.tripId);
    }
    return _raw(id, f.lat, f.lon, f.heading, f.tripId);
  }

  /// A pair that is not interpolated along one shape (a trip change, an
  /// off-route stretch, a pass correction, a step along the shape that does
  /// not fit the map, see [_alongStretch]) is drawn in a straight line from
  /// [a] to [b]. If the bus was already drawn further along [a]'s trip than
  /// [a] itself (dead-reckoned past it), the line starts at that drawn point
  /// ([mark], the vehicle's last on-shape high-water mark, which survives the
  /// off-shape frames of the glide), so the bus is not pulled back to [a].
  RenderedBus _between(String id, TrackFix a, TrackFix b, double f, DateTime at, _Mark? mark) {
    final sameAxis = a.tripId == b.tripId &&
        a.shapeId != null &&
        a.shapeId == b.shapeId &&
        a.progress != null &&
        b.progress != null &&
        b.progress! >= a.progress! - _glideBackwardMeters &&
        _plausibleAlong(b.progress! - a.progress!, a.snappedLat ?? a.lat, a.snappedLon ?? a.lon, b.snappedLat ?? b.lat, b.snappedLon ?? b.lon);
    if (sameAxis) {
      final p = a.progress! + (b.progress! - a.progress!) * f;
      final onShape = _onShape(id, a.shapeId!, p, b.tripId);
      if (onShape != null) return onShape;
    }
    var aLat = a.snappedLat ?? a.lat;
    var aLon = a.snappedLon ?? a.lon;
    if (mark != null &&
        a.progress != null &&
        a.shapeId != null &&
        mark.tripId == a.tripId &&
        mark.shapeId == a.shapeId &&
        mark.progress > a.progress! &&
        !at.isBefore(mark.at.subtract(_clockBackTolerance)) &&
        !at.isAfter(mark.at.add(_markLifetime))) {
      final start = _geometry.poseAt(a.shapeId!, mark.progress);
      if (start != null) {
        aLat = start.lat;
        aLon = start.lon;
      }
    }
    final bLat = b.snappedLat ?? b.lat;
    final bLon = b.snappedLon ?? b.lon;
    final heading = (aLat == bLat && aLon == bLon) ? b.heading : bearingDegrees(aLat, aLon, bLat, bLon);
    return _raw(id, aLat + (bLat - aLat) * f, aLon + (bLon - aLon) * f, heading, f < 0.5 ? a.tripId : b.tripId);
  }

  /// Render time [at] is past the newest fix: dead-reckoning along the shape
  /// at the last pair's speed v, decaying with time constant τ
  /// ([deadReckonTauSeconds]): v·τ·(1 − e^(−t/τ)) metres ahead after t
  /// seconds, t capped at [deadReckonHorizon], the distance at
  /// [maxDeadReckonMeters]. Only a last pair on one trip and shape whose step
  /// fits the map (see [_alongStretch]) gives a speed; otherwise, and off
  /// the shape, the bus holds at the newest fix.
  RenderedBus _beyondLast(BusTrack track, DateTime at) {
    final fixes = track.fixes;
    final last = fixes.last;
    if (fixes.length >= 2 && last.progress != null && last.shapeId != null) {
      final prev = fixes[fixes.length - 2];
      if (prev.tripId == last.tripId && prev.shapeId == last.shapeId && prev.progress != null) {
        final along = last.progress! - prev.progress!;
        final segSeconds = last.gpsTime.difference(prev.gpsTime).inMilliseconds / 1000.0;
        final plausible = _plausibleAlong(along, prev.snappedLat ?? prev.lat, prev.snappedLon ?? prev.lon, last.snappedLat ?? last.lat, last.snappedLon ?? last.lon);
        final speed = segSeconds <= 0 || !plausible ? 0.0 : (along / segSeconds).clamp(0.0, _maxCatchUpMps);
        final onShape = _onShape(track.vehicleId, last.shapeId!, last.progress! + _deadReckoned(speed, at.difference(last.gpsTime)), last.tripId);
        if (onShape != null) return onShape;
      }
    }
    return _atFix(track.vehicleId, last);
  }

  /// Metres a bus last seen at [speed] m/s is dead-reckoned [past] the fix
  /// (see [_beyondLast]).
  static double _deadReckoned(double speed, Duration past) {
    final horizon = deadReckonHorizon.inMicroseconds / 1e6;
    final t = math.min(past.inMicroseconds / 1e6, horizon);
    final ahead = speed * deadReckonTauSeconds * (1 - math.exp(-t / deadReckonTauSeconds));
    return math.min(ahead, maxDeadReckonMeters);
  }

  RenderedBus? _onShape(String id, String shapeId, double progress, String? tripId) {
    final length = _geometry.shapeLength(shapeId);
    final clamped = length == null ? progress : progress.clamp(0.0, length);
    final pose = _geometry.poseAt(shapeId, clamped);
    if (pose == null) return null;
    return RenderedBus(vehicleId: id, lat: pose.lat, lon: pose.lon, heading: pose.heading, progress: clamped, shapeId: shapeId, tripId: tripId);
  }

  RenderedBus _raw(String id, double lat, double lon, double heading, String? tripId) =>
      RenderedBus(vehicleId: id, lat: lat, lon: lon, heading: heading, tripId: tripId);

  /// Holds a bus that would move backward along its trip, within limits: a
  /// small step back (<= [_jitterMeters]) is jitter and held; a bigger one
  /// that lands within [_relabelMeters] of the mark on the map is the same
  /// place on the other pass and accepted; any other is held until the bus
  /// passes the mark, except that one of more than [_glideBackwardMeters] is
  /// held for at most [_maxHold] of render time, then accepted. Drawing
  /// without a progress (off route, across a trip change) forgets the mark.
  RenderedBus _neverBackward(RenderedBus bus, DateTime at, _VehicleState state) {
    final p = bus.progress;
    final shapeId = bus.shapeId;
    if (p == null || shapeId == null) {
      state.mark = null;
      return bus;
    }
    var mark = state.mark;
    if (mark != null && (at.isBefore(mark.at.subtract(_clockBackTolerance)) || at.isAfter(mark.at.add(_markLifetime)))) {
      mark = null;
    }
    if (mark == null || mark.tripId != bus.tripId || mark.shapeId != shapeId || p >= mark.progress) {
      state.mark = _Mark(tripId: bus.tripId, shapeId: shapeId, progress: p, at: at);
      return bus;
    }
    final markPose = _geometry.poseAt(shapeId, mark.progress);
    final held = _onShape(bus.vehicleId, shapeId, mark.progress, bus.tripId);
    if (held == null || markPose == null) {
      state.mark = _Mark(tripId: bus.tripId, shapeId: shapeId, progress: p, at: at);
      return bus;
    }
    if (mark.progress - p <= _jitterMeters) {
      mark.at = at;
      state.mark = mark;
      return held;
    }
    final pose = _geometry.poseAt(shapeId, p);
    if (pose != null && NearestStopService.haversineDistance(pose.lat, pose.lon, markPose.lat, markPose.lon) <= _relabelMeters) {
      // A relabel makes a new mark: any hold under way ends with it.
      state.mark = _Mark(tripId: bus.tripId, shapeId: shapeId, progress: p, at: at);
      return bus;
    }
    final holdStart = mark.holdStart ?? at;
    if (mark.progress - p > _glideBackwardMeters && at.difference(holdStart) > _maxHold) {
      state.mark = _Mark(tripId: bus.tripId, shapeId: shapeId, progress: p, at: at);
      return bus;
    }
    mark
      ..at = at
      ..holdStart = holdStart;
    state.mark = mark;
    return held;
  }
}

/// The furthest progress drawn for a bus on one trip and shape, and when it
/// was last used (render time).
class _Mark {
  _Mark({required this.tripId, required this.shapeId, required this.progress, required this.at});

  final String? tripId;
  final String shapeId;
  final double progress;
  DateTime at;

  /// Render time at which the current hold of a big backward move began.
  DateTime? holdStart;
}

/// How a frame's newest fix breaks from the vehicle's earlier data: no break,
/// a short gap (glides), a long gap (snaps), or a re-created track (snaps).
enum _Discontinuity { none, shortGap, gap, recreated }

class _VehicleState {
  _Mark? mark;

  /// The last mark set on a shape. Unlike [mark] it is not cleared by an
  /// off-shape frame, so a glide that follows can start from it.
  _Mark? anchor;

  /// The delay currently applied, seconds; null before the first render.
  double? delaySeconds;

  /// Wall time of the previous render.
  DateTime? lastNow;

  /// GPS time of the newest fix the last frame saw.
  DateTime? latestGps;

  /// Catching up after a short data gap: the limiter runs at
  /// DelayedTrackRenderer._gapCatchUpMps until the bus reaches its target.
  bool catchingUp = false;

  /// The bus last drawn, and the `now` it was drawn at.
  RenderedBus? drawn;
  DateTime? drawnAt;
}
