// Copyright 2026 Pepe Tiebosch (byme.dev). All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:example/adb_terminal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_adb/flutter_adb.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final adbCryptoProvider = Provider<AdbCrypto>((ref) => AdbCrypto(adbKeyName: 'example@flutter-adb'));

class AdbConnectionNotifier extends Notifier<AdbConnection?> {
  @override
  AdbConnection? build() {
    return null;
  }

  void setConnection(String ip, int port) {
    state?.disconnect();
    state = AdbConnection(ip, port, ref.read(adbCryptoProvider), verbose: true);
  }

  void disconnect() {
    state?.disconnect();
    state = null;
  }
}

final adbConnectionProvider = NotifierProvider<AdbConnectionNotifier, AdbConnection?>(AdbConnectionNotifier.new);

enum PairingStatus { idle, pairing, success, error }

class AdbPairingNotifier extends Notifier<PairingStatus> {
  @override
  PairingStatus build() {
    return PairingStatus.idle;
  }

  Future<void> pair(String ip, int port, String code) async {
    state = PairingStatus.pairing;
    try {
      final crypto = ref.read(adbCryptoProvider);
      final result = await AdbPairing.pair(ip, port, code, crypto, verbose: true);
      state = result ? PairingStatus.success : PairingStatus.error;
    } catch (e) {
      state = PairingStatus.error;
    }
  }

  void reset() {
    state = PairingStatus.idle;
  }
}

final adbPairingProvider = NotifierProvider<AdbPairingNotifier, PairingStatus>(AdbPairingNotifier.new);

class AdbStreamNotifier extends AsyncNotifier<AdbStream?> {
  @override
  FutureOr<AdbStream?> build() async {
    final connection = ref.watch(adbConnectionProvider);
    if (connection == null) return null;

    await connection.connect();
    return await connection.openShell();
  }
}

final adbStreamProvider = AsyncNotifierProvider<AdbStreamNotifier, AdbStream?>(AdbStreamNotifier.new);

