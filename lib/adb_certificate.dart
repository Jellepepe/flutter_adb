// Copyright 2026 Pepe Tiebosch (byme.dev). All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// Utilities for generating self-signed X.509 certificates and PEM-encoded
/// keys for use with Dart's [SecurityContext] during ADB TLS connections.
class AdbCertificate {
  /// Creates a [SecurityContext] suitable for the pairing TLS channel.
  static SecurityContext createSecurityContext(
    AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey> keyPair,
  ) {
    final certPem = generateSelfSignedCertificatePem(keyPair);
    final keyPem = encodePrivateKeyToPem(keyPair.privateKey);

    final context = SecurityContext(withTrustedRoots: false);
    context.useCertificateChainBytes(utf8.encode(certPem));
    context.usePrivateKeyBytes(utf8.encode(keyPem));
    return context;
  }

  /// Creates a [SecurityContext] for the post-pairing ADB TLS (STLS) transport.
  ///
  /// The certificate issuer/subject is shaped to match adbd's client-CA hinting
  /// (`O=AdbKey-0, CN=<SHA256(pubkey)>`) so `dart:io` can select the client
  /// certificate without AOSP's custom cert-selection callback.
  static SecurityContext createTransportSecurityContext(
    AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey> keyPair,
  ) {
    final certPem = generateTransportCertificatePem(keyPair);
    final keyPem = encodePrivateKeyToPem(keyPair.privateKey);

    final context = SecurityContext(withTrustedRoots: false);
    context.useCertificateChainBytes(utf8.encode(certPem));
    context.usePrivateKeyBytes(utf8.encode(keyPem));
    return context;
  }

  /// Generates a self-signed X.509 v3 certificate in PEM format.
  static String generateSelfSignedCertificatePem(
    AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey> keyPair,
  ) {
    final certDer = _buildSelfSignedCertificate(
      keyPair,
      subject: const <_X509NameAttribute>[
        _X509NameAttribute([2, 5, 4, 3], 'adb'),
      ],
      issuer: const <_X509NameAttribute>[
        _X509NameAttribute([2, 5, 4, 3], 'adb'),
      ],
    );
    return _derToPem(certDer, 'CERTIFICATE');
  }

  /// Generates the STLS client certificate in PEM format.
  static String generateTransportCertificatePem(
    AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey> keyPair,
  ) {
    final fingerprint = _adbTlsFingerprintHex(keyPair.publicKey);
    final name = <_X509NameAttribute>[
      const _X509NameAttribute([2, 5, 4, 10], 'AdbKey-0'),
      _X509NameAttribute([2, 5, 4, 3], fingerprint),
    ];
    final certDer = _buildSelfSignedCertificate(
      keyPair,
      subject: name,
      issuer: name,
    );
    return _derToPem(certDer, 'CERTIFICATE');
  }

  /// Encodes an RSA private key to PKCS#8 PEM format.
  static String encodePrivateKeyToPem(RSAPrivateKey privateKey) {
    final pkcs8Der = _encodePrivateKeyPkcs8(privateKey);
    return _derToPem(pkcs8Der, 'PRIVATE KEY');
  }

  static Uint8List _buildSelfSignedCertificate(
    AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey> keyPair, {
    required List<_X509NameAttribute> subject,
    required List<_X509NameAttribute> issuer,
  }) {
    final publicKey = keyPair.publicKey;
    final privateKey = keyPair.privateKey;
    final tbsCert = _buildTbsCertificate(
      publicKey,
      subject: subject,
      issuer: issuer,
    );

    final signer = RSASigner(SHA256Digest(), '0609608648016503040201');
    signer.init(true, PrivateKeyParameter<RSAPrivateKey>(privateKey));
    final signature = signer.generateSignature(tbsCert);

    return _asn1Sequence([
      tbsCert,
      _sha256WithRsaAlgorithmIdentifier(),
      _asn1BitString(signature.bytes),
    ]);
  }

  static Uint8List _buildTbsCertificate(
    RSAPublicKey publicKey, {
    required List<_X509NameAttribute> subject,
    required List<_X509NameAttribute> issuer,
  }) {
    final version = _asn1Explicit(0, _asn1Integer(BigInt.from(2)));
    final serial = _asn1Integer(_deterministicSerial(publicKey));
    final signatureAlgo = _sha256WithRsaAlgorithmIdentifier();
    final issuerName = _buildName(issuer);
    final validity = _asn1Sequence([
      _asn1UtcTime(DateTime.utc(2024, 1, 1, 0, 0, 0)),
      _asn1UtcTime(DateTime.utc(2049, 12, 31, 23, 59, 59)),
    ]);
    final subjectName = _buildName(subject);
    final spki = _encodeSubjectPublicKeyInfo(publicKey);

    return _asn1Sequence([
      version,
      serial,
      signatureAlgo,
      issuerName,
      validity,
      subjectName,
      spki,
    ]);
  }

