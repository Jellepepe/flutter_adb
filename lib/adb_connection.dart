// Copyright 2026 Pepe Tiebosch (byme.dev). All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_adb/adb_crypto.dart';
import 'package:flutter_adb/adb_message.dart';
import 'package:flutter_adb/adb_protocol.dart';
import 'package:flutter_adb/adb_stream.dart';
import 'package:flutter_adb/adb_transport.dart';
import 'package:flutter_adb/dart_socket_adb_transport.dart';

class AdbConnection {
  final String ip;
  final int port;
  final AdbCrypto crypto;
  final Map<int, AdbStream> openStreams = {};
  final bool verbose;
  final AdbTransportFactory _transportFactory;

  bool _transportConnected = false;
  bool _adbConnected = false;

  bool _sentSignature = false;
  bool _tlsEnabled = false;
  AdbTransport? _transport;

  Future? _sendLock;

  StreamSubscription<AdbMessage>? _adbMessageSubscription;
  StreamSubscription<bool>? _transportConnectedSubscription;
  StreamSubscription<Uint8List>? _transportDataSubscription;

  /// Specifies the maximum amount data that can be sent to the remote peer.
  /// Only valid after a connection has been established.
  int? maxData;

  final StreamController<AdbMessage> _adbStreamController =
      StreamController<AdbMessage>.broadcast();
  final StreamController<bool> _transportConnectedController =
      StreamController<bool>.broadcast();
  final StreamController<bool> _adbConnectedController =
      StreamController<bool>.broadcast();

  Stream<bool> get onConnectionChanged => _adbConnectedController.stream;

  AdbConnection(
    this.ip,
    this.port,
    this.crypto, {
    AdbTransportFactory? transportFactory,
    this.verbose = false,
  }) : _transportFactory =
            transportFactory ?? (() => DartSocketAdbTransport(crypto));

  bool get connected => _transportConnected;

  /// Whether the connection is using TLS encryption (Android 11+).
  bool get tlsEnabled => _tlsEnabled;

  Future<bool> disconnect() async {
    final transport = _transport;
    if (transport == null) {
      return true;
    }
    _transportConnected = false;
    _adbConnected = false;
    _sentSignature = false;
    _tlsEnabled = false;
    _inputBuffer.clear();
    _transportConnectedController.add(_transportConnected);

    await _adbMessageSubscription?.cancel();
    await _transportConnectedSubscription?.cancel();
    await _transportDataSubscription?.cancel();
    _adbMessageSubscription = null;
    _transportConnectedSubscription = null;
    _transportDataSubscription = null;

    for (var stream in openStreams.values) {
      stream.close();
    }
    openStreams.clear();

    _sendLock = null;

    try {
      await transport.close();
    } catch (_) {}
    _transport = null;

    return true;
  }

  Future<bool> connect() async {
    if (_transport != null && _transportConnected == true) {
      return _transportConnected;
    }
    if (_transport != null) {
      await disconnect();
    }
    try {
      final transport = _transportFactory();
      _transport = transport;
      await transport.connect(ip, port);

      // Add transport listener
      _transportDataSubscription = transport.input.listen(
        _handleAdbInput,
        onDone: () {
          _transportConnected = false;
          _transportConnectedController.add(_transportConnected);
        },
        onError: (error) {
          _transportConnected = false;
          _transportConnectedController.add(_transportConnected);
        },
      );
      _transportConnected = transport.connected;
      if (!_transportConnected) {
        throw StateError('Transport did not connect');
      }
      _transportConnectedController.add(_transportConnected);

      // Listen to adb messages
      await _adbMessageSubscription?.cancel();
      _adbMessageSubscription = _adbStreamController.stream
          .where((message) => AdbProtocol.validateAdbMessage(message))
          .listen((message) async {
        await _handleAdbMessage(message);
      });

      await _transportConnectedSubscription?.cancel();
      _transportConnectedSubscription =
          _transportConnectedController.stream.listen(
        (connected) => connected ? {} : _adbConnectedController.add(false),
      );

      // Send connection init
      final adbConnected = _adbConnectedController.stream.first;
      await _connectAdb();

      // wait for adbConnected
      return await adbConnected;
    } catch (e) {
      print('Failed to connect to ADB: $e');
      if (_transport != null) {
        await disconnect();
      } else {
        _transportConnected = false;
        _adbConnected = false;
      }
      return false;
    }
  }

