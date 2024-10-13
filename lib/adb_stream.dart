// Copyright 2024 Pepe Tiebosch (byme.dev). All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_adb/adb_connection.dart';
import 'package:flutter_adb/adb_protocol.dart';

class AdbStream {
  final StreamController<Uint8List> _readStream = StreamController<Uint8List>.broadcast();
  final StreamController<bool> _writeReadyController = StreamController<bool>.broadcast();

  Stream<Uint8List> get onPayload => _readStream.stream;
  Stream<bool> get onWriteReady => _writeReadyController.stream;

  final AdbConnection _adbConnection;
  final int localId;
  int? remoteId;
  bool _writeReady = false;

  bool get isClosed => _readStream.isClosed;

  AdbStream(this.localId, this._adbConnection);

  void addPayload(Uint8List payload) {
    _readStream.add(payload);
  }

  void readyForWrite() {
    _writeReady = true;
    _writeReadyController.add(_writeReady);
  }

  Future<void> sendReady() async {
    if (remoteId == null) {
      throw Exception('Remote ID is not set');
    }
    await _adbConnection.sendMessage(AdbProtocol.generateReady(localId, remoteId!));
  }

  Future<bool> writeString(String payload) {
    return write(utf8.encode(payload), true);
  }

  Future<bool> write(Uint8List payload, bool flush) async {
    if (remoteId == null) {
      throw Exception('Remote ID is not set');
    }
    while (!isClosed && !_writeReady) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    if (isClosed) {
      return false;
    }
    _writeReady = false;
    _writeReadyController.add(_writeReady);

    await _adbConnection.sendMessage(AdbProtocol.generateWrite(localId, remoteId!, payload), flush: flush);
    return true;
  }

  void close() {
    if (isClosed) {
      return;
    }
    _readStream.close();
  }

  void sendClose() {
    if (isClosed) {
      return;
    }
    _adbConnection.sendMessage(AdbProtocol.generateClose(localId, remoteId!), flush: true);
    close();
  }
}
