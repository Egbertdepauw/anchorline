import 'package:ccrlogger/data/import/cylinder_remap.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:subsurface_core/data/models/dive.dart';

DiveGasMix _mix(int o2, int he, {bool dil = false}) =>
    DiveGasMix(oxygenPercent: o2, heliumPercent: he, isDiluent: dil);

void main() {
  test('a reordered gas list moves each cylinder with its mix', () {
    final r = remapCylinderRows(
      oldMixes: [_mix(21, 35, dil: true), _mix(100, 0)],
      newMixes: [_mix(100, 0), _mix(21, 35, dil: true)],
      rowsByIndex: {0: 'dil-cyl', 1: 'o2-cyl'},
    );
    expect(r, {1: 'dil-cyl', 0: 'o2-cyl'});
  });

  test('a mix that is gone leaves its cylinder unassigned at -1', () {
    final r = remapCylinderRows(
      oldMixes: [_mix(21, 35, dil: true), _mix(50, 0)],
      newMixes: [_mix(21, 35, dil: true)],
      rowsByIndex: {0: 'dil-cyl', 1: 'ean50-cyl'},
    );
    expect(r, {0: 'dil-cyl', -1: 'ean50-cyl'});
  });

  test('two gone mixes take -1 and -2; existing negatives count as used', () {
    final r = remapCylinderRows(
      oldMixes: [_mix(50, 0), _mix(80, 0)],
      newMixes: [_mix(21, 0)],
      rowsByIndex: {0: 'a', 1: 'b', -1: 'c'},
    );
    expect(r[-1], 'c');
    expect({r[-2], r[-3]}, {'a', 'b'});
    expect(r, hasLength(3));
  });

  test('an index out of range of the old mixes counts as gone', () {
    final r = remapCylinderRows(
      oldMixes: [_mix(21, 0)],
      newMixes: [_mix(21, 0)],
      rowsByIndex: {0: 'a', 5: 'b'},
    );
    expect(r, {0: 'a', -1: 'b'});
  });

  test(
      'two mixes with the same O2/He keep their diluent and bailout '
      'cylinders apart', () {
    final r = remapCylinderRows(
      oldMixes: [_mix(21, 35, dil: true), _mix(21, 35)],
      newMixes: [_mix(21, 35), _mix(21, 35, dil: true)],
      rowsByIndex: {0: 'dil-cyl', 1: 'bailout-cyl'},
    );
    expect(r, {1: 'dil-cyl', 0: 'bailout-cyl'});
  });

  test('same mix twice falls back to the lowest unused index', () {
    final r = remapCylinderRows(
      oldMixes: [_mix(21, 35), _mix(21, 35)],
      newMixes: [_mix(21, 35, dil: true), _mix(21, 35, dil: true)],
      rowsByIndex: {0: 'a', 1: 'b'},
    );
    expect(r, {0: 'a', 1: 'b'});
  });

  test('an unassigned row stays unassigned and keeps its index', () {
    final r = remapCylinderRows(
      oldMixes: [_mix(21, 0)],
      newMixes: [_mix(21, 0)],
      rowsByIndex: {0: 'a', -2: 'lost'},
    );
    expect(r, {0: 'a', -2: 'lost'});
  });

  test('null cylinder ids are carried along', () {
    final r = remapCylinderRows(
      oldMixes: [_mix(21, 0)],
      newMixes: [_mix(32, 0), _mix(21, 0)],
      rowsByIndex: {0: null},
    );
    expect(r, {1: null});
  });
}
