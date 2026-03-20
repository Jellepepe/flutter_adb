// Copyright 2026 Pepe Tiebosch (byme.dev). All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:edwards25519/edwards25519.dart' as ed;
import 'package:pointycastle/export.dart';

typedef Spake2RandomBytesSource = Uint8List Function(int length);

/// BoringSSL-compatible SPAKE2 implementation over the Ed25519 group.
///
/// Used by the ADB wireless pairing protocol (Android 11+) for
/// password-authenticated key exchange with a 6-digit pairing code.
///
/// Usage:
/// ```dart
/// final ctx = Spake2Context.forPairing(role: Spake2Role.alice);
/// final myMsg = ctx.generateMessage(utf8.encode(pairingCode));
/// // Send myMsg to peer, receive theirMsg
/// final sharedKey = ctx.processMessage(theirMsg);
/// ```
class Spake2Context {
  final Spake2Role _role;
  final Uint8List _myName;
  final Uint8List _theirName;
  final Spake2RandomBytesSource _randomBytesSource;

  bool _messageGenerated = false;
  bool _keyDerived = false;

  late final Uint8List _privateKey;
  late final Uint8List _passwordHash;
  late final Uint8List _passwordScalar;
  late final Uint8List _myMessage;

  Spake2Context(
    this._role,
    this._myName,
    this._theirName, {
    Spake2RandomBytesSource? randomBytesSource,
  }) : _randomBytesSource = randomBytesSource ?? _secureRandomBytes;

  Uint8List get privateKey => _privateKey;
  Uint8List get myMessage => _myMessage;
  Uint8List get myName => Uint8List.fromList(_myName);
  Uint8List get theirName => Uint8List.fromList(_theirName);
  Uint8List get passwordHash => _passwordHash;
  Uint8List get passwordScalar => _passwordScalar;
  Uint8List get sharedEncoded => _sharedEncoded!;
  Uint8List? _sharedEncoded;

  /// Creates a SPAKE2 context pre-configured for ADB pairing.
  ///
  /// ADB uses specific name strings and the client acts as Alice.
  factory Spake2Context.forPairing({
    required Spake2Role role,
    Spake2RandomBytesSource? randomBytesSource,
  }) {
    // ADB uses sizeof() on these string literals, so the null terminator is included.
    final clientName = utf8.encode('adb pair client\x00');
    final serverName = utf8.encode('adb pair server\x00');
    return Spake2Context(
      role,
      Uint8List.fromList(role == Spake2Role.alice ? clientName : serverName),
      Uint8List.fromList(role == Spake2Role.alice ? serverName : clientName),
      randomBytesSource: randomBytesSource,
    );
  }

  /// Generates the SPAKE2 message to send to the peer.
  ///
  /// [password] is the raw pairing code bytes (UTF-8 encoded).
  /// Returns a 32-byte compressed Ed25519 point.
  Uint8List generateMessage(Uint8List password) {
    if (_messageGenerated) throw StateError('Message already generated');
    _messageGenerated = true;

    // Generate random private scalar
    final randomScalarBytes = _generatePrivateScalar();
    final privateScalar = Ed25519.leBytesToBigInt(randomScalarBytes);
    // Multiply by cofactor (8)
    final cofactorPrivateScalar = (privateScalar << 3) % (BigInt.one << 256);
    _privateKey = Ed25519.bigIntToLeBytes(cofactorPrivateScalar, 32);

    // Compute password scalar (w) by hashing password and reducing mod L
    // BoringSSL uses the raw hash for the transcript but the reduced scalar for points.
    _passwordHash = _passwordToHash(password);
    var w = Ed25519.leBytesToBigInt(_passwordHash) % Ed25519.L;

    // The BoringSSL "password scalar hack": ensure bottom 3 bits are zero.
    // We add multiples of L (the group order) until the bottom 3 bits are zero.
    // L is odd, so adding L flips the LSB.
    if (w.isOdd) w += Ed25519.L;
    if ((w >> 1).isOdd) w += (Ed25519.L << 1);
    if ((w >> 2).isOdd) w += (Ed25519.L << 2);
    _passwordScalar = Ed25519.bigIntToLeBytes(w, 32);

    // Compute T = private_key * B (base point multiplication)
    final tPoint = Ed25519.scalarMultBase(_privateKey);

    // Choose M or N based on role
    final blindPoint = _role == Spake2Role.alice ? Ed25519.pointM : Ed25519.pointN;

    // Compute message = T + w * blind_point
    final wBlind = Ed25519.scalarMult(_passwordScalar, blindPoint);
    final messagePoint = Ed25519.pointAdd(tPoint, wBlind);

    _myMessage = Ed25519.encodePoint(messagePoint);
    return Uint8List.fromList(_myMessage);
  }

