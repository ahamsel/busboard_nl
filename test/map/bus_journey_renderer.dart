// ignore_for_file: avoid_print

import 'package:busboard_nl/domain/map/bus_journey_anomaly.dart';
import 'package:busboard_nl/domain/map/bus_journey_tracer.dart';

/// Terminal visualization for bus journey traces.
class BusJourneyRenderer {
  /// Print a full report for all traced buses.
  ///
  /// If [onlyAnomalous] is true (default), only buses with anomalies are shown.
  /// If [verbose] is true, all frames are listed in the event timeline.
  static void printReport(
    BusJourneyTracer tracer, {
    int? maxBuses,
    bool onlyAnomalous = true,
    bool verbose = false,
  }) {
    var keys = tracer.trackedKeys.toList()
      ..sort((a, b) =>
          tracer.anomaliesFor(b).length.compareTo(tracer.anomaliesFor(a).length));

    if (onlyAnomalous) {
      keys = keys.where((k) => tracer.anomaliesFor(k).isNotEmpty).toList();
    }
    if (maxBuses != null && keys.length > maxBuses) {
      keys = keys.sublist(0, maxBuses);
    }

    if (keys.isEmpty) {
      print('[Tracer] No anomalies detected across ${tracer.trackedKeys.length} buses.');
      _printGlobalSummary(tracer);
      return;
    }

    print('[Tracer] Report for ${keys.length} bus(es) '
        '(${tracer.trackedKeys.length} total tracked):');
    print('');

    for (final key in keys) {
      _printBusReport(tracer, key, verbose: verbose);
      print('');
    }

    _printGlobalSummary(tracer);
  }

  static void _printGlobalSummary(BusJourneyTracer tracer) {
    final allAnomalies = tracer.allAnomalies;
    final byType = <AnomalyType, int>{};
    for (final a in allAnomalies) {
      byType[a.type] = (byType[a.type] ?? 0) + 1;
    }

    final parts = <String>[];
    for (final type in AnomalyType.values) {
      final count = byType[type] ?? 0;
      if (count > 0) parts.add('${type.name}=$count');
    }

    print('[Tracer] Global: ${tracer.trackedKeys.length} buses, '
        '${allAnomalies.length} anomalies${parts.isEmpty ? '' : ' (${parts.join(', ')})'}');
  }

  static void _printBusReport(
    BusJourneyTracer tracer,
    String key, {
    bool verbose = false,
  }) {
    final frames = tracer.framesFor(key);
    final anomalies = tracer.anomaliesFor(key);
    final summary = tracer.summaryFor(key);

    if (frames.isEmpty) return;

    final firstFrame = frames.first;
    final routeLen = summary.routeLengthM ?? 0.0;

    // Header.
    print('  ┌─ Bus "$key" '
        '(route ${firstFrame.vehicleId ?? "?"}, trip ${firstFrame.tripId ?? "?"}) '
        '| ${routeLen.toStringAsFixed(0)}m | '
        '${summary.durationSeconds.toStringAsFixed(1)}s');

    // Progress bar.
    print('  │ ${_renderProgressBar(frames, routeLen, anomalies)}');

    // Event timeline.
    _printEventTimeline(frames, anomalies, verbose: verbose);

    // Speed sparkline.
    print('  │');
    print('  │ Speed: ${_renderSpeedSparkline(frames, summary.durationSeconds, (f) => f.displaySpeedKmh)}');
    if (frames.any((f) => f.truthSpeedKmh != null)) {
      print('  │ Truth: ${_renderSpeedSparkline(frames, summary.durationSeconds, (f) => f.truthSpeedKmh)}');
    }
    print('  │        _ <10  / 10-25  ^ 25-45  * >45 km/h');

    // Summary.
    print('  │');
    print('  │ Frames: ${summary.frameCount} | '
        'Anomalies: ${summary.anomalyCount} | '
        'Backsteps: ${summary.backstepCount} (${summary.backstepTotalMeters.toStringAsFixed(1)}m) | '
        'Blends: ${summary.blendCount}');

    final parts = <String>[];
    if (summary.speedFidelityP50 != null) {
      parts.add('speedFid p50=${summary.speedFidelityP50!.toStringAsFixed(2)}');
    }
    if (summary.speedFidelityP90 != null) {
      parts.add('p90=${summary.speedFidelityP90!.toStringAsFixed(2)}');
    }
    if (summary.positionErrorP90 != null) {
      parts.add('posErr p90=${summary.positionErrorP90!.toStringAsFixed(1)}m');
    }
    if (parts.isNotEmpty) {
      print('  │ ${parts.join(' | ')}');
    }

    print('  └─');
  }