  static BigInt _deterministicSerial(RSAPublicKey publicKey) {
    final digest = SHA256Digest();
    final modulusBytes = _bigIntToSignedBytes(publicKey.modulus!);
    final exponentBytes = _bigIntToSignedBytes(publicKey.publicExponent!);
    final input = Uint8List.fromList([...modulusBytes, ...exponentBytes]);
    digest.update(input, 0, input.length);
    final out = Uint8List(digest.digestSize);
    digest.doFinal(out, 0);
    out[0] &= 0x7F;
    if (out.every((b) => b == 0)) {
      out[out.length - 1] = 1;
    }
    return _unsignedBytesToBigInt(out);
  }

  static String _adbTlsFingerprintHex(RSAPublicKey publicKey) {
    final digest = SHA256Digest();
    final spkiDer = _encodeSubjectPublicKeyInfo(publicKey);
    digest.update(spkiDer, 0, spkiDer.length);
    final out = Uint8List(digest.digestSize);
    digest.doFinal(out, 0);
    return out.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
  }

  static Uint8List _encodeSubjectPublicKeyInfo(RSAPublicKey publicKey) {
    final algoId = _asn1Sequence([
      _asn1ObjectIdentifier([1, 2, 840, 113549, 1, 1, 1]),
      _asn1Null(),
    ]);

    final rsaPubKey = _asn1Sequence([
      _asn1Integer(publicKey.modulus!),
      _asn1Integer(publicKey.publicExponent!),
    ]);

    return _asn1Sequence([algoId, _asn1BitString(rsaPubKey)]);
  }

  static Uint8List _encodePrivateKeyPkcs8(RSAPrivateKey privateKey) {
    final version = _asn1Integer(BigInt.zero);

    final algoId = _asn1Sequence([
      _asn1ObjectIdentifier([1, 2, 840, 113549, 1, 1, 1]),
      _asn1Null(),
    ]);

    final rsaPrivKey = _asn1Sequence([
      _asn1Integer(BigInt.zero),
      _asn1Integer(privateKey.modulus!),
      _asn1Integer(privateKey.publicExponent!),
      _asn1Integer(privateKey.privateExponent!),
      _asn1Integer(privateKey.p!),
      _asn1Integer(privateKey.q!),
      _asn1Integer(privateKey.privateExponent! % (privateKey.p! - BigInt.one)),
      _asn1Integer(privateKey.privateExponent! % (privateKey.q! - BigInt.one)),
      _asn1Integer(privateKey.q!.modInverse(privateKey.p!)),
    ]);

    return _asn1Sequence([version, algoId, _asn1OctetString(rsaPrivKey)]);
  }

  static Uint8List _sha256WithRsaAlgorithmIdentifier() {
    return _asn1Sequence([
      _asn1ObjectIdentifier([1, 2, 840, 113549, 1, 1, 11]),
      _asn1Null(),
    ]);
  }

  static Uint8List _buildName(List<_X509NameAttribute> attributes) {
    final rdns = <Uint8List>[];
    for (final attribute in attributes) {
      final valueBytes = utf8.encode(attribute.value);
      final attr = _asn1Sequence([
        _asn1ObjectIdentifier(attribute.oid),
        _asn1Wrap(0x0C, Uint8List.fromList(valueBytes)),
      ]);
      rdns.add(_asn1Set([attr]));
    }
    return _asn1Sequence(rdns);
  }

  static Uint8List _asn1Sequence(List<Uint8List> elements) {
    return _asn1Constructed(0x30, elements);
  }

  static Uint8List _asn1Set(List<Uint8List> elements) {
    return _asn1Constructed(0x31, elements);
  }

  static Uint8List _asn1Constructed(int tag, List<Uint8List> elements) {
    final content = BytesBuilder();
    for (final e in elements) {
      content.add(e);
    }
    return _asn1Wrap(tag, content.toBytes());
  }

  static Uint8List _asn1Explicit(int tagNumber, Uint8List content) {
    return _asn1Wrap(0xA0 | tagNumber, content);
  }

