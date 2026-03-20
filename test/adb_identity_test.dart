import 'dart:convert';

import 'package:flutter_adb/adb_certificate.dart';
import 'package:flutter_adb/adb_crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ADB public key payload includes configured identity metadata', () {
    final crypto = AdbCrypto(adbKeyName: 'alice@workstation');

    final payload = utf8.decode(crypto.getAdbPublicKeyPayload(), allowMalformed: false);

    expect(payload, endsWith(' alice@workstation\x00'));
  });

  test('ADB public key payload sanitizes empty and whitespace-heavy names', () {
    final crypto = AdbCrypto(adbKeyName: '   alice laptop   ');

    final payload = utf8.decode(crypto.getAdbPublicKeyPayload(), allowMalformed: false);

    expect(payload, contains(' alice_laptop\x00'));
    expect(payload, isNot(contains(' unknown@unknown')));
  });

  test('Self-signed certificate PEM is deterministic for the same keypair', () {
    final crypto = AdbCrypto(adbKeyName: 'alice@workstation');

    final certPemA = AdbCertificate.generateSelfSignedCertificatePem(crypto.keyPair);
    final certPemB = AdbCertificate.generateSelfSignedCertificatePem(crypto.keyPair);

    expect(certPemA, certPemB);
  });

  test('Private key PEM is deterministic for the same keypair', () {
    final crypto = AdbCrypto(adbKeyName: 'alice@workstation');

    final keyPemA = AdbCertificate.encodePrivateKeyToPem(crypto.keyPair.privateKey);
    final keyPemB = AdbCertificate.encodePrivateKeyToPem(crypto.keyPair.privateKey);

    expect(keyPemA, keyPemB);
  });

  test('Stored keypair round-trips through AdbCrypto storage helpers', () {
    final original = AdbCrypto(adbKeyName: 'alice@workstation');

    final stored = original.exportKeyPairForStorage();
    final restoredKeyPair = AdbCrypto.keyPairFromStorageMap(stored);
    final restored = AdbCrypto(
      keyPair: restoredKeyPair,
      adbKeyName: 'alice@workstation',
    );

    expect(restored.getRawAdbPublicKey(), original.getRawAdbPublicKey());
    expect(
      utf8.decode(restored.getAdbPublicKeyPayload(), allowMalformed: false),
      utf8.decode(original.getAdbPublicKeyPayload(), allowMalformed: false),
    );
  });
}
