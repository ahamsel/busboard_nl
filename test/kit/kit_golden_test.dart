import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'kit_test_helpers.dart';

class _Gallery extends StatelessWidget {
  const _Gallery();

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    Widget row(int route, String dest, String status, String mins, {bool soon = false}) => BBCard(
      child: Row(
        children: [
          RouteBadge(routeNumber: route),
          const SizedBox(width: BBSpace.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(dest, style: bb.text.headline, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(status, style: bb.text.caption),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(mins, style: bb.text.minutes.copyWith(color: soon ? bb.colors.soon : null)),
              Text('min', style: bb.text.minutesUnit),
            ],
          ),
        ],
      ),
    );
    // The gallery paints its own page colour so the golden shows the real
    // background (otherwise the capture is transparent).
    return ColoredBox(
      color: bb.colors.bg,
      child: Padding(
        padding: const EdgeInsets.all(BBSpace.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('MUN Centre', style: bb.text.display),
            const SizedBox(height: BBSpace.s),
            const Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                BBPill(label: 'Live', tone: BBPillTone.live, leadingDot: true),
                BBPill(label: 'Detour', tone: BBPillTone.warn),
                BBPill(label: 'No service', tone: BBPillTone.danger),
                BBPill(label: 'Stop 1150', tone: BBPillTone.brand),
                RouteBadge(routeNumber: 10, size: RouteBadgeSize.compact),
                RouteBadge(routeNumber: 14, size: RouteBadgeSize.compact),
              ],
            ),
            const SizedBox(height: BBSpace.s),
            row(29, 'Signal Hill Rd', 'Live · Bus 2134', '4', soon: true),
            const SizedBox(height: BBSpace.s),
            row(23, 'Stavanger Drive', 'Scheduled', '6'),
            const SizedBox(height: BBSpace.s),
            const BBSkeleton(kind: BBSkeletonKind.arrivalRow, count: 1),
            const SizedBox(height: BBSpace.m),
            BBSegmented<int>(
              segments: const [
                BBSegment(value: 0, label: 'Near me'),
                BBSegment(value: 1, label: 'Stop number'),
              ],
              selected: 0,
              onChanged: (_) {},
            ),
            const SizedBox(height: BBSpace.m),
            const BBTextField(hint: 'Stop name or number on the pole', leadingIcon: BBIcons.search),
            const SizedBox(height: BBSpace.m),
            Row(
              children: [
                for (final kind in BBGlyphKind.values) ...[
                  BBGlyph(kind, color: bb.colors.ink),
                  const SizedBox(width: BBSpace.m),
                ],
                BBGlyph(BBGlyphKind.liveDot, color: bb.colors.live),
              ],
            ),
            const SizedBox(height: BBSpace.m),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                BBButton(label: 'Use this stop', onPressed: () {}),
                BBButton(label: 'Cancel', kind: BBButtonKind.quiet, onPressed: () {}),
                BBSwitch(value: true, onChanged: (_) {}),
                BBSwitch(value: false, onChanged: (_) {}),
              ],
            ),
            const SizedBox(height: BBSpace.m),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      BBChip(label: 'MUN Centre · 1150', icon: BBIcons.star, chevron: true, onTap: () {}),
                      BBChip(label: 'All routes', chevron: true, onTap: () {}),
                      BBChip(label: 'Route 10', selected: true, onTap: () {}),
                    ],
                  ),
                ),
                const SizedBox(width: BBSpace.m),
                BBControlPill(items: [
                  BBControlPillItem(icon: BBIcons.location, semanticLabel: 'My location', onPressed: () {}),
                ]),
              ],
            ),
            const SizedBox(height: BBSpace.m),
            BBNavBar(
              items: const [
                BBNavItem(label: 'Board', icon: BBIcons.board),
                BBNavItem(label: 'Map', icon: BBIcons.map),
                BBNavItem(label: 'Alerts', icon: BBIcons.alerts, badgeCount: 2),
              ],
              currentIndex: 0,
              onSelect: (_) {},
            ),
          ],
        ),
      ),
    );
  }
}

void main() {
  setUpAll(loadAppFonts);

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('kit gallery ${brightness.name} x$scale', (tester) async {
        tester.view.physicalSize = Size(390 * 3, (scale == 1.0 ? 1100 : 1800) * 3);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          kitHost(
            const SingleChildScrollView(child: _Gallery()),
            brightness: brightness,
            textScale: scale,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(tester.getSize(find.byType(_Gallery)).height, lessThanOrEqualTo(scale == 1.0 ? 1100 : 1800));
        await expectLater(
          find.byType(_Gallery),
          matchesGoldenFile(
            'goldens/kit_gallery_${brightness.name}_x${scale.toStringAsFixed(0)}.png',
          ),
        );
      });
    }
  }
}
