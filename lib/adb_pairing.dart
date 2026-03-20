// Copyright 2026 Pepe Tiebosch (byme.dev). All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_adb/adb_certificate.dart';
import 'package:flutter_adb/adb_crypto.dart';
import 'package:flutter_adb/spake2.dart';
import 'package:flutter_adb/src/pairing_protocol.dart';
import 'package:flutter_adb/src/tls_exporter.dart';

/// ADB wireless pairing protocol handler (Android 11+).
///
/// This implementation follows the AOSP pairing protocol:
/// TLS handshake -> TLS exported keying material -> SPAKE2 -> encrypted PeerInfo.
class AdbPairing {
  /// Pair with an Android device using the wireless debugging pairing code.
  ///
  /// Returns `true` if pairing succeeded, `false` otherwise.
  static Future<bool> pair(
    String ip,
    int port,
    String pairingCode,
    AdbCrypto crypto, {
    bool verbose = false,
  }) async {
    return _pairWithDartTls(ip, port, pairingCode, crypto, verbose: verbose);
  }

  static Future<void> _writePacket(
    PairingTlsChannel channel,
    int type,
    Uint8List payload,
  ) async {
    final header = PairingPacketHeader(type, payload.length).encode();
    await channel.writeAll(header);
    await channel.writeAll(payload);
  }

  static Future<Uint8List?> _readPacket(
    PairingTlsChannel channel, {
    required int expectedType,
    required bool verbose,
  }) async {
    final headerBytes = await channel.readExact(kPairingPacketHeaderSize);
    if (headerBytes == null) {
      if (verbose) print('Failed to read pairing packet header');
      return null;
    }

    if (verbose) print('Received header: ${_toHex(headerBytes)}');
    final header = PairingPacketHeader.decode(headerBytes);
    if (verbose) {
      print('Packet version: $kPairingPacketVersion, type: ${header.type}, size: ${header.payloadSize}');
    }

    if (header.type != expectedType) {
      throw FormatException('Unexpected pairing packet type: ${header.type} (expected $expectedType)');
    }

    final payload = await channel.readExact(header.payloadSize);
    if (payload == null) {
      if (verbose) print('Failed to read pairing packet payload');
      return null;
    }
    return payload;
  }

  static String _toHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ').toUpperCase();
  }
}

abstract interface class PairingTlsChannel {
  Future<Uint8List?> readExact(int count);

  Future<void> writeAll(Uint8List bytes);

  Uint8List exportKeyingMaterial(int length);

  Future<void> close();
}

Future<bool> _pairWithDartTls(
  String ip,
  int port,
  String pairingCode,
  AdbCrypto crypto, {
  required bool verbose,
}) async {
  _SecureSocketPairingTlsChannel? channel;
  try {
    if (verbose) {
      print('Connecting to pairing port $ip:$port...');
    }

    channel = await _SecureSocketPairingTlsChannel.connect(
      ip,
      port,
      crypto,
      verbose: verbose,
    );

    final exportedKeyMaterial = channel.exportKeyingMaterial(kTlsExporterLength);
    if (verbose) {
      print('Derived TLS exporter (${exportedKeyMaterial.length} bytes)');
    }

    final spakePassword = Uint8List.fromList([
      ...utf8.encode(pairingCode),
      ...exportedKeyMaterial,
    ]);

    final spake2 = Spake2Context.forPairing(role: Spake2Role.alice);
    final mySpakeMessage = spake2.generateMessage(spakePassword);

    if (verbose) {
      print('Sending SPAKE2 message (${mySpakeMessage.length} bytes): ${AdbPairing._toHex(mySpakeMessage)}');
    }
    await AdbPairing._writePacket(channel, kPairingPacketTypeSpake2Msg, mySpakeMessage);

    if (verbose) print('Waiting for device SPAKE2 message...');
    final theirSpakeMessage = await AdbPairing._readPacket(
      channel,
      expectedType: kPairingPacketTypeSpake2Msg,
      verbose: verbose,
    );
    if (theirSpakeMessage == null) return false;

    if (verbose) {
      print('Received SPAKE2 message (${theirSpakeMessage.length} bytes): ${AdbPairing._toHex(theirSpakeMessage)}');
    }

    final sharedKey = spake2.processMessage(theirSpakeMessage, verbose: verbose);
    final cipher = PairingCipher(sharedKey);

    final myPeerInfo = PairingPeerInfo.forClientKey(crypto).encode();
    final encryptedPeerInfo = cipher.encrypt(myPeerInfo);

    if (verbose) {
      print('Sending encrypted PeerInfo (${encryptedPeerInfo.length} bytes)...');
    }
    await AdbPairing._writePacket(channel, kPairingPacketTypePeerInfo, encryptedPeerInfo);

    if (verbose) print('Waiting for device PeerInfo...');
    final theirEncryptedPeerInfo = await AdbPairing._readPacket(
      channel,
      expectedType: kPairingPacketTypePeerInfo,
      verbose: verbose,
    );
    if (theirEncryptedPeerInfo == null) return false;

    final theirPeerInfoBytes = cipher.decrypt(theirEncryptedPeerInfo);
    final theirPeerInfo = PairingPeerInfo.decode(theirPeerInfoBytes);

    if (verbose) {
      print('Received and decrypted device PeerInfo (${theirPeerInfoBytes.length} bytes)');
      final peerString = theirPeerInfo.readNullTerminatedString();
      if (peerString != null) {
        print('Device PeerInfo type=${theirPeerInfo.type}, data=$peerString');
      } else {
        print('Device PeerInfo type=${theirPeerInfo.type}, data=<binary>');
      }
      print('Pairing successful!');
    }

    return true;
  } on FormatException catch (e) {
    if (verbose) print('Pairing protocol error: $e');
    return false;
  } catch (e) {
    if (verbose) print('Pairing failed: $e');
    return false;
  } finally {
    await channel?.close();
  }
}

