import 'dart:convert';

import 'package:gtfs_realtime_bindings/gtfs_realtime_bindings.dart';
import 'package:http/http.dart' as http;

import 'service_alert_models.dart';

class ServiceAlertsApi {
  static const alertsUrl = 'https://www.mbusapi.ca/gtfsrt/servicealerts';
  static const statusUrl =
      'https://www.metrobusmobile.com/fleetview.asp?type=status';

  final http.Client _client;

  ServiceAlertsApi({http.Client? client}) : _client = client ?? http.Client();

  Future<ServiceUpdates> fetchUpdates({DateTime? now}) async {
    final fetchedAt = now ?? DateTime.now();
    final responses = await Future.wait([
      _client.get(Uri.parse(alertsUrl)).timeout(const Duration(seconds: 10)),
      _tryFetchStatus(),
    ]);
    final alertResponse = responses[0] as http.Response;
    if (alertResponse.statusCode != 200) {
      throw ServiceAlertsException(
        'Metrobus service alerts returned HTTP '
        '${alertResponse.statusCode}',
      );
    }

    final feed = _decodeFeed(alertResponse.bodyBytes);
    final alerts =
        _parseAlerts(
            feed,
          ).where((alert) => !alert.hasEndedBefore(fetchedAt)).toList()
          ..sort((a, b) => b.priority.compareTo(a.priority));

    return ServiceUpdates(
      alerts: alerts,
      serviceStatus: _parseStatus(responses[1]),
      fetchedAt: fetchedAt,
      feedTimestamp: feed.header.hasTimestamp()
          ? DateTime.fromMillisecondsSinceEpoch(
              feed.header.timestamp.toInt() * 1000,
              isUtc: true,
            ).toLocal()
          : null,
    );
  }

  FeedMessage _decodeFeed(List<int> bytes) {
    try {
      final feed = FeedMessage.fromBuffer(bytes);
      if (!feed.hasHeader() || feed.header.gtfsRealtimeVersion.isEmpty) {
        throw const FormatException('missing GTFS-Realtime header');
      }
      return feed;
    } catch (error) {
      throw ServiceAlertsException(
        'Metrobus returned an invalid service-alert feed: $error',
      );
    }
  }

  List<ServiceAlert> _parseAlerts(FeedMessage feed) {
    final grouped = <String, ServiceAlert>{};

    for (final entity in feed.entity) {
      if (!entity.hasAlert() || (entity.hasIsDeleted() && entity.isDeleted)) {
        continue;
      }
      final proto = entity.alert;
      final alert = ServiceAlert(
        sourceIds: {entity.id},
        header: _translatedText(
          proto.hasHeaderText() ? proto.headerText : null,
        ),
        description: _translatedText(
          proto.hasDescriptionText() ? proto.descriptionText : null,
        ),
        url: _nullableText(_translatedText(proto.hasUrl() ? proto.url : null)),
        cause: _cause(proto.hasCause() ? proto.cause.name : ''),
        effect: _effect(proto.hasEffect() ? proto.effect.name : ''),
        severity: _severity(
          proto.hasSeverityLevel() ? proto.severityLevel.name : '',
        ),
        activePeriods: [
          for (final period in proto.activePeriod)
            ServiceAlertPeriod(
              start: period.hasStart()
                  ? DateTime.fromMillisecondsSinceEpoch(
                      period.start.toInt() * 1000,
                      isUtc: true,
                    ).toLocal()
                  : null,
              end: period.hasEnd()
                  ? DateTime.fromMillisecondsSinceEpoch(
                      period.end.toInt() * 1000,
                      isUtc: true,
                    ).toLocal()
                  : null,
            ),
        ],
        targets: [
          for (final target in proto.informedEntity)
            ServiceAlertTarget(
              agencyId: _nullableText(target.agencyId),
              routeId: _nullableText(
                target.routeId.isNotEmpty
                    ? target.routeId
                    : target.hasTrip()
                    ? target.trip.routeId
                    : '',
              ),
              stopId: _nullableText(target.stopId),
              tripId: target.hasTrip()
                  ? _nullableText(target.trip.tripId)
                  : null,
              directionId: target.hasDirectionId() ? target.directionId : null,
            ),
        ],
      );

      if (alert.header.isEmpty && alert.description.isEmpty) continue;
      final key = _dedupeKey(alert);
      grouped[key] = grouped[key]?.merge(alert) ?? alert;
    }

    return grouped.values.toList();
  }

