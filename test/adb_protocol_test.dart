// Copyright 2026 Jaren. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_adb/adb_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final destination in [
    'shell:',
    'sync:',
    'shell:echo hello',
    'tcp:8080',
    'shell:echo 你好',
  ]) {
    test('OPEN preserves "$destination" when parsed by older adbd', () {
      final message = AdbProtocol.generateOpen(1, destination);
      final header = ByteData.sublistView(message);
      final payload = Uint8List.fromList(
        message.sublist(AdbProtocol.ADB_HEADER_LENGTH),
      );

      expect(header.getUint32(0, Endian.little), AdbProtocol.CMD_OPEN);
      expect(header.getUint32(4, Endian.little), 1);
      expect(header.getUint32(8, Endian.little), 0);
      expect(header.getUint32(12, Endian.little), payload.length);
      expect(
        header.getUint32(16, Endian.little),
        payload.fold<int>(0, (sum, byte) => sum + byte),
      );

      // Simulate older adbd: overwrite the last byte and read a C string.
      payload[payload.length - 1] = 0;
      expect(utf8.decode(payload.sublist(0, payload.indexOf(0))), destination);
    });
  }

  test('OPEN does not duplicate an existing NUL terminator', () {
    final message = AdbProtocol.generateOpen(1, 'shell:\x00');

    expect(
      message.sublist(AdbProtocol.ADB_HEADER_LENGTH),
      [115, 104, 101, 108, 108, 58, 0],
    );
  });

  test('WRTE preserves command and binary payload bytes', () {
    final payload =
        Uint8List.fromList([...utf8.encode('echo hello\n'), 0, 255]);
    final message = AdbProtocol.generateWrite(1, 2, payload);

    expect(message.sublist(AdbProtocol.ADB_HEADER_LENGTH), payload);
  });
}