  static Uint8List _asn1Integer(BigInt value) {
    final bytes = _bigIntToSignedBytes(value);
    return _asn1Wrap(0x02, Uint8List.fromList(bytes));
  }

  static Uint8List _asn1BitString(Uint8List data) {
    final content = Uint8List(data.length + 1);
    content[0] = 0x00;
    content.setAll(1, data);
    return _asn1Wrap(0x03, content);
  }

  static Uint8List _asn1OctetString(Uint8List data) {
    return _asn1Wrap(0x04, data);
  }

  static Uint8List _asn1Null() {
    return Uint8List.fromList([0x05, 0x00]);
  }

  static Uint8List _asn1UtcTime(DateTime dt) {
    final s = '${_pad2(dt.year % 100)}${_pad2(dt.month)}${_pad2(dt.day)}${_pad2(dt.hour)}${_pad2(dt.minute)}${_pad2(dt.second)}Z';
    return _asn1Wrap(0x17, ascii.encode(s));
  }

  static Uint8List _asn1ObjectIdentifier(List<int> components) {
    if (components.length < 2) {
      throw ArgumentError('OID must have at least 2 components');
    }
    final bytes = <int>[components[0] * 40 + components[1]];
    for (int i = 2; i < components.length; i++) {
      _encodeOidComponent(bytes, components[i]);
    }
    return _asn1Wrap(0x06, Uint8List.fromList(bytes));
  }

  static void _encodeOidComponent(List<int> bytes, int value) {
    if (value < 128) {
      bytes.add(value);
    } else {
      final encoded = <int>[];
      encoded.add(value & 0x7F);
      value >>= 7;
      while (value > 0) {
        encoded.add((value & 0x7F) | 0x80);
        value >>= 7;
      }
      bytes.addAll(encoded.reversed);
    }
  }

  static Uint8List _asn1Wrap(int tag, Uint8List content) {
    final lengthBytes = _asn1Length(content.length);
    final result = Uint8List(1 + lengthBytes.length + content.length);
    result[0] = tag;
    result.setAll(1, lengthBytes);
    result.setAll(1 + lengthBytes.length, content);
    return result;
  }

  static Uint8List _asn1Length(int length) {
    if (length < 128) {
      return Uint8List.fromList([length]);
    }
    int numBytes = 0;
    int temp = length;
    while (temp > 0) {
      numBytes++;
      temp >>= 8;
    }
    final result = Uint8List(1 + numBytes);
    result[0] = 0x80 | numBytes;
    for (int i = numBytes; i > 0; i--) {
      result[i] = length & 0xFF;
      length >>= 8;
    }
    return result;
  }

  static List<int> _bigIntToSignedBytes(BigInt value) {
    if (value == BigInt.zero) return [0];

    final isNegative = value.isNegative;
    final absValue = value.abs();
    final hex = absValue.toRadixString(16);
    final paddedHex = hex.length.isOdd ? '0$hex' : hex;

    final bytes = <int>[];
    for (int i = 0; i < paddedHex.length; i += 2) {
      bytes.add(int.parse(paddedHex.substring(i, i + 2), radix: 16));
    }

    if (!isNegative) {
      if (bytes[0] & 0x80 != 0) {
        bytes.insert(0, 0);
      }
    } else {
      for (int i = 0; i < bytes.length; i++) {
        bytes[i] = (~bytes[i]) & 0xFF;
      }
      int carry = 1;
      for (int i = bytes.length - 1; i >= 0 && carry > 0; i--) {
        int sum = bytes[i] + carry;
        bytes[i] = sum & 0xFF;
        carry = sum >> 8;
      }
      if (bytes[0] & 0x80 == 0) {
        bytes.insert(0, 0xFF);
      }
    }

    return bytes;
  }

  static BigInt _unsignedBytesToBigInt(Uint8List bytes) {
    BigInt result = BigInt.zero;
    for (final byte in bytes) {
      result = (result << 8) | BigInt.from(byte);
    }
    return result;
  }

  static String _pad2(int v) => v.toString().padLeft(2, '0');

  static String _derToPem(Uint8List der, String label) {
    final b64 = base64Encode(der);
    final lines = <String>['-----BEGIN $label-----'];
    for (int i = 0; i < b64.length; i += 64) {
      lines.add(b64.substring(i, i + 64 > b64.length ? b64.length : i + 64));
    }
    lines.add('-----END $label-----');
    return lines.join('\n');
  }
}

final class _X509NameAttribute {
  const _X509NameAttribute(this.oid, this.value);

  final List<int> oid;
  final String value;
}
