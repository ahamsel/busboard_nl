import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/map_providers.dart';
import '../kit/kit.dart';

/// Floating card of route badges under the route chip (spec §3.3): tap badges
/// to choose which routes the map shows; "Show all" clears the choice. A chosen
/// badge is full colour; with a choice made, the others fade.
Future<void> showRouteFilterCard(BuildContext context, {required List<int> routes}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close route filter',
    barrierColor: BBScrim.soft,
    transitionDuration: BBMotion.of(context, BBMotion.standard),
    pageBuilder: (_, _, _) => _RouteFilterCard(routes: routes),
    transitionBuilder: (_, animation, _, child) =>
        FadeTransition(opacity: CurvedAnimation(parent: animation, curve: BBMotion.curve), child: child),
  );
}

class _RouteFilterCard extends ConsumerWidget {
  const _RouteFilterCard({required this.routes});

  final List<int> routes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bb = context.bb;
    final filter = ref.watch(mapRouteFilterProvider);
    final notifier = ref.read(mapRouteFilterProvider.notifier);
    return SafeArea(
      child: Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(BBSpace.l, 56, BBSpace.s, BBSpace.l),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: DecoratedBox(
              decoration: bb.floating(radius: BBRadius.sheet),
              child: Padding(
                padding: const EdgeInsets.all(BBSpace.l),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Show routes', style: bb.text.headline),
                    const SizedBox(height: BBSpace.m),
                    if (routes.isEmpty)
                      Text('No buses are reporting right now', style: bb.text.caption)
                    else
                      Wrap(
                        spacing: BBSpace.s,
                        runSpacing: BBSpace.s,
                        children: [
                          for (final r in routes)
                            Semantics(
                              selected: filter.contains(r) ? true : null,
                              child: BBPressable(
                                onTap: () => notifier.toggle(r),
                                semanticLabel: filter.contains(r) ? 'Route $r, shown' : 'Route $r',
                                child: Opacity(
                                  opacity: filter.isEmpty || filter.contains(r) ? 1 : 0.4,
                                  child: RouteBadge(routeNumber: r),
                                ),
                              ),
                            ),
                        ],
                      ),
                    const SizedBox(height: BBSpace.m),
                    BBButton(
                      label: 'Show all',
                      kind: BBButtonKind.quiet,
                      onPressed: filter.isEmpty ? null : notifier.showAll,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
