import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_adb/spake2.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _bytes(List<int> values) => Uint8List.fromList(values);

void main() {
  test('ADB pairing names include null terminators', () {
    final context = Spake2Context.forPairing(
      role: Spake2Role.alice,
      randomBytesSource: (_) => Uint8List(32),
    );

    expect(context.myName, utf8.encode('adb pair client\x00'));
    expect(context.theirName, utf8.encode('adb pair server\x00'));
  });

  test('deterministic random source yields deterministic SPAKE2 message', () {
    final randomBytes = List<int>.generate(32, (index) => index + 1);
    final password = _bytes('123456'.codeUnits);

    final first = Spake2Context.forPairing(
      role: Spake2Role.alice,
      randomBytesSource: (_) => _bytes(randomBytes),
    );
    final second = Spake2Context.forPairing(
      role: Spake2Role.alice,
      randomBytesSource: (_) => _bytes(randomBytes),
    );

    expect(first.generateMessage(password), second.generateMessage(password));
  });

  test('password scalar hack clears the low three bits', () {
    final context = Spake2Context.forPairing(
      role: Spake2Role.alice,
      randomBytesSource: (_) => _bytes(List<int>.generate(32, (index) => index + 1)),
    );

    context.generateMessage(_bytes('123456'.codeUnits));

    expect(context.passwordScalar[0] & 0x07, 0);
  });

  test('generated message is 32 bytes', () {
    final context = Spake2Context.forPairing(
      role: Spake2Role.alice,
      randomBytesSource: (_) => _bytes(List<int>.generate(32, (index) => index + 1)),
    );

    final message = context.generateMessage(_bytes('123456'.codeUnits));

    expect(message, hasLength(32));
  });
}