void main() {
  final ProviderContainer container = ProviderContainer();
  WidgetsFlutterBinding.ensureInitialized();
  runApp(UncontrolledProviderScope(container: container, child: const MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Adb Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends ConsumerStatefulWidget {
  const MyHomePage({super.key});

  @override
  ConsumerState<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends ConsumerState<MyHomePage> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _ipController = TextEditingController(text: '127.0.0.1');
  final TextEditingController _portController = TextEditingController(text: '5555');
  final TextEditingController _pairingPortController = TextEditingController();
  final TextEditingController _pairingCodeController = TextEditingController();

  bool _showPairing = false;

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    _pairingPortController.dispose();
    _pairingCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          title: StreamBuilder<bool>(
            stream: ref.watch(adbConnectionProvider)?.onConnectionChanged,
            initialData: false,
            builder: (context, snapshot) {
              final connection = ref.watch(adbConnectionProvider);
              if (connection == null) {
                return const Text('ADB Flutter Example, Not connected', style: TextStyle(fontSize: 32));
              }
              if (snapshot.hasData) {
                if (snapshot.data ?? false) {
                  return Text(
                    'ADB Flutter Example, Connected to: ${connection.ip}:${connection.port}',
                    style: const TextStyle(fontSize: 32),
                  );
                } else {
                  return const Text(
                    'ADB Flutter Example, Connecting...',
                    style: TextStyle(fontSize: 32),
                  );
                }
              } else {
                return const CircularProgressIndicator();
              }
            },
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Spacer(),
                        IntrinsicWidth(
                          child: TextFormField(
                            controller: _ipController,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              hintText: 'IP Address',
                              labelText: 'IP Address',
                            ),
                            //validates valid ipv4 address
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Invalid IP';
                              }
                              if (!RegExp(r'^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$').hasMatch(value)) {
                                return 'Invalid IP';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        IntrinsicWidth(
                          child: TextFormField(
                            controller: _portController,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              hintText: 'Port',
                              labelText: 'ADB Port',
                            ),
                            // Validates valid port
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Invalid Port';
                              }
                              if (int.tryParse(value) == null ||
                                  int.tryParse(value)! < 0 ||
                                  int.tryParse(value)! > 65535) {
                                return 'Invalid Port';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        StreamBuilder<bool>(
                          stream: ref.watch(adbConnectionProvider)?.onConnectionChanged,
                          initialData: false,
                          builder: (context, snapshot) {
                            final connection = ref.watch(adbConnectionProvider);
                            final isConnected = snapshot.data ?? false;
                            return ElevatedButton(
                              onPressed: () {
                                if (connection != null) {
                                  ref.read(adbConnectionProvider.notifier).disconnect();
                                } else {
                                  if (_formKey.currentState!.validate()) {
                                    ref.read(adbConnectionProvider.notifier).setConnection(
                                          _ipController.text,
                                          int.parse(_portController.text),
                                        );
                                  }
                                }
                              },
                              child: Text(connection != null ? (isConnected ? 'Disconnect' : 'Cancel') : 'Connect'),
                            );
                          },
                        ),
                        const SizedBox(width: 10),
                        OutlinedButton(
                          onPressed: () {
                            setState(() {
                              _showPairing = !_showPairing;
                            });
                          },
                          child: Text(_showPairing ? 'Hide Pairing' : 'Pair Device'),
                        ),
                        const Spacer(),
                      ],
                    ),
                    if (_showPairing) ...[
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IntrinsicWidth(
                            child: TextFormField(
                              controller: _pairingPortController,
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                hintText: 'Pairing Port',
                                labelText: 'Pairing Port',
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          IntrinsicWidth(
                            child: TextFormField(
                              controller: _pairingCodeController,
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                hintText: '6-digit code',
                                labelText: 'Pairing Code',
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Consumer(
                            builder: (context, ref, child) {
                              final status = ref.watch(adbPairingProvider);
                              return ElevatedButton(
                                onPressed: status == PairingStatus.pairing
                                    ? null
                                    : () async {
                                        final messenger = ScaffoldMessenger.of(context);
                                        if (_pairingPortController.text.isEmpty ||
                                            _pairingCodeController.text.isEmpty) {
                                          messenger.showSnackBar(
                                            const SnackBar(content: Text('Please enter port and code')),
                                          );
                                          return;
                                        }
                                        await ref.read(adbPairingProvider.notifier).pair(
                                              _ipController.text,
                                              int.parse(_pairingPortController.text),
                                              _pairingCodeController.text,
                                            );
                                        if (!mounted) return;
                                        final finalStatus = ref.read(adbPairingProvider);
                                        if (finalStatus == PairingStatus.success) {
                                          messenger.showSnackBar(
                                            const SnackBar(content: Text('Pairing Successful!')),
                                          );
                                          setState(() => _showPairing = false);
                                        } else if (finalStatus == PairingStatus.error) {
                                          messenger.showSnackBar(
                                            const SnackBar(content: Text('Pairing Failed')),
                                          );
                                        }
                                      },
                                child: status == PairingStatus.pairing
                                    ? const SizedBox(
                                        width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                    : const Text('Pair'),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              Expanded(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 700),
                  child: ref.watch(adbStreamProvider).maybeWhen(
                      data: (adbStream) {
                        if (adbStream == null) {
                          return const Center(child: Text('Press Connect to start ADB session'));
                        }
                        return AdbTerminal(stream: adbStream);
                      },
                      loading: () => const CircularProgressIndicator(),
                      error: (error, stack) {
                        return Text('Error: $error');
                      },
                      orElse: () => const SizedBox()),
                ),
              ),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () async {
            final crypto = ref.read(adbCryptoProvider);
            final result = await Adb.sendSingleCommand(
              'monkey -p com.google.android.googlequicksearchbox 1;sleep 3;input keyevent KEYCODE_HOME',
              ip: _ipController.text,
              port: int.tryParse(_portController.text) ?? 5555,
              crypto: crypto,
            );
            debugPrint('Result: $result');
          },
          tooltip: 'Send single command',
          child: const Icon(Icons.send),
        ));
  }
}
