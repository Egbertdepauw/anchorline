import 'package:ccrlogger/ui/widgets/serial_port_picker_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// Opens the picker; the returned function yields the dialog's result.
  Future<String? Function()> openPicker(
      WidgetTester tester, List<String> Function() listPorts) async {
    String? result;
    var done = false;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            result = await showSerialPortPicker(context, listPorts: listPorts);
            done = true;
          },
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return () {
      expect(done, isTrue);
      return result;
    };
  }

  testWidgets('preselects the usbmodem port and returns it', (tester) async {
    final result = await openPicker(
        tester, () => ['/dev/cu.usbmodem101', '/dev/cu.usbserial-A']);

    expect(find.text('/dev/cu.usbmodem101'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('serial-port-connect')));
    await tester.pumpAndSettle();
    expect(result(), '/dev/cu.usbmodem101');
  });

  testWidgets('no ports: explains, Connect disabled, refresh finds the port',
      (tester) async {
    var ports = <String>[];
    final result = await openPicker(tester, () => ports);

    expect(find.byKey(const ValueKey('serial-port-none')), findsOneWidget);
    final connect = tester.widget<FilledButton>(
        find.byKey(const ValueKey('serial-port-connect')));
    expect(connect.onPressed, isNull);

    ports = ['/dev/ttyACM0'];
    await tester.tap(find.byKey(const ValueKey('serial-port-refresh')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('serial-port-connect')));
    await tester.pumpAndSettle();
    expect(result(), '/dev/ttyACM0');
  });

  testWidgets('cancel returns null', (tester) async {
    final result = await openPicker(tester, () => ['COM3']);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result(), isNull);
  });
}
