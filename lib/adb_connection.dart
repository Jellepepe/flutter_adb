// Copyright 2026 Pepe Tiebosch (byme.dev). All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_adb/adb_certificate.dart';
import 'package:flutter_adb/adb_crypto.dart';
import 'package:flutter_adb/adb_message.dart';
import 'package:flutter_adb/adb_protocol.dart';
import 'package:flutter_adb/adb_stream.dart';

class AdbConnection {
  final String ip;
  final int port;
  final AdbCrypto crypto;
  final Map<int, AdbStream> openStreams = {};
  final bool verbose;

  bool _socketConnected = false;
  bool _adbConnected = false;

  bool _sentSignature = false;
  bool _tlsEnabled = false;
  Socket? _socket;

  Future? _sendLock;

  StreamSubscription<AdbMessage>? _adbMessageSubscription;
  StreamSubscription<bool>? _socketConnectedSubscription;
  StreamSubscription<Uint8List>? _socketDataSubscription;

  /// Specifies the maximum amount data that can be sent to the remote peer.
  /// Only valid after a connection has been established.
  int? maxData;

  final StreamController<AdbMessage> _adbStreamController = StreamController<AdbMessage>.broadcast();
  final StreamController<bool> _socketConnectedController = StreamController<bool>.broadcast();
  final StreamController<bool> _adbConnectedController = StreamController<bool>.broadcast();

  Stream<bool> get onConnectionChanged => _adbConnectedController.stream;

  AdbConnection(this.ip, this.port, this.crypto, {this.verbose = false});

  bool get connected => _socketConnected;

  /// Whether the connection is using TLS encryption (Android 11+).
  bool get tlsEnabled => _tlsEnabled;

  Future<bool> disconnect() async {
    if (_socket == null) {
      return true;
    }
    _socketConnected = false;
    _adbConnected = false;
    _sentSignature = false;
    _tlsEnabled = false;
    _socketConnectedController.add(_socketConnected);

    await _adbMessageSubscription?.cancel();
    await _socketConnectedSubscription?.cancel();
    await _socketDataSubscription?.cancel();
    _adbMessageSubscription = null;
    _socketConnectedSubscription = null;
    _socketDataSubscription = null;

    for (var stream in openStreams.values) {
      stream.close();
    }
    openStreams.clear();

    _sendLock = null;

    try {
      await _socket!.flush();
      _socket!.destroy();
    } catch (_) {}
    _socket = null;

    return true;
  }

  Future<bool> connect() async {
    if (_socket != null && _socketConnected == true) {
      return _socketConnected;
    }
    try {
      // Create socket connection
      _socket = await Socket.connect(InternetAddress(ip), port, timeout: const Duration(seconds: 1))
        ..setOption(SocketOption.tcpNoDelay, true);

      // Add socket listener
      _socketDataSubscription = _socket!.listen(
        _handleAdbInput,
        onDone: () {
          _socketConnected = false;
          _socketConnectedController.add(_socketConnected);
        },
        onError: (error) {
          _socketConnected = false;
          _socketConnectedController.add(_socketConnected);
        },
      );
      _socketConnected = true;
      _socketConnectedController.add(_socketConnected);

      // Listen to adb messages
      await _adbMessageSubscription?.cancel();
      _adbMessageSubscription = _adbStreamController.stream
          .where((message) => AdbProtocol.validateAdbMessage(message))
          .listen((message) async {
        await _handleAdbMessage(message);
      });

      await _socketConnectedSubscription?.cancel();
      _socketConnectedSubscription =
          _socketConnectedController.stream.listen((connected) => connected ? {} : _adbConnectedController.add(false));

      // Send connection init
      await _connectAdb();

      // wait for adbConnected
      return await _adbConnectedController.stream.first;
    } catch (e) {
      print('Failed to connect to ADB: $e');
      return false;
    }
  }

  Future<void> _connectAdb() async {
    if (!_socketConnected) {
      throw Exception('Socket not connected');
    }
    _socket!.add(AdbProtocol.generateConnect());
    await _socket!.flush();
    if (verbose) print('Sent connect message');
  }

