import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_adb/adb_stream.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

final StateProvider<String> shellBufferProvider = StateProvider((ref) => '');

final Provider<List<String>> shellOutput = Provider((ref) {
  List<String> shellLines = ref.watch(shellBufferProvider).split('\n');
  return shellLines.sublist(max(0, shellLines.length - 101), shellLines.length - 1);
});

final Provider<String> shellCurLine = Provider((ref) {
  List<String> shellLines = ref.watch(shellBufferProvider).split('\n');
  return shellLines[shellLines.length - 1];
});

class AdbTerminal extends ConsumerStatefulWidget {
  const AdbTerminal({super.key, required this.stream});

  final AdbStream stream;

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _AdbTerminalState();
}

class _AdbTerminalState extends ConsumerState<AdbTerminal> {
  final TextEditingController _controller = TextEditingController();

  bool isClosed = false;

  late StreamSubscription<Uint8List> _shellSubscription;

  @override
  void initState() {
    super.initState();
    _shellSubscription = widget.stream.onPayload.listen(
        (value) => ref.read(shellBufferProvider.notifier).state += utf8.decode(value),
        onDone: () => setState(() => isClosed = true));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (ref.watch(shellBufferProvider).isEmpty) {
      widget.stream.writeString('\n');
    }
  }

  @override
  void dispose() {
    _shellSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: SingleChildScrollView(
            reverse: true,
            child: Text(
              ref.watch(shellOutput).join('\n'),
              style: GoogleFonts.robotoMono(
                color: isClosed ? Colors.grey : Colors.black,
              ),
            ),
          ),
        ),
        Row(
          children: [
            Text(
              ref.watch(shellCurLine),
              style: GoogleFonts.robotoMono(
                color: isClosed ? Colors.grey : Colors.black,
              ),
            ),
            Expanded(
              child: TextField(
                controller: _controller,
                enabled: !isClosed,
                decoration: InputDecoration(
                  border: const UnderlineInputBorder(),
                  hintText: isClosed ? 'Shell closed' : 'echo Hello, world!',
                  hintStyle: GoogleFonts.robotoMono(
                    color: Colors.grey,
                  ),
                ),
                onSubmitted: (value) {
                  widget.stream.writeString('$value\n');
                  _controller.clear();
                },
              ),
            ),
            IconButton(
              icon: const Icon(Icons.send),
              onPressed: isClosed
                  ? null
                  : () {
                      widget.stream.writeString('${_controller.text}\n');
                      _controller.clear();
                    },
            ),
          ],
        ),
      ],
    );
  }
}
