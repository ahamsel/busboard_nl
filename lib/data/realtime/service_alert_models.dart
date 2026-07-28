enum ServiceAlertEffect {
  noService,
  reducedService,
  significantDelays,
  detour,
  additionalService,
  modifiedService,
  stopMoved,
  accessibilityIssue,
  noEffect,
  other,
  unknown;

  String get label => switch (this) {
    ServiceAlertEffect.noService => 'No service',
    ServiceAlertEffect.reducedService => 'Reduced service',
    ServiceAlertEffect.significantDelays => 'Significant delays',
    ServiceAlertEffect.detour => 'Detour',
    ServiceAlertEffect.additionalService => 'Additional service',
    ServiceAlertEffect.modifiedService => 'Modified service',
    ServiceAlertEffect.stopMoved => 'Stop moved',
    ServiceAlertEffect.accessibilityIssue => 'Accessibility issue',
    ServiceAlertEffect.noEffect => 'Information',
    ServiceAlertEffect.other => 'Service update',
    ServiceAlertEffect.unknown => 'Service alert',
  };
}

enum ServiceAlertCause {
  technicalProblem,
  strike,
  demonstration,
  accident,
  holiday,
  weather,
  maintenance,
  construction,
  policeActivity,
  medicalEmergency,
  other,
  unknown;

  String get label => switch (this) {
    ServiceAlertCause.technicalProblem => 'Technical problem',
    ServiceAlertCause.strike => 'Strike',
    ServiceAlertCause.demonstration => 'Demonstration',
    ServiceAlertCause.accident => 'Accident',
    ServiceAlertCause.holiday => 'Holiday',
    ServiceAlertCause.weather => 'Weather',
    ServiceAlertCause.maintenance => 'Maintenance',
    ServiceAlertCause.construction => 'Construction',
    ServiceAlertCause.policeActivity => 'Police activity',
    ServiceAlertCause.medicalEmergency => 'Medical emergency',
    ServiceAlertCause.other => 'Other',
    ServiceAlertCause.unknown => 'Unknown',
  };
}

enum ServiceAlertSeverity { severe, warning, info, unknown }

class ServiceAlertPeriod {
  final DateTime? start;
  final DateTime? end;

  const ServiceAlertPeriod({this.start, this.end});

  bool contains(DateTime time) {
    if (start != null && time.isBefore(start!)) return false;
    if (end != null && !time.isBefore(end!)) return false;
    return true;
  }

  bool hasEndedBefore(DateTime time) => end != null && !time.isBefore(end!);
}

/// One GTFS-Realtime EntitySelector. Fields in a single selector have AND
/// semantics; separate selectors have OR semantics.
class ServiceAlertTarget {
  final String? agencyId;
  final String? routeId;
  final String? stopId;
  final String? tripId;
  final int? directionId;

  const ServiceAlertTarget({
    this.agencyId,
    this.routeId,
    this.stopId,
    this.tripId,
    this.directionId,
  });

  bool matches({
    required Set<String> routeIds,
    String? stopId,
    Set<String> tripIds = const {},
  }) {
    if (routeId != null && !routeIds.contains(routeId)) return false;
    if (this.stopId != null && this.stopId != stopId) return false;
    if (tripId != null && !tripIds.contains(tripId)) return false;

    // Agency-only selectors apply system-wide. A selector with no supported
    // restriction is also treated as system-wide rather than hidden.
    return true;
  }

  String get mergeKey =>
      '${agencyId ?? ''}|${routeId ?? ''}|${stopId ?? ''}|'
      '${tripId ?? ''}|${directionId ?? ''}';
}

class ServiceAlert {
  final Set<String> sourceIds;
  final String header;
  final String description;
  final String? url;
  final ServiceAlertCause cause;
  final ServiceAlertEffect effect;
  final ServiceAlertSeverity severity;
  final List<ServiceAlertPeriod> activePeriods;
  final List<ServiceAlertTarget> targets;

  const ServiceAlert({
    required this.sourceIds,
    required this.header,
    required this.description,
    this.url,
    required this.cause,
    required this.effect,
    required this.severity,
    required this.activePeriods,
    required this.targets,
  });

  Set<String> get routeIds => {
    for (final target in targets)
      if (target.routeId != null) target.routeId!,
  };

  Set<String> get stopIds => {
    for (final target in targets)
      if (target.stopId != null) target.stopId!,
  };

  bool isActiveAt(DateTime time) =>
      activePeriods.isEmpty ||
      activePeriods.any((period) => period.contains(time));

  bool hasEndedBefore(DateTime time) =>
      activePeriods.isNotEmpty &&
      activePeriods.every((period) => period.hasEndedBefore(time));

  bool appliesTo({
    required Set<String> routeIds,
    String? stopId,
    Set<String> tripIds = const {},
  }) {
    if (targets.isEmpty) return true;
    return targets.any(
      (target) =>
          target.matches(routeIds: routeIds, stopId: stopId, tripIds: tripIds),
    );
  }

  int get priority => switch (severity) {
    ServiceAlertSeverity.severe => 100,
    ServiceAlertSeverity.warning => 80,
    ServiceAlertSeverity.info => 40,
    ServiceAlertSeverity.unknown => switch (effect) {
      ServiceAlertEffect.noService => 90,
      ServiceAlertEffect.reducedService => 75,
      ServiceAlertEffect.significantDelays => 70,
      ServiceAlertEffect.detour => 65,
      ServiceAlertEffect.stopMoved => 60,
      ServiceAlertEffect.accessibilityIssue => 55,
      _ => 30,
    },
  };

  ServiceAlert merge(ServiceAlert other) {
    final mergedTargets = <String, ServiceAlertTarget>{
      for (final target in [...targets, ...other.targets])
        target.mergeKey: target,
    };
    return ServiceAlert(
      sourceIds: {...sourceIds, ...other.sourceIds},
      header: header,
      description: description,
      url: url ?? other.url,
      cause: cause != ServiceAlertCause.unknown ? cause : other.cause,
      effect: effect != ServiceAlertEffect.unknown ? effect : other.effect,
      severity: severity != ServiceAlertSeverity.unknown
          ? severity
          : other.severity,
      activePeriods: activePeriods,
      targets: mergedTargets.values.toList(),
    );
  }
}

class MetrobusServiceStatus {
  final bool? serviceOperating;
  final String serviceId;
  final String day;
  final String message;

  const MetrobusServiceStatus({
    required this.serviceOperating,
    required this.serviceId,
    required this.day,
    required this.message,
  });
}

class ServiceUpdates {
  final List<ServiceAlert> alerts;
  final MetrobusServiceStatus? serviceStatus;
  final DateTime fetchedAt;
  final DateTime? feedTimestamp;

  const ServiceUpdates({
    required this.alerts,
    required this.serviceStatus,
    required this.fetchedAt,
    required this.feedTimestamp,
  });

  List<ServiceAlert> activeAlertsAt(DateTime time) =>
      alerts.where((alert) => alert.isActiveAt(time)).toList();
}
