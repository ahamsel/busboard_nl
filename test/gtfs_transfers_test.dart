import 'dart:io';

import 'package:busboard_nl/data/gtfs/gtfs_parser.dart';
import 'package:busboard_nl/data/gtfs/gtfs_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('gtfs_transfers');
    // Metrobus files can start with a UTF-8 BOM; the first column must still be found.
    await File('${dir.path}/transfers.txt').writeAsString(
      '﻿from_stop_id,to_stop_id,transfer_type,min_transfer_time\n'
      '1150,1150,1,\n'
      '1600,1601,2,180\n'
      '1700,1701,3,\n',
    );
  });
  tearDown(() => dir.delete(recursive: true));

  test('parses every row, the BOM, an empty min time and type 3', () async {
    final rules = await GtfsParser(dir.path).parseTransfers();
    expect(rules.length, 3);
    expect(rules[0].fromStopId, '1150');
    expect(rules[0].minTransferSeconds, isNull);
    expect(rules[1].transferType, 2);
    expect(rules[1].minTransferSeconds, 180);
    expect(rules[2].transferType, 3);
  });

  test('a missing transfers.txt gives no rules', () async {
    await File('${dir.path}/transfers.txt').delete();
    expect(await GtfsParser(dir.path).parseTransfers(), isEmpty);
  });

  test('the repository indexes rules by from stop', () async {
    final repo = GtfsRepository();
    await repo.loadFromDirectory(dir.path);
    expect(repo.transfersByFromStop['1600']!.single.toStopId, '1601');
  });
}
