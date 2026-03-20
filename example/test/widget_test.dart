import 'package:example/qr_pairing_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_adb/flutter_adb.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders generated qr pairing details',
      (WidgetTester tester) async {
    final qr =
        AdbQrPairingData(serviceName: 'studio-test123', password: 'pw123456');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QrPairingPanel(
            pairingData: qr,
            statusText: 'Waiting for scan',
            onStart: null,
          ),
        ),
      ),
    );

    expect(find.text('QR Pairing'), findsOneWidget);
    expect(find.textContaining('studio-test123'), findsOneWidget);
    expect(find.textContaining('pw123456'), findsOneWidget);
    expect(find.text('Waiting for scan'), findsOneWidget);
    expect(find.text('Generate New QR'), findsOneWidget);
  });
}