  static String _renderProgressBar(
    List<FrameRecord> frames,
    double routeLengthM,
    List<Anomaly> anomalies,
  ) {
    const barWidth = 60;
    if (routeLengthM < 1.0 || frames.isEmpty) return '[no progress data]';

    final bar = List.filled(barWidth, ' ');

    // Build a set of anomaly timestamps for fast lookup.
    final anomalyTimes = <double>{};
    for (final a in anomalies) {
      anomalyTimes.add(a.elapsedSeconds);
    }

    for (final frame in frames) {
      final p = frame.renderedProgressM;
      if (p == null) continue;
      final idx = ((p / routeLengthM) * (barWidth - 1)).round().clamp(0, barWidth - 1);

      // Check if this frame is near an anomaly.
      final isAnomaly = anomalyTimes.any(
        (t) => (t - frame.elapsedSeconds).abs() < 0.5,
      );

      if (isAnomaly) {
        bar[idx] = '!';
      } else if (frame.blendActive) {
        if (bar[idx] != '!') bar[idx] = 'B';
      } else {
        if (bar[idx] != '!' && bar[idx] != 'B') bar[idx] = '>';
      }
    }

    final barStr = bar.join();
    return '[$barStr] ${routeLengthM.toStringAsFixed(0)}m';
  }

  static void _printEventTimeline(
    List<FrameRecord> frames,
    List<Anomaly> anomalies, {
    bool verbose = false,
  }) {
    print('  │');

    // Collect all notable events.
    final entries = <(double, String)>[];

    for (final frame in frames) {
      for (final event in frame.events) {
        final prefix = switch (event.type) {
          TraceEventType.pollReceived => 'POLL   ',
          TraceEventType.blendStarted => 'BLEND+ ',
          TraceEventType.blendEnded => 'BLEND- ',
          TraceEventType.tripChanged => 'TRIP   ',
          TraceEventType.vehicleSwapped => 'SWAP   ',
          TraceEventType.statusChanged => 'STATUS ',
          TraceEventType.backstepOccurred => '!! BACK',
          TraceEventType.backstepClamped => 'CLAMP  ',
        };

        // In non-verbose mode, skip poll events.
        if (!verbose && event.type == TraceEventType.pollReceived) continue;

        entries.add((frame.elapsedSeconds, '$prefix ${event.description}'));
      }
    }

    // Add anomalies.
    for (final a in anomalies) {
      if (a.type == AnomalyType.backwardJump) continue; // Already shown via events.
      entries.add((a.elapsedSeconds, a.toString()));
    }

    entries.sort((a, b) => a.$1.compareTo(b.$1));

    // Cap output.
    final maxEntries = verbose ? 500 : 50;
    final toShow = entries.length > maxEntries
        ? entries.sublist(0, maxEntries)
        : entries;

    for (final (t, desc) in toShow) {
      print('  │ t=${t.toStringAsFixed(1).padLeft(7)}s  $desc');
    }

    if (entries.length > maxEntries) {
      print('  │ ... and ${entries.length - maxEntries} more events');
    }
  }

  static String _renderSpeedSparkline(
    List<FrameRecord> frames,
    double totalSeconds,
    double? Function(FrameRecord) speedExtractor,
  ) {
    const width = 50;
    if (totalSeconds < 0.1 || frames.isEmpty) return '';

    final chars = List.filled(width, ' ');

    for (final frame in frames) {
      final speed = speedExtractor(frame);
      if (speed == null) continue;
      final idx = ((frame.elapsedSeconds / totalSeconds) * (width - 1))
          .round()
          .clamp(0, width - 1);

      final c = switch (speed) {
        < 10.0 => '_',
        < 25.0 => '/',
        < 45.0 => '^',
        _ => '*',
      };

      // Prefer higher speed chars.
      const priority = ' _/^*';
      if (priority.indexOf(c) > priority.indexOf(chars[idx])) {
        chars[idx] = c;
      }
    }

    return chars.join();
  }
}
