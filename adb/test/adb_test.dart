import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:adb/adb.dart';

void main() {
  const MethodChannel channel = MethodChannel('adb');

  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    channel.setMockMethodCallHandler((MethodCall methodCall) async {
      return '42';
    });
  });

  tearDown(() {
    channel.setMockMethodCallHandler(null);
  });

  test('getPlatformVersion', () async {
    expect(await Adb.platformVersion, '42');
  });
}