  Future<void> sendMessage(Uint8List messageData, {bool flush = false}) async {
    if (!_adbConnected) {
      throw Exception('Not connected to ADB');
    }
    await _sendRaw(messageData, flush: flush);
  }

  Future<void> _sendRaw(Uint8List data, {bool flush = false}) async {
    final socket = _socket;
    if (socket == null) return;

    final completer = Completer();
    final prevLock = _sendLock;
    _sendLock = completer.future;
    if (prevLock != null) await prevLock;

    if (verbose) print('Sending adb data: $data');
    try {
      socket.add(data);
      if (flush) {
        await socket.flush();
        if (verbose) print('Flushed adb data: $data');
      }
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
      if (internalBuffer.length < AdbProtocol.ADB_HEADER_LENGTH + payloadLength) {
        _inputBuffer.addAll(internalBuffer);
        break;
      }
      List<int>? payload;
      if (payloadLength > 0) {
        payload = internalBuffer.sublist(AdbProtocol.ADB_HEADER_LENGTH, AdbProtocol.ADB_HEADER_LENGTH + payloadLength);
        internalBuffer = internalBuffer.sublist(AdbProtocol.ADB_HEADER_LENGTH + payloadLength);
        _adbStreamController
            .add(AdbMessage(command, arg0, arg1, payloadLength, checksum, magic, Uint8List.fromList(payload)));
      } else {
        internalBuffer = internalBuffer.sublist(AdbProtocol.ADB_HEADER_LENGTH);
        final message = AdbMessage(command, arg0, arg1, payloadLength, checksum, magic);
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
          await _sendRaw(AdbProtocol.generateAuth(AdbProtocol.AUTH_TYPE_RSA_PUBLIC, crypto.getAdbPublicKeyPayload()));
        } else if (message.payload != null) {
          await _sendRaw(
            AdbProtocol.generateAuth(AdbProtocol.AUTH_TYPE_SIGNATURE, crypto.signAdbTokenPayload(message.payload!)),
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

  /// Upgrades the current TCP socket to a TLS-encrypted connection.
  ///
  /// This is called when the device sends a STLS message (Android 11+).
  /// The flow is:
  /// 1. Send STLS response (agreeing to TLS)
  /// 2. Perform TLS handshake using a self-signed certificate
  /// 3. Re-attach the data listener to the SecureSocket
  /// 4. The device will then send CNXN over the TLS channel
  Future<void> _upgradeToTls() async {
    final socket = _socket;
    if (socket == null) return;

    // Send STLS response to agree to the TLS upgrade
    socket.add(AdbProtocol.generateStls());
    await socket.flush();
    if (verbose) print('Sent STLS response, performing TLS handshake...');

    // Pause the plaintext listener so SecureSocket can take over the socket
    // without closing the underlying connection.
    _socketDataSubscription?.pause();

    // Create a SecurityContext with a self-signed certificate from our RSA keypair
    final securityContext = AdbCertificate.createTransportSecurityContext(crypto.keyPair);

    try {
      // Upgrade the socket to TLS
      final secureSocket = await SecureSocket.secure(
        socket,
        context: securityContext,
        onBadCertificate: (_) => true, // Accept device's self-signed certificate
      );

      // Clear any plaintext parser state before the TLS socket takes over.
      _inputBuffer.clear();

      // Re-attach the listener to the new SecureSocket
      _socketDataSubscription = secureSocket.listen(
        _handleAdbInput,
        onDone: () {
          _socketConnected = false;
          _socketConnectedController.add(_socketConnected);
        },
        onError: (error) {
          _socketConnected = false;
          _socketConnectedController.add(_socketConnected);
        },
      );

      // Replace the socket reference
      _socket = secureSocket;
      _tlsEnabled = true;

      if (verbose) print('TLS handshake complete, waiting for device CNXN...');
    } catch (e) {
      if (verbose) {
        print('TLS handshake failed: $e');
      }
      _socketConnected = false;
      _socketConnectedController.add(_socketConnected);
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
    if (await stream.onWriteReady.first.timeout(const Duration(seconds: 10), onTimeout: () => false)) {
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
