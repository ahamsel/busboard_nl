import 'package:busboard_nl/ui/orientation_lock.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('phones run upright, tablets turn freely', () {
    for (final (name, size) in [
      ('iPhone 17, portrait', const Size(402, 874)),
      ('iPhone 17, held sideways', const Size(874, 402)),
      ('small Android phone', const Size(360, 640)),
      ('folded foldable', const Size(380, 860)),
      ('just under the tablet line', const Size(599, 900)),
    ]) {
      test('$name: portrait only', () {
        expect(OrientationLock.orientationsFor(size), [DeviceOrientation.portraitUp]);
      });
    }
    for (final (name, size) in [
      ('iPad Pro 13', const Size(1032, 1376)),
      ('iPad held sideways', const Size(1376, 1032)),
      ('7" Android tablet', const Size(600, 960)),
      ('unfolded foldable', const Size(840, 900)),
    ]) {
      test('$name: every orientation', () {
        expect(OrientationLock.orientationsFor(size), isEmpty, reason: 'an empty list lets the system turn freely');
      });
    }
  });

  test('sets the orientations at launch, and again only when the screen kind changes', () {
    var size = const Size(402, 874);
    final calls = <List<DeviceOrientation>>[];
    final lock = OrientationLock(viewSize: () => size, setOrientations: (o) async => calls.add(o));

    lock.apply();
    expect(calls, [
      [DeviceOrientation.portraitUp],
    ]);

    size = const Size(874, 402); // a phone turned: still a phone
    lock.apply();
    expect(calls, hasLength(1));

    size = const Size(840, 900); // a foldable opened
    lock.apply();
    expect(calls.last, isEmpty);

    size = Size.zero; // no view yet: leave things as they are
    lock.apply();
    expect(calls, hasLength(2));
  });
}
