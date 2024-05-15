// Copyright 2024 Pepe Tiebosch (byme.dev). All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_adb/adb_message.dart';

class AdbProtocol {
  /// The length of the ADB message header
  static const int ADB_HEADER_LENGTH = 24;

  /// CNXN is the connect message. No messages (except AUTH) are valid before this message is received.
  static const int CMD_CNXN = 0x4e584e43;

  /// The current version of the ADB protocol
  static const int CONNECT_VERSION = 0x01000000;

  /// The maximum data payload supported by the ADB implementation
  static const int CONNECT_MAXDATA = 4096;

  /// The payload sent with the connect message
  // ignore: non_constant_identifier_names
  static Uint8List CONNECT_PAYLOAD = utf8.encode('host::\x00');

  /// AUTH is the authentication message. It is part of the RSA public key authentication added in Android 4.2.2.
  static const int CMD_AUTH = 0x48545541;

  /// This authentication type represents a SHA1 hash to sign
  static const int AUTH_TYPE_TOKEN = 1;

  /// This authentication type represents the signed SHA1 hash
  static const int AUTH_TYPE_SIGNATURE = 2;

  /// This authentication type represents a RSA public key
  static const int AUTH_TYPE_RSA_PUBLIC = 3;

  /// OPEN is the open stream message. It is sent to open a new stream on the target device.
  static const int CMD_OPEN = 0x4e45504f;

  /// OKAY is a success message. It is sent when a write is processed successfully.
  static const int CMD_OKAY = 0x59414b4f;

  /// CLSE is the close stream message. It it sent to close an existing stream on the target device.
  static const int CMD_CLSE = 0x45534c43;

  /// WRTE is the write stream message. It is sent with a payload that is the data to write to the stream.
  static const int CMD_WRTE = 0x45545257;

  static Uint8List generateConnect() {
    return generateMessage(CMD_CNXN, CONNECT_VERSION, CONNECT_MAXDATA, CONNECT_PAYLOAD);
  }

  static Uint8List generateAuth(int authType, Uint8List payload) {
    return generateMessage(CMD_AUTH, authType, 0, payload);
  }

  static Uint8List generateOpen(int localId, String destination) {
    return generateMessage(CMD_OPEN, localId, 0, utf8.encode(destination));
  }

  static Uint8List generateWrite(int localId, int remoteId, Uint8List payload) {
    return generateMessage(CMD_WRTE, localId, remoteId, payload);
  }

  static Uint8List generateClose(int localId, int remoteId) {
    return generateMessage(CMD_CLSE, localId, remoteId, null);
  }

  static Uint8List generateReady(int localId, int remoteId) {
    return generateMessage(CMD_OKAY, localId, remoteId, null);
  }

  static Uint8List generateMessage(int command, int arg0, int arg1, Uint8List? payload) {
    Uint8List message;

    if (payload != null) {
      message = Uint8List(ADB_HEADER_LENGTH + payload.length);
    } else {
      message = Uint8List(ADB_HEADER_LENGTH);
    }

    ByteData byteData = ByteData.view(message.buffer);

    byteData.setUint32(0, command, Endian.little);
    byteData.setUint32(4, arg0, Endian.little);
    byteData.setUint32(8, arg1, Endian.little);

    if (payload != null) {
      byteData.setUint32(12, payload.length, Endian.little);
      byteData.setUint32(16, generatePayloadChecksum(payload), Endian.little);
    } else {
      byteData.setUint32(12, 0, Endian.little);
      byteData.setUint32(16, 0, Endian.little);
    }

    byteData.setUint32(20, (~command).toUnsigned(command.bitLength + 1), Endian.little);

    if (payload != null) {
      message.setAll(ADB_HEADER_LENGTH, payload);
    }

    return message;
  }

  static bool validateAdbMessage(AdbMessage message) {
    if (message.magic != (~message.command).toUnsigned(message.command.bitLength + 1)) {
      print('Magic invalid: $message');
      return false;
    }
    if (message.payload != null) {
      bool valid = generatePayloadChecksum(message.payload!) == message.checksum;
      if (!valid) print('Checksum invalid: $message');
      return valid;
    }
    return true;
  }

  static int generatePayloadChecksum(Uint8List payload) {
    int checksum = 0;

    for (int byte in payload) {
      if (byte >= 0) {
        checksum += byte;
      } else {
        checksum += 256 + byte;
      }
    }
    return checksum;
  }
}
