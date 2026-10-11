// Copyright 2026 Jaren. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_adb/adb_certificate.dart';
import 'package:flutter_adb/adb_crypto.dart';
import 'package:flutter_adb/adb_transport.dart';

/// The default [AdbTransport], backed by a Dart [Socket].
final class DartSocketAdbTransport implements AdbTlsTransport {
  DartSocketAdbTransport(
    this.crypto, {
    this.connectionTimeout = const Duration(seconds: 1),
  });

  final AdbCrypto crypto;
  final Duration connectionTimeout;

  Socket? _socket;
  StreamController<Uint8List>? _inputController;
  StreamSubscription<Uint8List>? _socketSubscription;
  bool _connected = false;

  @override
  Stream<Uint8List> get input =>
      _inputController?.stream ?? const Stream<Uint8List>.empty();

  @override
  bool get connected => _connected;

  @override
  Future<void> connect(String host, int port) async {
    if (_connected) {
      throw StateError('Transport is already connected');
    }

    final inputController = StreamController<Uint8List>();
    _inputController = inputController;

    try {
      final socket = await Socket.connect(
        InternetAddress(host),
        port,
        timeout: connectionTimeout,
      );
      socket.setOption(SocketOption.tcpNoDelay, true);
      _socket = socket;
      _connected = true;
      _listenTo(socket, inputController);
    } catch (_) {
      _inputController = null;
      await inputController.close();
      rethrow;
    }
  }

  void _listenTo(Socket socket, StreamController<Uint8List> inputController) {
    _socketSubscription = socket.listen(
      inputController.add,
      onError: (Object error, StackTrace stackTrace) {
        _connected = false;
        inputController.addError(error, stackTrace);
        unawaited(inputController.close());
      },
      onDone: () {
        _connected = false;
        unawaited(inputController.close());
      },
    );
  }

  @override
  Future<void> write(Uint8List data) async {
    final socket = _socket;
    if (!_connected || socket == null) {
      throw StateError('Transport is not connected');
    }

    socket.add(data);
    await socket.flush();
  }

  @override
  Future<void> upgradeToTls() async {
    final socket = _socket;
    final inputController = _inputController;
    if (!_connected || socket == null || inputController == null) {
      throw StateError('Transport is not connected');
    }

    _socketSubscription?.pause();
    final securityContext = AdbCertificate.createTransportSecurityContext(
      crypto.keyPair,
    );

    try {
      final secureSocket = await SecureSocket.secure(
        socket,
        context: securityContext,
        onBadCertificate: (_) => true,
      );
      _socket = secureSocket;
      _listenTo(secureSocket, inputController);
    } catch (_) {
      _connected = false;
      rethrow;
    }
  }

  @override
  Future<void> close() async {
    _connected = false;

    final subscription = _socketSubscription;
    _socketSubscription = null;
    await subscription?.cancel();

    final socket = _socket;
    _socket = null;
    if (socket != null) {
      try {
        await socket.flush();
      } catch (_) {}
      socket.destroy();
    }

    final inputController = _inputController;
    _inputController = null;
    if (inputController != null && !inputController.isClosed) {
      await inputController.close();
    }
  }
}
