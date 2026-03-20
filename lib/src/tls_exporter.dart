// Copyright 2026 Pepe Tiebosch (byme.dev). All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

const String kTlsExporterKeyLogLabel = 'EXPORTER_SECRET';
const String kAdbTlsExporterLabel = 'adb-label\x00';

final class TlsKeyLogLine {
  TlsKeyLogLine({
    required this.label,
    required this.clientRandom,
    required this.secret,
  });

  final String label;
  final Uint8List clientRandom;
  final Uint8List secret;

  static TlsKeyLogLine parse(String line) {
    final parts = line.trim().split(RegExp(r'\s+'));
    if (parts.length != 3) {
      throw FormatException('Invalid TLS key log line format');
    }

    return TlsKeyLogLine(
      label: parts[0],
      clientRandom: _hexToBytes(parts[1]),
      secret: _hexToBytes(parts[2]),
    );
  }
}

final class TlsKeyLogSession {
  TlsKeyLogSession(this._linesByLabel);

  final Map<String, TlsKeyLogLine> _linesByLabel;

  factory TlsKeyLogSession.fromLines(Iterable<String> lines) {
    final parsed = <String, TlsKeyLogLine>{};
    Uint8List? clientRandom;

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      final parsedLine = TlsKeyLogLine.parse(line);
      clientRandom ??= parsedLine.clientRandom;
      if (!_bytesEqual(clientRandom, parsedLine.clientRandom)) {
        throw FormatException('TLS key log contains multiple sessions');
      }
      parsed[parsedLine.label] = parsedLine;
    }

    if (parsed.isEmpty) {
      throw FormatException('TLS key log is empty');
    }

    return TlsKeyLogSession(parsed);
  }

  TlsKeyLogLine requireLabel(String label) {
    final line = _linesByLabel[label];
    if (line == null) {
      throw FormatException('Missing TLS key log label: $label');
    }
    return line;
  }
}

final class TlsExporter {
  TlsExporter._();

  static Uint8List deriveFromKeyLogSession(
    TlsKeyLogSession session, {
    required int length,
    String label = kAdbTlsExporterLabel,
    Uint8List? context,
  }) {
    final exporterSecret = session.requireLabel(kTlsExporterKeyLogLabel).secret;
    final digest = _digestForSecret(exporterSecret);
    final emptyTranscriptHash = _hash(_digestForSecret(exporterSecret), Uint8List(0));
    final contextHash = _hash(_digestForSecret(exporterSecret), context ?? Uint8List(0));

    final derivedSecret = _hkdfExpandLabel(
      secret: exporterSecret,
      label: label,
      context: emptyTranscriptHash,
      length: digest.digestSize,
      digest: digest,
    );

    return _hkdfExpandLabel(
      secret: derivedSecret,
      label: 'exporter',
      context: contextHash,
      length: length,
      digest: _digestForSecret(exporterSecret),
    );
  }

  static Digest _digestForSecret(Uint8List secret) {
    return switch (secret.length) {
      32 => SHA256Digest(),
      48 => SHA384Digest(),
      _ => throw UnsupportedError(
          'Unsupported TLS exporter secret length: ${secret.length}',
        ),
    };
  }

  static Uint8List _hkdfExpandLabel({
    required Uint8List secret,
    required String label,
    required Uint8List context,
    required int length,
    required Digest digest,
  }) {
    final hkdfLabel = BytesBuilder()
      ..add(_uint16(length))
      ..add(_opaque8(utf8.encode('tls13 $label')))
      ..add(_opaque8(context));

    return _hkdfExpand(
      prk: secret,
      info: hkdfLabel.toBytes(),
      length: length,
      digest: digest,
    );
  }

  static Uint8List _hkdfExpand({
    required Uint8List prk,
    required Uint8List info,
    required int length,
    required Digest digest,
  }) {
    final hmac = HMac(digest, _hmacBlockLength(digest))..init(KeyParameter(prk));
    final blockCount = (length / digest.digestSize).ceil();
    final output = BytesBuilder();
    var previous = Uint8List(0);

    for (var blockIndex = 1; blockIndex <= blockCount; blockIndex++) {
      final input = BytesBuilder()
        ..add(previous)
        ..add(info)
        ..add([blockIndex]);
      hmac.reset();
      final inputBytes = input.toBytes();
      hmac.update(inputBytes, 0, inputBytes.length);
      previous = Uint8List(hmac.macSize);
      hmac.doFinal(previous, 0);
      output.add(previous);
    }

    return Uint8List.fromList(output.toBytes().sublist(0, length));
  }

  static int _hmacBlockLength(Digest digest) {
    return switch (digest.digestSize) {
      32 => 64,
      48 => 128,
      _ => throw UnsupportedError('Unsupported HMAC digest size: '),
    };
  }

  static Uint8List _hash(Digest digest, Uint8List input) {
    digest.reset();
    digest.update(input, 0, input.length);
    final result = Uint8List(digest.digestSize);
    digest.doFinal(result, 0);
    return result;
  }

  static Uint8List _uint16(int value) {
    final data = ByteData(2)..setUint16(0, value, Endian.big);
    return data.buffer.asUint8List();
  }

  static Uint8List _opaque8(List<int> bytes) {
    if (bytes.length > 255) {
      throw ArgumentError('TLS exporter field too large: ${bytes.length}');
    }
    return Uint8List.fromList([bytes.length, ...bytes]);
  }
}

Uint8List _hexToBytes(String hex) {
  final normalized = hex.trim();
  if (normalized.length.isOdd) {
    throw FormatException('Invalid hex length');
  }

  final bytes = Uint8List(normalized.length ~/ 2);
  for (var index = 0; index < normalized.length; index += 2) {
    bytes[index ~/ 2] = int.parse(normalized.substring(index, index + 2), radix: 16);
  }
  return bytes;
}

bool _bytesEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
