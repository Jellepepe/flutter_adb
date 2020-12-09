
import 'dart:async';

import 'package:flutter/services.dart';

class Adb {
  static const MethodChannel _channel =
      const MethodChannel('dev.byme.adb');
  static const _outputChannel = const EventChannel('dev.byme.adb/shellStream');

  static Stream<dynamic> _rawOutputStream;

  static Stream<String> get outputStream {
    if(_rawOutputStream == null) {
      _rawOutputStream = _outputChannel.receiveBroadcastStream(1);
    }
    return _rawOutputStream.map((event) => event.toString());
  }

  static Future<String> get platformVersion async {
    final String version = await _channel.invokeMethod('getPlatformVersion');
    return version;
  }

  static Future<String> attemptAdb(String command) async {
    final String adbResult = await _channel.invokeMethod('attemptAdb',{'command':command});
    return adbResult;
  }
}
