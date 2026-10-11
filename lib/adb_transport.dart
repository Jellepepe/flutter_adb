// Copyright 2026 Jaren. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:typed_data';

/// Creates a new transport for an ADB connection.
typedef AdbTransportFactory = AdbTransport Function();

/// The byte transport used by an ADB connection.
abstract interface class AdbTransport {
  Stream<Uint8List> get input;

  bool get connected;

  Future<void> connect(String host, int port);

  Future<void> write(Uint8List data);

  Future<void> close();
}

/// Optional transport capability for Android 11+ STLS connections.
///
/// Implement this interface when a custom transport can upgrade its active
/// connection to TLS after the ADB STLS exchange.
abstract interface class AdbTlsTransport implements AdbTransport {
  Future<void> upgradeToTls();
}
