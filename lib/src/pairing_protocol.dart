// Copyright 2026 Pepe Tiebosch (byme.dev). All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_adb/adb_crypto.dart';
import 'package:pointycastle/export.dart';

const int kPairingPacketVersion = 1;
const int kPairingPacketHeaderSize = 6;
const int kPairingPacketTypeSpake2Msg = 0;
const int kPairingPacketTypePeerInfo = 1;
const int kPairingMaxPeerInfoSize = 8192;
const int kPairingPeerInfoDataSize = kPairingMaxPeerInfoSize - 1;
const int kPairingPeerInfoTypeRsaPubKey = 0;
const int kPairingPeerInfoTypeDeviceGuid = 1;
const int kTlsExporterLength = 64;
const String kPairingAes128GcmInfo = 'adb pairing_auth aes-128-gcm key';

final class PairingPacketHeader {
  PairingPacketHeader(this.type, this.payloadSize);

  final int type;
  final int payloadSize;

  Uint8List encode() {
    final header = ByteData(kPairingPacketHeaderSize);
    header.setUint8(0, kPairingPacketVersion);
    header.setUint8(1, type);
    header.setUint32(2, payloadSize, Endian.big);
    return header.buffer.asUint8List();
  }

  static PairingPacketHeader decode(Uint8List bytes) {
    if (bytes.length != kPairingPacketHeaderSize) {
      throw FormatException('Invalid pairing packet header size: ${bytes.length}');
    }
    final view = ByteData.sublistView(bytes);
    final version = view.getUint8(0);
    if (version != kPairingPacketVersion) {
      throw FormatException('Unsupported pairing packet version: $version');
    }
    return PairingPacketHeader(
      view.getUint8(1),
      view.getUint32(2, Endian.big),
    );
  }
}

final class PairingPeerInfo {
  PairingPeerInfo(this.type, this.data);

  final int type;
  final Uint8List data;

  Uint8List encode() {
    if (data.length > kPairingPeerInfoDataSize) {
      throw ArgumentError('PeerInfo data too large: ${data.length}');
    }

    final bytes = Uint8List(kPairingMaxPeerInfoSize);
    bytes[0] = type;
    bytes.setRange(1, 1 + data.length, data);
    return bytes;
  }

  static PairingPeerInfo decode(Uint8List bytes) {
    if (bytes.length != kPairingMaxPeerInfoSize) {
      throw FormatException('Invalid PeerInfo size: ${bytes.length}');
    }
    return PairingPeerInfo(bytes[0], Uint8List.fromList(bytes.sublist(1)));
  }

  static PairingPeerInfo forClientKey(AdbCrypto crypto) {
    final payload = crypto.getAdbPublicKeyPayload();
    if (payload.length > kPairingPeerInfoDataSize) {
      throw ArgumentError('ADB public key payload too large: ${payload.length}');
    }
    return PairingPeerInfo(kPairingPeerInfoTypeRsaPubKey, payload);
  }

  String? readNullTerminatedString() {
    final end = data.indexOf(0);
    final content = end == -1 ? data : data.sublist(0, end);
    if (content.isEmpty) return null;
    return utf8.decode(content, allowMalformed: true);
  }
}

final class PairingCipher {
  PairingCipher(Uint8List keyMaterial) : _key = Uint8List.fromList(_deriveKey(keyMaterial));

  final Uint8List _key;
  int _encryptSequence = 0;
  int _decryptSequence = 0;

  Uint8List encrypt(Uint8List plaintext) {
    final nonce = _buildNonce(_encryptSequence++);
    final cipher = GCMBlockCipher(AESEngine());
    cipher.init(true, AEADParameters(KeyParameter(_key), 128, nonce, Uint8List(0)));

    final output = Uint8List(plaintext.length + 16);
    var len = cipher.processBytes(plaintext, 0, plaintext.length, output, 0);
    len += cipher.doFinal(output, len);
    return Uint8List.fromList(output.sublist(0, len));
  }

  Uint8List decrypt(Uint8List ciphertext) {
    final nonce = _buildNonce(_decryptSequence++);
    final cipher = GCMBlockCipher(AESEngine());
    cipher.init(false, AEADParameters(KeyParameter(_key), 128, nonce, Uint8List(0)));

    final output = Uint8List(ciphertext.length);
    var len = cipher.processBytes(ciphertext, 0, ciphertext.length, output, 0);
    len += cipher.doFinal(output, len);
    return Uint8List.fromList(output.sublist(0, len));
  }

  int encryptedSize(int plaintextLength) => plaintextLength + 16;

  static Uint8List _deriveKey(Uint8List keyMaterial) {
    final derivator = HKDFKeyDerivator(SHA256Digest());
    derivator.init(HkdfParameters(keyMaterial, 16, null, utf8.encode(kPairingAes128GcmInfo)));
    return derivator.process(Uint8List(0));
  }

  static Uint8List _buildNonce(int sequence) {
    final nonce = Uint8List(12);
    final view = ByteData.sublistView(nonce);
    view.setUint64(0, sequence, Endian.little);
    return nonce;
  }
}
