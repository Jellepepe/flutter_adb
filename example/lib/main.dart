// Copyright 2026 Pepe Tiebosch (byme.dev). All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:example/adb_terminal.dart';
import 'package:example/example_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_adb/flutter_adb.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final exampleStorageProvider = Provider<ExampleStorage>((ref) => ExampleStorage());

final adbCryptoProvider = FutureProvider<AdbCrypto>((ref) async {
  return ref.read(exampleStorageProvider).loadOrCreateCrypto();
});

class SavedDevicesNotifier extends AsyncNotifier<List<SavedAdbDevice>> {
  ExampleStorage get _storage => ref.read(exampleStorageProvider);

  @override
  Future<List<SavedAdbDevice>> build() {
    return _storage.loadSavedDevices();
  }

  Future<void> saveDevice({
    required String ip,
    required int port,
    String? label,
  }) async {
    await _storage.saveDevice(ip: ip, port: port, label: label);
    state = AsyncData(await _storage.loadSavedDevices());
  }

  Future<void> deleteDevice(String id) async {
    await _storage.deleteDevice(id);
    state = AsyncData(await _storage.loadSavedDevices());
  }
}

final savedDevicesProvider = AsyncNotifierProvider<SavedDevicesNotifier, List<SavedAdbDevice>>(
  SavedDevicesNotifier.new,
);

class AdbConnectionNotifier extends Notifier<AdbConnection?> {
  @override
  AdbConnection? build() {
    return null;
  }

  Future<void> setConnection(String ip, int port) async {
    state?.disconnect();
    final crypto = await ref.read(adbCryptoProvider.future);
    state = AdbConnection(ip, port, crypto, verbose: true);
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
      final crypto = await ref.read(adbCryptoProvider.future);
      final result = await AdbPairing.pair(ip, port, code, crypto, verbose: true);
      state = result ? PairingStatus.success : PairingStatus.error;
    } catch (_) {
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
  bool _isCreatingConnection = false;

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    _pairingPortController.dispose();
    _pairingCodeController.dispose();
    super.dispose();
  }

