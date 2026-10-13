import 'package:flutter/widgets.dart';

import '../../domain/arrival/arrival_models.dart';
import '../../domain/arrival_alerts/arrival_alert.dart';
import '../kit/kit.dart';

/// "Alert me when route 10 is 3 / 5 / 10 min away" (spec §2.1). Returns the lead, or null.
Future<int?> showLeadTimeSheet(
  BuildContext context, {
  required ArrivalRow arrival,
  required int initialLead,
  required bool explainPermission,
}) {
  return showGeneralDialog<int>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: BBScrim.strongOf(context),
    transitionDuration: BBMotion.of(context, BBMotion.standard),
    pageBuilder: (_, _, _) =>
        _LeadTimeCard(arrival: arrival, initialLead: initialLead, explainPermission: explainPermission),
    transitionBuilder: (_, animation, _, child) =>
        FadeTransition(opacity: CurvedAnimation(parent: animation, curve: BBMotion.curve), child: child),
  );
}

class _LeadTimeCard extends StatefulWidget {
  const _LeadTimeCard({required this.arrival, required this.initialLead, required this.explainPermission});

  final ArrivalRow arrival;
  final int initialLead;
  final bool explainPermission;

  @override
  State<_LeadTimeCard> createState() => _LeadTimeCardState();
}

class _LeadTimeCardState extends State<_LeadTimeCard> {
  late final List<int> _allowed = leadChoicesFor(widget.arrival.minutesAway);
  late int _lead = _allowed.contains(widget.initialLead)
      ? widget.initialLead
      : _allowed.isEmpty
          ? alertLeadChoices.first
          : _allowed.last;

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    final nav = Navigator.of(context);
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(BBSpace.l),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            // A dialog surface like BBDialog: its chips are field pills, not floating map pills.
            child: BBSurfaceScope(
              child: DecoratedBox(
                decoration: bb.floating(radius: BBRadius.sheet),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(BBSpace.l),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Semantics(
                        header: true,
                        child: Text('Alert me when route ${widget.arrival.routeShortName} is', style: bb.text.headline),
                      ),
                      const SizedBox(height: BBSpace.m),
                      Wrap(
                        spacing: BBSpace.s,
                        runSpacing: BBSpace.s,
                        children: [
                          for (final m in alertLeadChoices)
                            Opacity(
                              opacity: _allowed.contains(m) ? 1 : 0.4,
                              child: BBChip(
                                label: '$m min',
                                selected: m == _lead,
                                semanticLabel: _allowed.contains(m) ? '$m minutes away' : '$m minutes, too late for this bus',
                                onTap: _allowed.contains(m) ? () => setState(() => _lead = m) : null,
                              ),
                            ),
                        ],
                      ),
                      if (widget.explainPermission) ...[
                        const SizedBox(height: BBSpace.m),
                        Text('BusBoard will ask to send notifications, so it can alert you.', style: bb.text.caption),
                      ],
                      const SizedBox(height: BBSpace.l),
                      BBButton(label: 'Set alert', expand: true, onPressed: _allowed.isEmpty ? null : () => nav.pop(_lead)),
                      const SizedBox(height: BBSpace.s),
                      BBButton(label: 'Cancel', kind: BBButtonKind.quiet, expand: true, onPressed: () => nav.pop()),
                    ],
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