  Future<void> _connectAdb() async {
    if (!_transportConnected) {
      throw Exception('Transport not connected');
    }
    await _transport!.write(AdbProtocol.generateConnect());
    if (verbose) print('Sent connect message');
  }

  Future<void> sendMessage(Uint8List messageData, {bool flush = false}) async {
    if (!_adbConnected) {
      throw Exception('Not connected to ADB');
    }
    await _sendRaw(messageData, flush: flush);
  }

  Future<void> _sendRaw(Uint8List data, {bool flush = false}) async {
    final transport = _transport;
    if (transport == null) return;

    final completer = Completer();
    final prevLock = _sendLock;
    _sendLock = completer.future;
    if (prevLock != null) await prevLock;

    if (verbose) print('Sending adb data: $data');
    try {
      await transport.write(data);
      if (flush && verbose) print('Flushed adb data: $data');
    } catch (e) {
      if (verbose) print('Error sending adb data: $e');
    } finally {
      completer.complete();
    }
  }

  final List<int> _inputBuffer = [];

  void _handleAdbInput(Uint8List data) {
    if (verbose) print('Received adb data: $data');
    List<int> internalBuffer = [];
    if (_inputBuffer.isNotEmpty) {
      internalBuffer.addAll(_inputBuffer);
      _inputBuffer.clear();
    }
    internalBuffer.addAll(data);
    while (internalBuffer.length >= AdbProtocol.ADB_HEADER_LENGTH) {
      var header = internalBuffer.sublist(0, AdbProtocol.ADB_HEADER_LENGTH);
      var byteData = ByteData.view(Uint8List.fromList(header).buffer);
      var command = byteData.getUint32(0, Endian.little);
      var arg0 = byteData.getUint32(4, Endian.little);
      var arg1 = byteData.getUint32(8, Endian.little);
      var payloadLength = byteData.getUint32(12, Endian.little);
      var checksum = byteData.getUint32(16, Endian.little);
      var magic = byteData.getUint32(20, Endian.little);
      if (internalBuffer.length <
          AdbProtocol.ADB_HEADER_LENGTH + payloadLength) {
        _inputBuffer.addAll(internalBuffer);
        break;
      }
      List<int>? payload;
      if (payloadLength > 0) {
        payload = internalBuffer.sublist(
          AdbProtocol.ADB_HEADER_LENGTH,
          AdbProtocol.ADB_HEADER_LENGTH + payloadLength,
        );
        internalBuffer = internalBuffer.sublist(
          AdbProtocol.ADB_HEADER_LENGTH + payloadLength,
        );
        _adbStreamController.add(
          AdbMessage(
            command,
            arg0,
            arg1,
            payloadLength,
            checksum,
            magic,
            Uint8List.fromList(payload),
          ),
        );
      } else {
        internalBuffer = internalBuffer.sublist(AdbProtocol.ADB_HEADER_LENGTH);
        final message = AdbMessage(
          command,
          arg0,
          arg1,
          payloadLength,
          checksum,
          magic,
        );
        _adbStreamController.add(message);
        if (command == AdbProtocol.CMD_STLS) {
          if (internalBuffer.isNotEmpty) {
            _inputBuffer.addAll(internalBuffer);
          }
          return;
        }
      }
    }
  }

