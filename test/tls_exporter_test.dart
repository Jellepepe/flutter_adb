import 'dart:typed_data';

import 'package:flutter_adb/src/tls_exporter.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _hex(String value) {
  final bytes = Uint8List(value.length ~/ 2);
  for (var i = 0; i < value.length; i += 2) {
    bytes[i ~/ 2] = int.parse(value.substring(i, i + 2), radix: 16);
  }
  return bytes;
}

void main() {
  test('parses EXPORTER_SECRET key log line', () {
    final line = TlsKeyLogLine.parse(
      'EXPORTER_SECRET e26fb0db22409b963498a22168d8a51a2064ddfa811115f559204c7b1ecb5310 dc944062996917d8677db4bca2c560b60e87d037441852f84813e69ad5157c18',
    );

    expect(line.label, kTlsExporterKeyLogLabel);
    expect(
      line.clientRandom,
      _hex('e26fb0db22409b963498a22168d8a51a2064ddfa811115f559204c7b1ecb5310'),
    );
    expect(
      line.secret,
      _hex('dc944062996917d8677db4bca2c560b60e87d037441852f84813e69ad5157c18'),
    );
  });

  test('rejects mixed-session key log lines', () {
    expect(
      () => TlsKeyLogSession.fromLines([
        'EXPORTER_SECRET 00 dc944062996917d8677db4bca2c560b60e87d037441852f84813e69ad5157c18',
        'CLIENT_TRAFFIC_SECRET_0 11 4473a8b849f1f2a1829327940f4b79b33e60096cfacbb2200e572a65af53d7a6',
      ]),
      throwsFormatException,
    );
  });

  test('derives adb exporter bytes from EXPORTER_SECRET oracle fixture', () {
    final session = TlsKeyLogSession.fromLines([
      'CLIENT_HANDSHAKE_TRAFFIC_SECRET e26fb0db22409b963498a22168d8a51a2064ddfa811115f559204c7b1ecb5310 02b1f6943ab11ae1183992d6be8e1c9405bab5c0c79b94c2d9f6393c66f5e24e',
      'SERVER_HANDSHAKE_TRAFFIC_SECRET e26fb0db22409b963498a22168d8a51a2064ddfa811115f559204c7b1ecb5310 ee42bac385900ce7f1538c6d47360a3d052fc33c959a754d727d13d6881053a6',
      'CLIENT_TRAFFIC_SECRET_0 e26fb0db22409b963498a22168d8a51a2064ddfa811115f559204c7b1ecb5310 4473a8b849f1f2a1829327940f4b79b33e60096cfacbb2200e572a65af53d7a6',
      'SERVER_TRAFFIC_SECRET_0 e26fb0db22409b963498a22168d8a51a2064ddfa811115f559204c7b1ecb5310 c4f4c38ec5ccba5ba01596f00aa5356bed536a48050255290bcc70ba86951e2e',
      'EXPORTER_SECRET e26fb0db22409b963498a22168d8a51a2064ddfa811115f559204c7b1ecb5310 dc944062996917d8677db4bca2c560b60e87d037441852f84813e69ad5157c18',
    ]);

    final exporter = TlsExporter.deriveFromKeyLogSession(session, length: 64);

    expect(
      exporter,
      _hex('eba59f1e5515d59842c7af7285840461ff40ac89856cf5b680efcb088d3c5a39f1d8427a73ec554a4ea1951ed7a4a8612d8b485b76ff2cf0a30aee805212e625'),
    );
  });
}