  Future<void> _connectToCurrentTarget() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isCreatingConnection = true);
    try {
      final ip = _ipController.text;
      final port = int.parse(_portController.text);
      await ref.read(adbConnectionProvider.notifier).setConnection(
            ip,
            port,
          );
      await ref.read(savedDevicesProvider.notifier).saveDevice(
            ip: ip,
            port: port,
          );
      unawaited(_refreshSavedDeviceLabel(ip, port));
    } finally {
      if (mounted) {
        setState(() => _isCreatingConnection = false);
      }
    }
  }

  Future<void> _pairCurrentTarget() async {
    final messenger = ScaffoldMessenger.of(context);
    if (_pairingPortController.text.isEmpty || _pairingCodeController.text.isEmpty) {
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
      await ref.read(savedDevicesProvider.notifier).saveDevice(
            ip: _ipController.text,
            port: int.tryParse(_portController.text) ?? 5555,
          );
      messenger.showSnackBar(
        const SnackBar(content: Text('Pairing Successful!')),
      );
      setState(() => _showPairing = false);
    } else if (finalStatus == PairingStatus.error) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Pairing Failed')),
      );
    }
  }

  void _loadSavedDevice(SavedAdbDevice device) {
    _ipController.text = device.ip;
    _portController.text = device.port.toString();
  }

  Future<void> _refreshSavedDeviceLabel(String ip, int port) async {
    try {
      final crypto = await ref.read(adbCryptoProvider.future);
      final manufacturer = await Adb.sendSingleCommand(
        'getprop ro.product.manufacturer',
        ip: ip,
        port: port,
        crypto: crypto,
      );
      final model = await Adb.sendSingleCommand(
        'getprop ro.product.model',
        ip: ip,
        port: port,
        crypto: crypto,
      );

      final label = _buildDeviceLabel(manufacturer, model, ip, port);
      await ref.read(savedDevicesProvider.notifier).saveDevice(
            ip: ip,
            port: port,
            label: label,
          );
    } catch (_) {
      // Best-effort label enrichment for the example UI.
    }
  }

  String _buildDeviceLabel(String manufacturer, String model, String ip, int port) {
    final cleanManufacturer = manufacturer.trim();
    final cleanModel = model.trim();
    final combined = [cleanManufacturer, cleanModel]
        .where((value) => value.isNotEmpty)
        .join(' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (combined.isEmpty) {
      return '$ip:$port';
    }
    return '$combined ($ip)';
  }

  Widget _buildConnectionControls(AsyncValue<AdbCrypto> cryptoAsync) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        cryptoAsync.when(
          data: (crypto) => Text('Stored key: ${crypto.adbKeyName}', style: Theme.of(context).textTheme.titleMedium),
          loading: () => const LinearProgressIndicator(),
          error: (error, stack) => Text('Failed to load stored key: $error'),
        ),
        const SizedBox(height: 16),
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 220,
                    child: TextFormField(
                      controller: _ipController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'IP Address',
                        labelText: 'IP Address',
                      ),
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
                  SizedBox(
                    width: 160,
                    child: TextFormField(
                      controller: _portController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'Port',
                        labelText: 'ADB Port',
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Invalid Port';
                        }
                        if (int.tryParse(value) == null || int.parse(value) < 0 || int.parse(value) > 65535) {
                          return 'Invalid Port';
                        }
                        return null;
                      },
                    ),
                  ),
                  StreamBuilder<bool>(
                    stream: ref.watch(adbConnectionProvider)?.onConnectionChanged,
                    initialData: false,
                    builder: (context, snapshot) {
                      final connection = ref.watch(adbConnectionProvider);
                      final isConnected = snapshot.data ?? false;
                      return ElevatedButton(
                        onPressed: cryptoAsync.isLoading || _isCreatingConnection
                            ? null
                            : () async {
                                if (connection != null) {
                                  ref.read(adbConnectionProvider.notifier).disconnect();
                                } else {
                                  await _connectToCurrentTarget();
                                }
                              },
                        child: _isCreatingConnection
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : Text(connection != null ? (isConnected ? 'Disconnect' : 'Cancel') : 'Connect'),
                      );
                    },
                  ),
                  OutlinedButton(
                    onPressed: () {
                      setState(() {
                        _showPairing = !_showPairing;
                      });
                    },
                    child: Text(_showPairing ? 'Hide Pairing' : 'Pair Device'),
                  ),
                ],
              ),
              if (_showPairing) ...[
                const SizedBox(height: 20),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    SizedBox(
                      width: 180,
                      child: TextFormField(
                        controller: _pairingPortController,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: 'Pairing Port',
                          labelText: 'Pairing Port',
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 180,
                      child: TextFormField(
                        controller: _pairingCodeController,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: '6-digit code',
                          labelText: 'Pairing Code',
                        ),
                      ),
                    ),
                    Consumer(
                      builder: (context, ref, child) {
                        final status = ref.watch(adbPairingProvider);
                        return ElevatedButton(
                          onPressed:
                              status == PairingStatus.pairing || cryptoAsync.isLoading ? null : _pairCurrentTarget,
                          child: status == PairingStatus.pairing
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
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
      ],
    );
  }

  Widget _buildSavedConnections(AsyncValue<List<SavedAdbDevice>> savedDevicesAsync) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Saved Connections', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        savedDevicesAsync.when(
          data: (devices) {
            if (devices.isEmpty) {
              return const Text('No saved connections yet.');
            }
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: devices.map((device) {
                return InputChip(
                  label: Text(device.label),
                  onPressed: () => _loadSavedDevice(device),
                  onDeleted: () => ref.read(savedDevicesProvider.notifier).deleteDevice(device.id),
                  tooltip: '${device.ip}:${device.port}',
                );
              }).toList(),
            );
          },
          loading: () => const LinearProgressIndicator(),
          error: (error, stack) => Text('Failed to load saved connections: $error'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cryptoAsync = ref.watch(adbCryptoProvider);
    final savedDevicesAsync = ref.watch(savedDevicesProvider);
    final activeConnection = ref.watch(adbConnectionProvider);

    final terminal = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 700),
      child: ref.watch(adbStreamProvider).maybeWhen(
            data: (adbStream) {
              if (adbStream == null) {
                return const Center(child: Text('Press Connect to start ADB session'));
              }
              return AdbTerminal(
                stream: adbStream,
                onDisconnect: () => ref.read(adbConnectionProvider.notifier).disconnect(),
              );
            },
            loading: () => Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                const Text('Connecting to ADB...'),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => ref.read(adbConnectionProvider.notifier).disconnect(),
                  child: const Text('Cancel'),
                ),
              ],
            ),
            error: (error, stack) => Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Error: $error', style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => ref.read(adbConnectionProvider.notifier).disconnect(),
                  child: const Text('Go Back'),
                ),
              ],
            ),
            orElse: () => const SizedBox(),
          ),
    );

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [],
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
              }
              return const Text(
                'ADB Flutter Example, Connecting...',
                style: TextStyle(fontSize: 32),
              );
            }
            return const CircularProgressIndicator();
          },
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final showSidebar = activeConnection == null && constraints.maxWidth >= 1100;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (activeConnection == null) ...[
                  _buildConnectionControls(cryptoAsync),
                  const SizedBox(height: 20),
                ],
                Expanded(
                  child: showSidebar
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 260,
                              child: SingleChildScrollView(
                                child: _buildSavedConnections(savedDevicesAsync),
                              ),
                            ),
                            const SizedBox(width: 24),
                            Expanded(child: Center(child: terminal)),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (activeConnection == null) ...[
                              _buildSavedConnections(savedDevicesAsync),
                              const SizedBox(height: 20),
                            ],
                            Expanded(child: Center(child: terminal)),
                          ],
                        ),
                ),
              ],
            );
          },
        ),
      ),
      floatingActionButton: activeConnection == null
          ? null
          : FloatingActionButton(
              onPressed: cryptoAsync.isLoading
                  ? null
                  : () async {
                      final crypto = await ref.read(adbCryptoProvider.future);
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
            ),
    );
  }
}