  /// Processes the peer's SPAKE2 message and derives the shared key.
  ///
  /// [theirMessage] is the 32-byte message received from the peer.
  /// [verbose] enables detailed transcript logging.
  /// Returns a 64-byte shared key.
  Uint8List processMessage(Uint8List theirMessage, {bool verbose = false}) {
    if (!_messageGenerated) throw StateError('Must call generateMessage first');
    if (_keyDerived) throw StateError('Key already derived');
    _keyDerived = true;

    // Decode their point
    final theirPoint = Ed25519.decodePoint(theirMessage);

    // Choose the opposite blind point (peer used the other one)
    final theirBlindPoint = _role == Spake2Role.alice ? Ed25519.pointN : Ed25519.pointM;

    // Unblind: remove w * theirBlindPoint from their message
    // unblinded = theirPoint - w * theirBlindPoint
    final wTheirBlind = Ed25519.scalarMult(_passwordScalar, theirBlindPoint);
    final unblinded = Ed25519.pointSub(theirPoint, wTheirBlind);

    // Compute shared secret: K = private_key * unblinded
    final sharedPoint = Ed25519.scalarMult(_privateKey, unblinded);
    _sharedEncoded = Ed25519.encodePoint(sharedPoint);
    final sharedEncoded = _sharedEncoded!;

    // Build the transcript for key derivation
    // transcript = len(myName) || myName || len(theirName) || theirName ||
    //              len(myMessage) || myMessage || len(theirMessage) || theirMessage ||
    //              len(sharedEncoded) || sharedEncoded || len(passwordScalar) || passwordScalar
    final transcript = BytesBuilder();

    // Order depends on role: Alice's message first, then Bob's
    final Uint8List firstMsg;
    final Uint8List secondMsg;
    final Uint8List firstName;
    final Uint8List secondName;

    if (_role == Spake2Role.alice) {
      firstMsg = _myMessage;
      secondMsg = theirMessage;
      firstName = _myName;
      secondName = _theirName;
    } else {
      firstMsg = theirMessage;
      secondMsg = _myMessage;
      firstName = _theirName;
      secondName = _myName;
    }

    void append(String label, Uint8List data) {
      if (verbose) print('Transcript $label (${data.length} bytes): ${_toHex(data)}');
      _appendLengthPrefixed(transcript, data);
    }

    if (verbose) print('--- SPAKE2 Transcript Debug ---');
    append('A', firstName);
    append('B', secondName);
    append('X', firstMsg);
    append('Y', secondMsg);
    append('K', sharedEncoded);
    append('w', _passwordHash);
    if (verbose) print('--- End SPAKE2 Transcript Debug ---');

    final hash = SHA512Digest();
    final transcriptBytes = transcript.toBytes();
    final key = Uint8List(64);
    hash.update(transcriptBytes, 0, transcriptBytes.length);
    hash.doFinal(key, 0);

    return key;
  }

  static String _toHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ').toUpperCase();
  }

  void _appendLengthPrefixed(BytesBuilder builder, Uint8List data) {
    // BoringSSL's spake2_update_transcript uses sizeof(size_t) = 8 bytes
    // (little-endian) on 64-bit Android devices.
    final lenBytes = ByteData(8);
    lenBytes.setUint64(0, data.length, Endian.little);
    builder.add(lenBytes.buffer.asUint8List());
    builder.add(data);
  }

  Uint8List _generatePrivateScalar() {
    final bytes = _randomBytesSource(32);
    if (bytes.length != 32) {
      throw ArgumentError('SPAKE2 random source must return exactly 32 bytes');
    }
    // Clamp for Ed25519 scalar
    bytes[0] &= 248;
    bytes[31] &= 127;
    bytes[31] |= 64;
    return bytes;
  }

  static Uint8List _passwordToHash(Uint8List password) {
    // BoringSSL: hash the password with SHA-512.
    final digest = SHA512Digest();
    final hash = Uint8List(64);
    digest.update(password, 0, password.length);
    digest.doFinal(hash, 0);
    return hash;
  }

  static Uint8List _secureRandomBytes(int length) {
    final random = Random.secure();
    final bytes = Uint8List(length);
    for (int i = 0; i < length; i++) {
      bytes[i] = random.nextInt(256);
    }
    return bytes;
  }
}

