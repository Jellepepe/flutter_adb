// Copyright 2024 Pepe Tiebosch (byme.dev). All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:typed_data';

class AdbMessage {
  final int command;
  final int arg0;
  final int arg1;
  final int payloadLength;
  final int checksum;
  final int magic;
  final Uint8List? payload;

  AdbMessage(this.command, this.arg0, this.arg1, this.payloadLength, this.checksum, this.magic, [this.payload]);

  @override
  String toString() {
    return 'AdbMessage{command: 0x${command.toRadixString(16)}, arg0: $arg0, arg1: $arg1, payloadLength: $payloadLength, checksum: $checksum, magic: $magic, payload: $payload}';
  }
}
