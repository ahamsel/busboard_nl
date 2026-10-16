import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'kit_test_helpers.dart';

/// The page as the app builds it, with the app's real fonts: Search has a back button and a field under the title
/// (`below`); Alerts has a large title that wraps to two lines at 2x text, and an action.
Widget _page({required bool search, required double textScale}) => kitHost(
      SizedBox(
        height: 800,
        child: BBScrollPage(
          title: search ? 'Where to?' : 'Service alerts',
          large: !search,
          onBack: () {},
          actions: search
              ? const []
              : [BBIconButton(icon: BBIcons.settings, semanticLabel: 'Settings', onPressed: () {})],
          below: search
              ? const Padding(
                  padding: EdgeInsets.fromLTRB(BBSpace.l, 0, BBSpace.l, BBSpace.s),
                  child: BBTextField(hint: 'Search for a stop or a place', leadingIcon: BBIcons.search),
                )
              : null,
          body: (context, topInset) => ListView(
            padding: EdgeInsets.only(top: topInset),
            children: [for (var i = 0; i < 40; i++) SizedBox(height: 44, child: Text('row $i'))],
          ),
        ),
      ),
      textScale: textScale,
    );

void main() {
  setUpAll(loadAppFonts);

  for (final search in [true, false]) {
    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets('${search ? 'Search' : 'Alerts'} at ${scale}x: the first frame already puts the first row where '
          'the settled page does, and below the bar', (tester) async {
        await tester.pumpWidget(_page(search: search, textScale: scale));
        // No settle: the very first frame.
        final first = tester.getTopLeft(find.text('row 0')).dy;
        final barBottom = tester.getBottomLeft(find.byKey(BBScrollPage.barKey)).dy;
        expect(first, closeTo(barBottom, 0.01), reason: 'row 0 starts right under the bar in frame one');
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(find.text('row 0')).dy, closeTo(first, 0.01), reason: 'and it never moves after');
        expect(tester.getBottomLeft(find.byKey(BBScrollPage.barKey)).dy, closeTo(barBottom, 0.01));
        expect(tester.takeException(), isNull);
      });
    }
  }
}