  String _dedupeKey(ServiceAlert alert) {
    final periods = alert.activePeriods
        .map(
          (period) =>
              '${period.start?.millisecondsSinceEpoch ?? ''}-'
              '${period.end?.millisecondsSinceEpoch ?? ''}',
        )
        .join(',');
    return '${alert.header.trim().toLowerCase()}|'
        '${alert.description.trim().toLowerCase()}|'
        '${alert.effect.name}|$periods';
  }

  String _translatedText(TranslatedString? value) {
    if (value == null || value.translation.isEmpty) return '';
    final english = value.translation.where(
      (translation) => translation.language.toLowerCase().startsWith('en'),
    );
    if (english.isNotEmpty) return english.first.text.trim();
    final unspecified = value.translation.where(
      (translation) => translation.language.trim().isEmpty,
    );
    if (unspecified.isNotEmpty) return unspecified.first.text.trim();
    return value.translation.first.text.trim();
  }

  Future<http.Response?> _tryFetchStatus() async {
    try {
      final response = await _client
          .get(Uri.parse(statusUrl))
          .timeout(const Duration(seconds: 10));
      return response.statusCode == 200 ? response : null;
    } catch (_) {
      return null;
    }
  }

  MetrobusServiceStatus? _parseStatus(http.Response? response) {
    if (response == null) return null;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return null;
      final json = Map<String, dynamic>.from(decoded);
      return MetrobusServiceStatus(
        serviceOperating: json['serviceOperating'] is bool
            ? json['serviceOperating'] as bool
            : null,
        serviceId: json['serviceId']?.toString().trim() ?? '',
        day: json['day']?.toString().trim() ?? '',
        message: json['message']?.toString().trim() ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  ServiceAlertCause _cause(String name) => switch (name) {
    'TECHNICAL_PROBLEM' => ServiceAlertCause.technicalProblem,
    'STRIKE' => ServiceAlertCause.strike,
    'DEMONSTRATION' => ServiceAlertCause.demonstration,
    'ACCIDENT' => ServiceAlertCause.accident,
    'HOLIDAY' => ServiceAlertCause.holiday,
    'WEATHER' => ServiceAlertCause.weather,
    'MAINTENANCE' => ServiceAlertCause.maintenance,
    'CONSTRUCTION' => ServiceAlertCause.construction,
    'POLICE_ACTIVITY' => ServiceAlertCause.policeActivity,
    'MEDICAL_EMERGENCY' => ServiceAlertCause.medicalEmergency,
    'OTHER_CAUSE' => ServiceAlertCause.other,
    _ => ServiceAlertCause.unknown,
  };

  ServiceAlertEffect _effect(String name) => switch (name) {
    'NO_SERVICE' => ServiceAlertEffect.noService,
    'REDUCED_SERVICE' => ServiceAlertEffect.reducedService,
    'SIGNIFICANT_DELAYS' => ServiceAlertEffect.significantDelays,
    'DETOUR' => ServiceAlertEffect.detour,
    'ADDITIONAL_SERVICE' => ServiceAlertEffect.additionalService,
    'MODIFIED_SERVICE' => ServiceAlertEffect.modifiedService,
    'STOP_MOVED' => ServiceAlertEffect.stopMoved,
    'ACCESSIBILITY_ISSUE' => ServiceAlertEffect.accessibilityIssue,
    'NO_EFFECT' => ServiceAlertEffect.noEffect,
    'OTHER_EFFECT' => ServiceAlertEffect.other,
    _ => ServiceAlertEffect.unknown,
  };

  ServiceAlertSeverity _severity(String name) => switch (name) {
    'SEVERE' => ServiceAlertSeverity.severe,
    'WARNING' => ServiceAlertSeverity.warning,
    'INFO' => ServiceAlertSeverity.info,
    _ => ServiceAlertSeverity.unknown,
  };

  String? _nullableText(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  void dispose() => _client.close();
}

class ServiceAlertsException implements Exception {
  final String message;

  const ServiceAlertsException(this.message);

  @override
  String toString() => message;
}
