// Copyright 2024 Pepe Tiebosch (byme.dev). All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

library flutter_adb;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_adb/adb_connection.dart';
import 'package:flutter_adb/adb_crypto.dart';
import 'package:flutter_adb/adb_stream.dart';

class Adb {
  /// Convenience method to open an ADB connection, open a shell and send a single command, then closing the connection.
  /// The function will return the sanitized output of the command.
  static Future<String> sendSingleCommand(
    String command, {
    String ip = '127.0.0.1',
    int port = 5555,
    AdbCrypto? crypto,
  }) async {
    AdbConnection connection = AdbConnection(ip, port, crypto ?? AdbCrypto());
    if (!await connection.connect()) {
      debugPrint('Failed to connect to $ip:$port');
      return '';
    }
    String finalCommand = '$command;exit\n';
    AdbStream stream = await connection.openShell();
    stream.writeString(finalCommand);
    String output = await stream.onPayload.fold('', (previous, element) => previous + utf8.decode(element)).timeout(
      const Duration(minutes: 1),
      onTimeout: () {
        debugPrint('Timeout closing the stream.');
        stream.close();
        return '';
      },
    );
    await connection.disconnect();
    // Sanitize output
    output = output.replaceAll('\r', '');
    output.endsWith('\n') ? output = output.substring(0, output.length - 1) : output;
    return output.split(finalCommand).last.trim();
  }
}
