import 'dart:typed_data';

import 'package:flutter_adb/adb_crypto.dart';
import 'package:flutter_adb/src/pairing_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _bytes(List<int> values) => Uint8List.fromList(values);

void main() {
  test('pairing header encodes and decodes', () {
    final header = PairingPacketHeader(kPairingPacketTypePeerInfo, 8208);
    final encoded = header.encode();
    final decoded = PairingPacketHeader.decode(encoded);

    expect(encoded.length, kPairingPacketHeaderSize);
    expect(decoded.type, kPairingPacketTypePeerInfo);
    expect(decoded.payloadSize, 8208);
  });

  test('peer info uses fixed-size AOSP struct', () {
    final crypto = AdbCrypto();
    final peerInfo = PairingPeerInfo.forClientKey(crypto);
    final encoded = peerInfo.encode();
    final decoded = PairingPeerInfo.decode(encoded);
    final identity = decoded.readNullTerminatedString();

    expect(encoded.length, kPairingMaxPeerInfoSize);
    expect(encoded.first, kPairingPeerInfoTypeRsaPubKey);
    expect(decoded.type, kPairingPeerInfoTypeRsaPubKey);
    expect(identity, isNotNull);
    expect(identity, contains('@'));
  });

  test('peer info string decoding stops at the first null byte', () {
    final data = Uint8List(kPairingPeerInfoDataSize);
    data.setRange(0, 12, 'device-guid\x00'.codeUnits);
    final info = PairingPeerInfo(kPairingPeerInfoTypeDeviceGuid, data);

    expect(info.readNullTerminatedString(), 'device-guid');
  });

  test('pairing cipher encrypts and decrypts with sequence-based nonces', () {
    final keyMaterial = _bytes(List<int>.generate(64, (index) => index));
    final plaintext = _bytes(List<int>.generate(64, (index) => 255 - index));

    final sender = PairingCipher(keyMaterial);
    final receiver = PairingCipher(keyMaterial);

    final firstCiphertext = sender.encrypt(plaintext);
    final secondCiphertext = sender.encrypt(plaintext);

    expect(firstCiphertext.length, sender.encryptedSize(plaintext.length));
    expect(firstCiphertext, isNot(secondCiphertext));
    expect(receiver.decrypt(firstCiphertext), plaintext);
    expect(receiver.decrypt(secondCiphertext), plaintext);
  });
}
