import 'dart:typed_data';

import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/db/dive_merge_dao.dart';
import 'package:ccrlogger/ui/models/dive_list_item.dart';
import 'package:flutter_test/flutter_test.dart';

Dive d({required String id, required int start, required int end}) => Dive(
      id: id,
      dcSerial: 1,
      dcDiveNumber: 1,
      startTime: start,
      endTime: end,
      durationSeconds: end - start,
      maxDepthMm: 30000,
      diveMode: 0,
      decoModel: 0,
      atmosphericPressureMbar: 1013,
      waterDensity: 1030,
      logVersion: 1,
      dcModel: 0,
      sampleIntervalMs: 10000,
      gasMixesJson: '[]',
      rawBlob: Uint8List(0),
      parserVersion: 1,
      importedAt: 0,
    );

void main() {
  // dives passed in start-DESC order (matching getAllDives()).
  final newest = d(id: 'c', start: 9000, end: 12000);
  final mid = d(id: 'b', start: 5000, end: 8000);
  final oldest = d(id: 'a', start: 0, end: 3000);

  test('no links -> all single items', () {
    final items = buildListItems([newest, mid, oldest], const []);
    expect(items.length, 3);
    expect(items.every((i) => i is SingleDive), isTrue);
  });

  test('two linked dives collapse into one group item', () {
    final links = [
      const MergeLink(diveId: 'a', groupId: 'g1'),
      const MergeLink(diveId: 'b', groupId: 'g1'),
    ];
    final items = buildListItems([newest, mid, oldest], links);
    expect(items.length, 2);
    final group = items.whereType<MergedGroupItem>().single.group;
    expect(group.members.map((m) => m.id).toList(), ['a', 'b']); // sorted asc
    expect(group.totalInWaterSeconds, 3000 + 3000);
    expect(group.surfaceGapsSeconds, [5000 - 3000]);
  });

  test('a group with only one present member stays a single item', () {
    final links = [const MergeLink(diveId: 'a', groupId: 'g1')];
    final items = buildListItems([newest, mid, oldest], links);
    expect(items.length, 3);
    expect(items.every((i) => i is SingleDive), isTrue);
  });
}