/// SPAKE2 roles. In ADB pairing, the client (initiator) is Alice.
enum Spake2Role { alice, bob }

/// Ed25519 group operations for SPAKE2.
class Ed25519 {
  /// Ed25519 group order
  static final BigInt L = BigInt.parse(
    '7237005577332262213973186563042994240857116359379907606001950938285454250989',
  );

  static final ed.Point basePoint = ed.Point.newGeneratorPoint();

  static final ed.Point pointM = _decodePointFromBytes([
    0x5a,
    0xda,
    0x7e,
    0x4b,
    0xf6,
    0xdd,
    0xd9,
    0xad,
    0xb6,
    0x62,
    0x6d,
    0x32,
    0x13,
    0x1c,
    0x6b,
    0x5c,
    0x51,
    0xa1,
    0xe3,
    0x47,
    0xa3,
    0x47,
    0x8f,
    0x53,
    0xcf,
    0xcf,
    0x44,
    0x1b,
    0x88,
    0xee,
    0xd1,
    0x2e,
  ]);

  static final ed.Point pointN = _decodePointFromBytes([
    0x10,
    0xe3,
    0xdf,
    0x0a,
    0xe3,
    0x7d,
    0x8e,
    0x7a,
    0x99,
    0xb5,
    0xfe,
    0x74,
    0xb4,
    0x46,
    0x72,
    0x10,
    0x3d,
    0xbd,
    0xdc,
    0xbd,
    0x06,
    0xaf,
    0x68,
    0x0d,
    0x71,
    0x32,
    0x9a,
    0x11,
    0x69,
    0x3b,
    0xc7,
    0x78,
  ]);

  static ed.Point _decodePointFromBytes(List<int> bytes) {
    return decodePoint(Uint8List.fromList(bytes));
  }

  static ed.Point scalarMult(Uint8List scalar, ed.Point point) {
    var result = ed.Point.newIdentityPoint();
    var temp = _copyPoint(point);

    for (int i = 0; i < 256; i++) {
      final bit = (scalar[i >> 3] >> (i & 7)) & 1;
      if (bit == 1) {
        result = pointAdd(result, temp);
      }
      temp = pointDouble(temp);
    }
    return result;
  }

  static ed.Point scalarMultBase(Uint8List scalar) {
    return scalarMult(scalar, basePoint);
  }

  static ed.Point pointAdd(ed.Point p1, ed.Point p2) {
    final result = ed.Point.zero();
    result.add(p1, p2);
    return result;
  }

  static ed.Point pointDouble(ed.Point point) {
    final result = ed.Point.zero();
    result.add(point, point);
    return result;
  }

  static ed.Point pointSub(ed.Point p1, ed.Point p2) {
    final result = ed.Point.zero();
    result.subtract(p1, p2);
    return result;
  }

  static Uint8List encodePoint(ed.Point point) {
    return Uint8List.fromList(point.Bytes());
  }

  static ed.Point decodePoint(Uint8List encoded) {
    final point = ed.Point.zero();
    point.setBytes(encoded);
    return point;
  }

  static BigInt leBytesToBigInt(Uint8List bytes) {
    BigInt result = BigInt.zero;
    for (int i = bytes.length - 1; i >= 0; i--) {
      result = (result << 8) + BigInt.from(bytes[i]);
    }
    return result;
  }

  static Uint8List bigIntToLeBytes(BigInt value, int length) {
    final result = Uint8List(length);
    var temp = value;
    for (int i = 0; i < length; i++) {
      result[i] = (temp & BigInt.from(0xFF)).toInt();
      temp >>= 8;
    }
    return result;
  }

  static ed.Point _copyPoint(ed.Point point) {
    final result = ed.Point.zero();
    result.set(point);
    return result;
  }
}
