import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:busboard_nl/ui/map/map_style.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no override follows the app brightness', () {
    expect(MapStyle.assetFor(Brightness.light, null), MapStyle.lightAsset);
    expect(MapStyle.assetFor(Brightness.dark, null), MapStyle.darkAsset);
    expect(MapStyle.assetFor(Brightness.dark, BBThemeMode.system), MapStyle.darkAsset);
  });

  test('an override wins over the app brightness', () {
    expect(MapStyle.assetFor(Brightness.dark, BBThemeMode.light), MapStyle.lightAsset);
    expect(MapStyle.assetFor(Brightness.light, BBThemeMode.dark), MapStyle.darkAsset);
    expect(MapStyle.brightnessFor(Brightness.light, BBThemeMode.dark), Brightness.dark);
  });
}