final class _SecureSocketPairingTlsChannel implements PairingTlsChannel {
  _SecureSocketPairingTlsChannel(this._socket, this._keyLogCollector) : _reader = _SocketReader(_socket);

  final SecureSocket _socket;
  final _TlsKeyLogCollector _keyLogCollector;
  final _SocketReader _reader;

  static Future<_SecureSocketPairingTlsChannel> connect(
    String ip,
    int port,
    AdbCrypto crypto, {
    required bool verbose,
  }) async {
    final socket = await Socket.connect(
      InternetAddress(ip),
      port,
      timeout: const Duration(seconds: 5),
    );

    if (verbose) print('Upgrading pairing connection to TLS...');
    final securityContext = AdbCertificate.createSecurityContext(crypto.keyPair);
    final keyLogCollector = _TlsKeyLogCollector(verbose: verbose);
    final secureSocket = await SecureSocket.secure(
      socket,
      context: securityContext,
      onBadCertificate: (_) => true,
      keyLog: keyLogCollector.add,
    );
    if (verbose) print('TLS handshake complete');
    return _SecureSocketPairingTlsChannel(secureSocket, keyLogCollector);
  }

  @override
  Future<Uint8List?> readExact(int count) => _reader.readExactly(count);

  @override
  Future<void> writeAll(Uint8List bytes) async {
    _socket.add(bytes);
    await _socket.flush();
  }

  @override
  Uint8List exportKeyingMaterial(int length) {
    final session = TlsKeyLogSession.fromLines(_keyLogCollector.lines);
    return TlsExporter.deriveFromKeyLogSession(session, length: length);
  }

  @override
  Future<void> close() async {
    try {
      await _socket.close();
    } catch (_) {}
  }
}

final class _TlsKeyLogCollector {
  _TlsKeyLogCollector({required this.verbose});

  final bool verbose;
  final List<String> _lines = <String>[];

  List<String> get lines => List<String>.unmodifiable(_lines);

  void add(String line) {
    _lines.add(line);
    if (verbose) {
      final parts = line.split(RegExp(r'\s+'));
      final label = parts.isNotEmpty ? parts.first : 'UNKNOWN';
      print('Captured TLS key log label: $label');
    }
  }
}

/// Helper class to synchronously read from a socket stream.
class _SocketReader {
  _SocketReader(this._socket) {
    _socket.listen(
      (data) {
        _buffer.addAll(data);
        _dataCompleter?.complete();
        _dataCompleter = null;
      },
      onDone: () {
        _isDone = true;
        _dataCompleter?.complete();
        _dataCompleter = null;
      },
      onError: (e) {
        _error = e;
        _dataCompleter?.completeError(e);
        _dataCompleter = null;
      },
      cancelOnError: true,
    );
  }

  final Socket _socket;
  final List<int> _buffer = <int>[];
  Completer<void>? _dataCompleter;
  bool _isDone = false;
  Object? _error;

  Future<Uint8List?> readExactly(int count) async {
    while (_buffer.length < count) {
      if (_error != null) throw _error!;
      if (_isDone) return null;
      _dataCompleter ??= Completer<void>();
      await _dataCompleter!.future;
    }

    final result = Uint8List.fromList(_buffer.sublist(0, count));
    _buffer.removeRange(0, count);
    return result;
  }
}
