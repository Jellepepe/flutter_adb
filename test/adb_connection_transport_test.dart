// Copyright 2026 Jaren. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_adb/flutter_adb.dart';
import 'package:flutter_adb/adb_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AdbConnection uses the supplied transport factory', () async {
    final transport = _FakeAdbTransport();
    var factoryCalls = 0;
    final connection = AdbConnection(
      '192.0.2.1',
      5555,
      AdbCrypto(),
      transportFactory: () {
        factoryCalls++;
        return transport;
      },
    );

    final connected = await connection.connect();

    expect(connected, isTrue);
    expect(factoryCalls, 1);
    expect(transport.host, '192.0.2.1');
    expect(transport.port, 5555);
    expect(transport.writes, hasLength(1));
    expect(transport.writes.single, AdbProtocol.generateConnect());

    await connection.disconnect();
    expect(transport.closeCalls, 1);
    expect(connection.connected, isFalse);
  });
}

final class _FakeAdbTransport implements AdbTransport {
  final StreamController<Uint8List> _inputController =
      StreamController<Uint8List>();
  final List<Uint8List> writes = [];

  String? host;
  int? port;
  int closeCalls = 0;

  @override
  bool connected = false;

  @override
  Stream<Uint8List> get input => _inputController.stream;

  @override
  Future<void> connect(String host, int port) async {
    this.host = host;
    this.port = port;
    connected = true;
  }

  @override
  Future<void> write(Uint8List data) async {
    writes.add(Uint8List.fromList(data));
    if (writes.length == 1) {
      _inputController.add(
        AdbProtocol.generateMessage(
          AdbProtocol.CMD_CNXN,
          AdbProtocol.CONNECT_VERSION,
          AdbProtocol.CONNECT_MAXDATA,
          null,
        ),
      );
    }
  }

  @override
  Future<void> close() async {
    closeCalls++;
    connected = false;
    await _inputController.close();
  }
}
