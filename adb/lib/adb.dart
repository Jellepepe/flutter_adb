
import 'dart:async';

import 'package:flutter/services.dart';

class Adb {
  static const MethodChannel _channel =
      const MethodChannel('adb');

  static Future<String> get platformVersion async {
    final String version = await _channel.invokeMethod('getPlatformVersion');
    return version;
  }

  static Future<String> get attemptAdb async {
    final String adbResult = await _channel.invokeMethod('attemptAdb');
    return adbResult;
  }
}
