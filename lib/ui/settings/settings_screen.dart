import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../state/providers.dart';

/// Settings screen for changing refresh interval and forcing GTFS re-download.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _refreshing = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        bottom: true,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Appearance
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.palette_outlined,
                          color: theme.colorScheme.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Text('Appearance', style: theme.textTheme.titleMedium),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SegmentedButton<ThemeMode>(
                      segments: const [
                        ButtonSegment(
                          value: ThemeMode.system,
                          label: Text('System'),
                          icon: Icon(Icons.brightness_auto),
                        ),
                        ButtonSegment(
                          value: ThemeMode.light,
                          label: Text('Light'),
                          icon: Icon(Icons.wb_sunny),
                        ),
                        ButtonSegment(
                          value: ThemeMode.dark,
                          label: Text('Dark'),
                          icon: Icon(Icons.nightlight_round),
                        ),
                      ],
                      selected: {settings.themeMode},
                      onSelectionChanged: (Set<ThemeMode> newSelection) {
                        ref
                            .read(settingsProvider.notifier)
                            .setThemeMode(newSelection.first);
                      },
                      style: ButtonStyle(
                        padding: WidgetStateProperty.all(
                          const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Refresh interval
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.timer_outlined,
                          color: theme.colorScheme.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Refresh Interval',
                          style: theme.textTheme.titleMedium,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'How often to refresh live data',
                      style: TextStyle(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.4,
                        ),
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Text(
                          '5s',
                          style: TextStyle(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.4,
                            ),
                            fontSize: 12,
                          ),
                        ),
                        Expanded(
                          child: Slider(
                            value: settings.refreshIntervalSeconds
                                .toDouble()
                                .clamp(5, 60),
                            min: 5,
                            max: 60,
                            divisions: 11,
                            label: '${settings.refreshIntervalSeconds}s',
                            onChanged: (val) {
                              ref
                                  .read(settingsProvider.notifier)
                                  .setRefreshInterval(val.round());
                            },
                          ),
                        ),
                        Text(
                          '60s',
                          style: TextStyle(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.4,
                            ),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    Center(
                      child: Text(
                        '${settings.refreshIntervalSeconds} seconds',
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Enhanced Predictions
            /* // TEMPORARILY DISABLED SCRAPING
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.rocket_launch_outlined,
                        color: theme.brightness == Brightness.light
                            ? const Color(0xFF7B1FA2)
                            : const Color(0xFFCE93D8),
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Enhanced Predictions',
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      Switch(
                        value: settings.useEnhancedPredictions,
                        onChanged: (val) {
                          ref
                              .read(settingsProvider.notifier)
                              .setUseEnhancedPredictions(val);
                        },
                        activeTrackColor:
                            (theme.brightness == Brightness.light
                                    ? const Color(0xFF7B1FA2)
                                    : const Color(0xFFCE93D8))
                                .withValues(alpha: 0.4),
                        activeThumbColor: theme.brightness == Brightness.light
                            ? const Color(0xFF7B1FA2)
                            : const Color(0xFFCE93D8),
                      ),
                    ],
                  ),
                  // const SizedBox(height: 4),
                  // Text(
                  //   'Use Metrobus Mobile for better departure predictions',
                  //   style: TextStyle(
                  //     color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  //     fontSize: 13,
                  //   ),
                  // ),
                  // const SizedBox(height: 8),
                  // Text(
                  //   'Scrapes metrobusmobile.com for agency-predicted times. '
                  //   'Only active for the selected stop.',
                  //   style: TextStyle(
                  //     color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
                  //     fontSize: 11,
                  //   ),
                  // ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          */

            // Schedule data
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.cloud_download_outlined,
                          color: theme.colorScheme.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Schedule Data (GTFS)',
                          style: theme.textTheme.titleMedium,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Text(
                          'Last updated:',
                          style: TextStyle(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.4,
                            ),
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          settings.lastGtfsUpdate != null
                              ? DateFormat(
                                  'MMM d, yyyy HH:mm',
                                ).format(settings.lastGtfsUpdate!)
                              : 'Never',
                          style: const TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Auto-refreshes every 7 days',
                      style: TextStyle(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.3,
                        ),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _refreshing
                            ? null
                            : () async {
                                setState(() => _refreshing = true);
                                ref
                                    .read(settingsProvider.notifier)
                                    .requestForceRefresh();
                                ref.invalidate(gtfsRepositoryProvider);
                                // Wait for the provider to complete
                                await ref.read(gtfsRepositoryProvider.future);
                                if (mounted) {
                                  setState(() => _refreshing = false);
                                }
                              },
                        icon: _refreshing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.refresh, size: 18),
                        label: Text(
                          _refreshing
                              ? 'Downloading...'
                              : 'Refresh Schedule Now',
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: theme.colorScheme.primary,
                          side: BorderSide(
                            color: theme.colorScheme.primary.withValues(
                              alpha: 0.3,
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // About
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: theme.colorScheme.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Text('About', style: theme.textTheme.titleMedium),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'BusBoard NL v1.0.0',
                      style: TextStyle(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.7,
                        ),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Personalized arrival board for Metrobus\n'
                      'St. John\'s, Mount Pearl & Paradise, NL',
                      style: TextStyle(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.4,
                        ),
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Data: GTFS schedule + TimeTrack live tracking',
                      style: TextStyle(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.3,
                        ),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
