// Copyright 2026 Pepe Tiebosch (byme.dev). All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:math';

const int kAdbQrServiceSuffixLength = 10;
const int kAdbQrPasswordLength = 12;

final class AdbQrPairingData {
  AdbQrPairingData({
    required this.serviceName,
    required this.password,
  }) {
    if (serviceName.isEmpty) {
      throw ArgumentError.value(
          serviceName, 'serviceName', 'Service name must not be empty',);
    }
    if (password.isEmpty) {
      throw ArgumentError.value(
          password, 'password', 'Password must not be empty',);
    }
  }

  final String serviceName;
  final String password;

  String get qrPayload =>
      'WIFI:T:ADB;S:${_escapeWifiValue(serviceName)};P:${_escapeWifiValue(password)};;';

  static AdbQrPairingData generate({Random? random}) {
    final rng = random ?? Random.secure();
    return AdbQrPairingData(
      serviceName:
          'studio-${_randomChars(rng, kAdbQrServiceSuffixLength, _serviceAlphabet)}',
      password: _randomChars(rng, kAdbQrPasswordLength, _passwordAlphabet),
    );
  }

  static AdbQrPairingData parse(String qrPayload) {
    if (!qrPayload.startsWith('WIFI:')) {
      throw const FormatException('ADB QR payload must start with WIFI:');
    }

    final payload = qrPayload.substring(5);
    final fields = <String, String>{};
    for (final token in _splitWifiTokens(payload)) {
      if (token.isEmpty) continue;
      final separator = token.indexOf(':');
      if (separator <= 0) continue;
      fields[token.substring(0, separator)] =
          _unescapeWifiValue(token.substring(separator + 1));
    }

    if (fields['T'] != 'ADB') {
      throw FormatException('Unsupported QR type: ${fields['T']}');
    }

    final serviceName = fields['S'];
    final password = fields['P'];
    if (serviceName == null || serviceName.isEmpty) {
      throw const FormatException('QR payload is missing service name');
    }
    if (password == null || password.isEmpty) {
      throw const FormatException('QR payload is missing password');
    }
    return AdbQrPairingData(serviceName: serviceName, password: password);
  }
}

const String _serviceAlphabet =
    'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
const String _passwordAlphabet =
    'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#\$%^&*()_+-=,.?/[]{}';

String _randomChars(Random random, int length, String alphabet) {
  final buffer = StringBuffer();
  for (var i = 0; i < length; i++) {
    buffer.write(alphabet[random.nextInt(alphabet.length)]);
  }
  return buffer.toString();
}

String _escapeWifiValue(String value) {
  final buffer = StringBuffer();
  for (final rune in value.runes) {
    final char = String.fromCharCode(rune);
    if (char == '\\' || char == ';' || char == ':' || char == ',') {
      buffer.write('\\');
    }
    buffer.write(char);
  }
  return buffer.toString();
}

String _unescapeWifiValue(String value) {
  final buffer = StringBuffer();
  var escaping = false;
  for (final rune in value.runes) {
    final char = String.fromCharCode(rune);
    if (escaping) {
      buffer.write(char);
      escaping = false;
      continue;
    }
    if (char == '\\') {
      escaping = true;
      continue;
    }
    buffer.write(char);
  }
  if (escaping) {
    buffer.write('\\');
  }
  return buffer.toString();
}

Iterable<String> _splitWifiTokens(String payload) sync* {
  final buffer = StringBuffer();
  var escaping = false;
  for (final rune in payload.runes) {
    final char = String.fromCharCode(rune);
    if (escaping) {
      buffer.write(char);
      escaping = false;
      continue;
    }
    if (char == '\\') {
      escaping = true;
      continue;
    }
    if (char == ';') {
      yield buffer.toString();
      buffer.clear();
      continue;
    }
    buffer.write(char);
  }
  if (buffer.isNotEmpty) {
    yield buffer.toString();
  }
}
