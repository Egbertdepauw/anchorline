import 'package:ccrlogger/ui/notifiers/settings_notifier.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<SettingsNotifier> _loaded() async {
  SharedPreferences.setMockInitialValues({});
  final s = SettingsNotifier();
  await s.load();
  return s;
}

Future<SettingsNotifier> _reloaded() async {
  final s = SettingsNotifier();
  await s.load();
  return s;
}

void main() {
  test('defaults to 1.6 everywhere and no printer', () async {
    final s = await _loaded();
    expect(s.labelUse14ForDeeperMixes, isFalse);
    expect(s.labelPrinterId, isNull);
    expect(s.labelPrinterName, isNull);
  });

  test('"Use 1.4 for deeper mixes" persists and reads back', () async {
    final s = await _loaded();
    await s.setLabelUse14ForDeeperMixes(true);
    expect(s.labelUse14ForDeeperMixes, isTrue);
    expect((await _reloaded()).labelUse14ForDeeperMixes, isTrue);

    await s.setLabelUse14ForDeeperMixes(false);
    expect(s.labelUse14ForDeeperMixes, isFalse);
    expect((await _reloaded()).labelUse14ForDeeperMixes, isFalse);
  });

  test('the printer persists and reads back', () async {
    final s = await _loaded();
    await s.setLabelPrinter(id: 'AA:BB:CC', name: 'M110-1234');
    expect(s.labelPrinterId, 'AA:BB:CC');
    expect(s.labelPrinterName, 'M110-1234');

    final reloaded = await _reloaded();
    expect(reloaded.labelPrinterId, 'AA:BB:CC');
    expect(reloaded.labelPrinterName, 'M110-1234');
  });

  test('the settings use the documented preference keys', () async {
    final s = await _loaded();
    await s.setLabelUse14ForDeeperMixes(true);
    await s.setLabelPrinter(id: 'AA:BB:CC', name: 'M110-1234');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('label_use_14_for_deeper_mixes'), isTrue);
    expect(prefs.getString('label_printer_id'), 'AA:BB:CC');
    expect(prefs.getString('label_printer_name'), 'M110-1234');
  });

  test('setting a new printer replaces the old one', () async {
    final s = await _loaded();
    await s.setLabelPrinter(id: 'one', name: 'First');
    await s.setLabelPrinter(id: 'two', name: 'Second');
    final reloaded = await _reloaded();
    expect(reloaded.labelPrinterId, 'two');
    expect(reloaded.labelPrinterName, 'Second');
  });

  test('forgetLabelPrinter clears both id and name', () async {
    final s = await _loaded();
    await s.setLabelPrinter(id: 'AA:BB:CC', name: 'M110-1234');
    await s.forgetLabelPrinter();
    expect(s.labelPrinterId, isNull);
    expect(s.labelPrinterName, isNull);

    final reloaded = await _reloaded();
    expect(reloaded.labelPrinterId, isNull);
    expect(reloaded.labelPrinterName, isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('label_printer_id'), isFalse);
    expect(prefs.containsKey('label_printer_name'), isFalse);
  });

  test('forgetLabelPrinter with no printer is harmless', () async {
    final s = await _loaded();
    var notified = 0;
    s.addListener(() => notified++);
    await s.forgetLabelPrinter();
    expect(s.labelPrinterId, isNull);
    expect(notified, 0);
  });

  test('the setters notify listeners', () async {
    final s = await _loaded();
    var notified = 0;
    s.addListener(() => notified++);

    await s.setLabelUse14ForDeeperMixes(true);
    expect(notified, 1);
    await s.setLabelPrinter(id: 'AA:BB:CC', name: 'M110-1234');
    expect(notified, 2);
    await s.forgetLabelPrinter();
    expect(notified, 3);
  });
}
