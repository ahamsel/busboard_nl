import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/providers.dart';
import '../copy/legal_copy.dart';
import '../kit/kit.dart';

enum _MapThemeChoice { matchApp, light, dark }

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _refreshing = false;

  Future<void> _refreshSchedule() async {
    setState(() => _refreshing = true);
    try {
      ref.read(settingsProvider.notifier).requestForceRefresh();
      ref.invalidate(gtfsRepositoryProvider);
      await ref.read(gtfsRepositoryProvider.future);
    } catch (_) {
      if (mounted) BBToast.show(context, "Couldn't refresh schedule data. Try again later.");
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final mapChoice = switch (settings.mapThemeMode) {
      BBThemeMode.light => _MapThemeChoice.light,
      BBThemeMode.dark => _MapThemeChoice.dark,
      _ => _MapThemeChoice.matchApp,
    };

    Widget section(String title, IconData icon, List<Widget> children) => BBCard(
          padding: const EdgeInsets.all(BBSpace.xl),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Icon(icon, size: 20, color: bb.colors.brandInk),
              const SizedBox(width: BBSpace.s),
              Expanded(child: Semantics(header: true, child: Text(title, style: bb.text.headline))),
            ]),
            const SizedBox(height: BBSpace.m),
            ...children,
          ]),
        );

    return BBScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BBTopBar(title: 'Settings', onBack: () => context.pop()),
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                  BBSpace.screen, 0, BBSpace.screen, MediaQuery.paddingOf(context).bottom + BBSpace.l),
              children: [
                section('Appearance', BBIcons.palette, [
                  Text('App theme', style: bb.text.label.copyWith(color: bb.colors.muted)),
                  const SizedBox(height: BBSpace.s),
                  BBSegmented<BBThemeMode>(
                    segments: const [
                      BBSegment(value: BBThemeMode.system, label: 'System'),
                      BBSegment(value: BBThemeMode.light, label: 'Light'),
                      BBSegment(value: BBThemeMode.dark, label: 'Dark'),
                    ],
                    selected: settings.themeMode,
                    onChanged: notifier.setThemeMode,
                  ),
                  const SizedBox(height: BBSpace.l),
                  Text('Map theme', style: bb.text.label.copyWith(color: bb.colors.muted)),
                  const SizedBox(height: BBSpace.s),
                  BBSegmented<_MapThemeChoice>(
                    segments: const [
                      BBSegment(value: _MapThemeChoice.matchApp, label: 'Match app'),
                      BBSegment(value: _MapThemeChoice.light, label: 'Light'),
                      BBSegment(value: _MapThemeChoice.dark, label: 'Dark'),
                    ],
                    selected: mapChoice,
                    onChanged: (choice) => notifier.setMapThemeMode(switch (choice) {
                      _MapThemeChoice.matchApp => null,
                      _MapThemeChoice.light => BBThemeMode.light,
                      _MapThemeChoice.dark => BBThemeMode.dark,
                    }),
                  ),
                ]),
                const SizedBox(height: BBSpace.l),
                section('Refresh interval', BBIcons.timer, [
                  Text('How often to check for new live coordinates', style: bb.text.caption),
                  const SizedBox(height: BBSpace.m),
                  BBStepper(
                    value: settings.refreshIntervalSeconds.clamp(5, 60),
                    min: 5,
                    max: 60,
                    step: 5,
                    format: (v) => '$v seconds',
                    semanticLabel: 'Refresh interval',
                    onChanged: notifier.setRefreshInterval,
                  ),
                  const SizedBox(height: BBSpace.s),
                  Text(
                    'Metrobus currently refreshes GPS snapshots about every 10 seconds. '
                    'The map animates smoothly between them.',
                    textAlign: TextAlign.center,
                    style: bb.text.caption,
                  ),
                ]),
                const SizedBox(height: BBSpace.l),
                section('Schedule data (GTFS)', BBIcons.download, [
                  Text.rich(TextSpan(children: [
                    TextSpan(text: 'Last updated: ', style: bb.text.caption),
                    TextSpan(
                      text: settings.lastGtfsUpdate != null
                          ? BBTime.dated(settings.lastGtfsUpdate!, use24h: BBTime.use24h(context), year: true)
                          : 'Never',
                      style: bb.text.label,
                    ),
                  ])),
                  const SizedBox(height: BBSpace.xs),
                  Text('Auto-refreshes every 7 days', style: bb.text.caption),
                  const SizedBox(height: BBSpace.m),
                  BBButton(
                    label: _refreshing ? 'Downloading...' : 'Refresh schedule now',
                    icon: BBIcons.refresh,
                    kind: BBButtonKind.quiet,
                    expand: true,
                    onPressed: _refreshing ? null : _refreshSchedule,
                  ),
                ]),
                const SizedBox(height: BBSpace.l),
                section('About', BBIcons.info, [
                  Text('BusBoard NL v1.1.0', style: bb.text.label),
                  const SizedBox(height: BBSpace.xs),
                  Text(
                    'Personalized arrival board for Metrobus\n'
                    "St. John's, Mount Pearl & Paradise, NL",
                    style: bb.text.caption,
                  ),
                  const SizedBox(height: BBSpace.m),
                  Text(LegalCopy.independence, style: bb.text.label),
                  const SizedBox(height: BBSpace.s),
                  Text(LegalCopy.dataCredit, style: bb.text.caption),
                  const SizedBox(height: 2),
                  Text(LegalCopy.mapCredit, style: bb.text.caption),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
