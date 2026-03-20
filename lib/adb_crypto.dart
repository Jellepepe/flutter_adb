// Copyright 2026 Pepe Tiebosch (byme.dev). All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

class AdbCrypto {
  /// The RSA signature padding used by ADB
  // ignore: non_constant_identifier_names
  static List<int> SIGNATURE_PADDING = [
    0x00,
    0x01,
    for (int i = 0; i < 218; i++) 0xff,
    0x00,
    0x30,
    0x21,
    0x30,
    0x09,
    0x06,
    0x05,
    0x2b,
    0x0e,
    0x03,
    0x02,
    0x1a,
    0x05,
    0x00,
    0x04,
    0x14,
  ];

  static const int KEY_LENGTH_BITS = 2048;
  static const int KEY_LENGTH_BYTES = KEY_LENGTH_BITS ~/ 8;
  static const int KEY_LENGTH_WORDS = KEY_LENGTH_BYTES ~/ 4;

  late final AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey> _keyPair;
  final String adbKeyName;

  AdbCrypto({
    AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey>? keyPair,
    String? adbKeyName,
  })  : _keyPair = keyPair ?? generateAdbKeyPair(),
        adbKeyName = _sanitizeAdbKeyName(adbKeyName ?? _defaultAdbKeyName());

  /// The RSA key pair used for ADB authentication and TLS.
  AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey> get keyPair => _keyPair;

  @override
  String toString() {
    return 'AdbCrypto: Modulus: ${_keyPair.publicKey.modulus}, Public Exponent: ${_keyPair.publicKey.publicExponent}, Name: $adbKeyName';
  }

  static Uint8List convertRsaPublicKeyToAdbFormat(RSAPublicKey publicKey) {
    assert(publicKey.modulus != null && publicKey.publicExponent != null, 'invalid public key');
    BigInt r32 = BigInt.zero.setBit(32);
    BigInt n = publicKey.modulus!;
    BigInt r = BigInt.zero.setBit(KEY_LENGTH_WORDS * 32);
    BigInt rr = r.modPow(BigInt.two, n);
    BigInt rem = n.remainder(r32);
    BigInt n0inv = rem.modInverse(r32);

    List<int> nDataList = List.filled(8, 0, growable: true);
    nDataList.addAll(n.toBytes());
    nDataList.addAll(rr.toBytes());
    nDataList.addAll(publicKey.publicExponent!.toBytes());
    while (nDataList.length < 524) {
      nDataList.add(0);
    }

    Uint8List nData2 = Uint8List.fromList(nDataList);

    nData2.buffer.asByteData().setUint32(0, KEY_LENGTH_WORDS, Endian.little);
    nData2.buffer.asByteData().setUint32(4, (n0inv * BigInt.from(-1)).toInt(), Endian.little);

    return nData2;
  }

  /// Returns the raw 524-byte ADB public key structure.
  Uint8List getRawAdbPublicKey() {
    return convertRsaPublicKeyToAdbFormat(_keyPair.publicKey);
  }

  /// Returns the base64-encoded ADB public key string with metadata (for USB AUTH).
  Uint8List getAdbPublicKeyPayload() {
    final adbPublicKey = getRawAdbPublicKey();
    final keyString = '${base64Encode(adbPublicKey)} $adbKeyName\x00';
    return utf8.encode(keyString);
  }

  Uint8List signAdbTokenPayload(Uint8List payload) {
    final signer = RSASigner(SHA1Digest(), '06052b0e03021a');
    signer.init(true, PrivateKeyParameter<RSAPrivateKey>(_keyPair.privateKey));

    final paddedPayload = Uint8List.fromList([...SIGNATURE_PADDING, ...payload]);
    return signer.generateSignature(paddedPayload).bytes;
  }

  static AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey> generateAdbKeyPair() {
    final random = Random.secure();
    final seed = Uint8List.fromList(
      List<int>.generate(32, (_) => random.nextInt(256)),
    );
    final secureRandom = SecureRandom('Fortuna')
      ..seed(KeyParameter(seed));
    final keyGen = RSAKeyGenerator();

    keyGen.init(
      ParametersWithRandom(
        RSAKeyGeneratorParameters(BigInt.parse('65537'), KEY_LENGTH_BITS, 64),
        secureRandom,
      ),
    );

    final pair = keyGen.generateKeyPair();
    return AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey>(pair.publicKey, pair.privateKey);
  }

  static String _defaultAdbKeyName() {
    final env = Platform.environment;
    final user = env['USERNAME'] ?? env['USER'] ?? 'flutter';
    String host;
    try {
      host = Platform.localHostname;
    } catch (_) {
      host = 'flutter-adb';
    }
    return '$user@$host';
  }

  static String _sanitizeAdbKeyName(String value) {
    final trimmed = value.trim().replaceAll(RegExp(r'\s+'), '_');
    return trimmed.isEmpty ? 'flutter@flutter-adb' : trimmed;
  }
}

extension BigIntExtension on BigInt {
  /// Little-endian byte representation of the number
  Uint8List toBytes() {
    var size = (bitLength / 8).ceil();
    var result = Uint8List(size);

    for (var i = 0; i < size; i++) {
      result[i] = (this >> i * 8).toUnsigned(8).toInt();
    }

    return result;
  }

  /// Set the bit to 1 at the given position
  BigInt setBit(int bit) {
    return this | BigInt.one << bit;
  }
}