  Future<void> _handleAdbMessage(AdbMessage message) async {
    if (verbose) print('Received adb message: $message');
    switch (message.command) {
      case AdbProtocol.CMD_OKAY:
        // Drop these messages when not in connected state
        if (!_adbConnected) return;
        // Drop message if the stream is not open
        if (!openStreams.containsKey(message.arg1)) return;
        // Set the remote ID for the stream
        openStreams[message.arg1]!.remoteId = message.arg0;
        // Notify that the remote stream is ready for write
        openStreams[message.arg1]!.readyForWrite();
        break;
      case AdbProtocol.CMD_WRTE:
        // Drop these messages when not in connected state
        if (!_adbConnected) return;
        // Drop message if the stream is not open
        if (!openStreams.containsKey(message.arg1)) return;
        // Add payload to the stream
        openStreams[message.arg1]!.addPayload(message.payload!);
        // Notify that we are ready for write
        await openStreams[message.arg1]!.sendReady();
        break;
      case AdbProtocol.CMD_CLSE:
        // Drop these messages when not in connected state
        if (!_adbConnected) return;
        // Drop message if the stream is not open
        if (!openStreams.containsKey(message.arg1)) return;

        openStreams[message.arg1]!.close();
        openStreams.remove(message.arg1);
        break;
      case AdbProtocol.CMD_AUTH:
        // Drop non-token messages
        if (message.arg0 != AdbProtocol.AUTH_TYPE_TOKEN) return;
        // Send the token to the remote peer
        if (_sentSignature) {
          await _sendRaw(
            AdbProtocol.generateAuth(
              AdbProtocol.AUTH_TYPE_RSA_PUBLIC,
              crypto.getAdbPublicKeyPayload(),
            ),
          );
        } else if (message.payload != null) {
          await _sendRaw(
            AdbProtocol.generateAuth(
              AdbProtocol.AUTH_TYPE_SIGNATURE,
              crypto.signAdbTokenPayload(message.payload!),
            ),
          );
          _sentSignature = true;
        }
        break;
      case AdbProtocol.CMD_CNXN:
        // Update max data from the remote peer
        maxData = message.arg1;
        // Notify that the connection is established
        _adbConnected = true;
        _adbConnectedController.add(true);
        break;
      case AdbProtocol.CMD_STLS:
        // Device requires TLS upgrade (Android 11+)
        if (verbose) print('Device requires TLS, upgrading connection...');
        await _upgradeToTls();
        break;
      default:
        // Unknown message, drop it
        break;
    }
  }

  /// Upgrades the current transport to a TLS-encrypted connection.
  ///
  /// This is called when the device sends a STLS message (Android 11+).
  /// The flow is:
  /// 1. Send STLS response (agreeing to TLS)
  /// 2. Ask the transport to perform its TLS handshake
  /// 3. The device will then send CNXN over the TLS channel
  Future<void> _upgradeToTls() async {
    final transport = _transport;
    if (transport == null) return;

    // Send STLS response to agree to the TLS upgrade
    await transport.write(AdbProtocol.generateStls());
    if (verbose) print('Sent STLS response, performing TLS handshake...');

    try {
      if (transport is! AdbTlsTransport) {
        throw UnsupportedError(
          'The configured ADB transport does not support TLS upgrades',
        );
      }

      await transport.upgradeToTls();
      _inputBuffer.clear();
      _tlsEnabled = true;

      if (verbose) print('TLS handshake complete, waiting for device CNXN...');
    } catch (e) {
      if (verbose) {
        print('TLS handshake failed: $e');
      }
      _transportConnected = false;
      _transportConnectedController.add(_transportConnected);
      _adbConnectedController.add(false);
    }
  }

  /// Opens a new shell stream to the remote peer,
  /// ensuring that the connection is established and the stream is open.
  Future<AdbStream> openShell() async {
    return open('shell:');
  }

  /// Opens a new stream to the remote peer,
  /// ensuring that the connection is established and the stream is open.
  Future<AdbStream> open(String destination) async {
    if (!_adbConnected) {
      throw Exception('Not connected to ADB');
    }
    int localId = openStreams.length + 1;
    AdbStream stream = AdbStream(localId, this);
    openStreams[localId] = stream;
    await sendMessage(AdbProtocol.generateOpen(localId, destination));
    if (await stream.onWriteReady.first.timeout(
      const Duration(seconds: 10),
      onTimeout: () => false,
    )) {
      return stream;
    } else {
      throw Exception('Stream open failed or refused by remote peer');
    }
  }

  /// Closes all connected streams
  Future<void> cleanupStreams() async {
    for (var stream in openStreams.values) {
      stream.close();
    }
    openStreams.clear();
  }
}
