import 'package:flutter_adb/flutter_adb.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('qr payload matches the AOSP WIFI:T:ADB format', () {
    final qr =
        AdbQrPairingData(serviceName: 'studio-test123', password: 'abc123XYZ');

    expect(qr.qrPayload, 'WIFI:T:ADB;S:studio-test123;P:abc123XYZ;;');
  });

  test('generated qr payload round-trips through parse', () {
    final qr = AdbQrPairingData.generate();
    final parsed = AdbQrPairingData.parse(qr.qrPayload);

    expect(parsed.serviceName, startsWith('studio-'));
    expect(parsed.serviceName, qr.serviceName);
    expect(parsed.password, isNotEmpty);
    expect(parsed.password, qr.password);
  });
}
