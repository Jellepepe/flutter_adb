
import 'dart:async';

import 'package:flutter/services.dart';

class Adb {
  static const MethodChannel _channel =
      const MethodChannel('dev.byme.adb');

  static Future<String> get platformVersion async {
    final String version = await _channel.invokeMethod('getPlatformVersion');
    return version;
  }

  static Future<String> attemptAdb(String command) async {
    final String adbResult = await _channel.invokeMethod('attemptAdb',{'command':command});
    return adbResult;
  }
}
