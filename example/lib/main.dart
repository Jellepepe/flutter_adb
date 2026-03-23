// Copyright 2026 Pepe Tiebosch (byme.dev). All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:example/adb_terminal.dart';
import 'package:example/example_storage.dart';
import 'package:example/qr_pairing_panel.dart';
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
    await state?.disconnect();
    final crypto = await ref.read(adbCryptoProvider.future);
    state = AdbConnection(ip, port, crypto, verbose: true);
    await state?.connect();
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

enum QrPairingStatus { idle, pairing, success, error }

final class QrPairingSession {
  const QrPairingSession({
    this.status = QrPairingStatus.idle,
    this.qrData,
    this.result,
  });

  final QrPairingStatus status;
  final AdbQrPairingData? qrData;
  final AdbPairingResult? result;
}

class QrPairingNotifier extends Notifier<QrPairingSession> {
  @override
  QrPairingSession build() {
    return const QrPairingSession();
  }

  Future<void> pair() async {
    final qrData = AdbQrPairingData.generate();
    state = QrPairingSession(status: QrPairingStatus.pairing, qrData: qrData);

    try {
      final crypto = await ref.read(adbCryptoProvider.future);
      final result = await AdbPairing.pairWithQr(qrData, crypto, verbose: true);
      state = QrPairingSession(
        status: result.success ? QrPairingStatus.success : QrPairingStatus.error,
        qrData: qrData,
        result: result,
      );
    } catch (e) {
      state = QrPairingSession(
        status: QrPairingStatus.error,
        qrData: qrData,
        result: AdbPairingResult(success: false, errorMessage: '$e'),
      );
    }
  }

  void reset() {
    state = const QrPairingSession();
  }
}

final qrPairingProvider = NotifierProvider<QrPairingNotifier, QrPairingSession>(QrPairingNotifier.new);

class AdbStreamNotifier extends AsyncNotifier<AdbStream?> {
  @override
  FutureOr<AdbStream?> build() async {
    final connection = ref.watch(adbConnectionProvider);
    if (connection == null) return null;

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
  bool _showQrPairing = false;
  bool _isCreatingConnection = false;

  void _toggleCodePairing() {
    setState(() {
      _showPairing = !_showPairing;
      if (_showPairing) {
        _showQrPairing = false;
        ref.read(qrPairingProvider.notifier).reset();
      }
    });
  }

  void _toggleQrPairing() {
    setState(() {
      _showQrPairing = !_showQrPairing;
      if (_showQrPairing) {
        _showPairing = false;
        ref.read(adbPairingProvider.notifier).reset();
      } else {
        ref.read(qrPairingProvider.notifier).reset();
      }
    });
  }

  void _closeQrPairing() {
    setState(() => _showQrPairing = false);
    ref.read(qrPairingProvider.notifier).reset();
  }

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
      await ref.read(adbConnectionProvider.notifier).setConnection(ip, port);
      await ref.read(savedDevicesProvider.notifier).saveDevice(ip: ip, port: port);
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

  Future<void> _startQrPairing() async {
    await ref.read(qrPairingProvider.notifier).pair();
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final session = ref.read(qrPairingProvider);
    final result = session.result;
    if (session.status == QrPairingStatus.success) {
      final endpoint = result?.connectEndpoint;
      if (endpoint != null) {
        _ipController.text = endpoint.host;
        _portController.text = endpoint.port.toString();
        await ref.read(adbConnectionProvider.notifier).setConnection(
              endpoint.host,
              endpoint.port,
            );
        await ref.read(savedDevicesProvider.notifier).saveDevice(
              ip: endpoint.host,
              port: endpoint.port,
            );
        unawaited(_refreshSavedDeviceLabel(endpoint.host, endpoint.port));
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            endpoint == null
                ? 'QR pairing successful. Resolve the connect endpoint manually if needed.'
                : 'QR pairing successful. Device saved and connecting automatically.',
          ),
        ),
      );
      _closeQrPairing();
    } else if (session.status == QrPairingStatus.error) {
      messenger.showSnackBar(
        SnackBar(content: Text(result?.errorMessage ?? 'QR pairing failed')),
      );
    }
  }

  void _loadSavedDevice(SavedAdbDevice device) {
    _ipController.text = device.ip;
    _portController.text = device.port.toString();
  }

  Future<void> _refreshSavedDeviceLabel(String ip, int port) async {
    try {
      final connection = ref.read(adbConnectionProvider);
      if (connection == null) {
        return;
      }
      final stream = await connection.openShell();
      final command = 'getprop ro.product.manufacturer && getprop ro.product.model;exit\n';
      await stream.writeString(command);
      final combined = await stream.onPayload
          .fold('', (prev, chunk) => prev + utf8.decode(chunk))
          .timeout(const Duration(seconds: 10), onTimeout: () => '');
      stream.close();
      // Strip the echoed command prefix if present
      final output = combined.contains(command.trim()) ? combined.split(command.trim()).last : combined;
      final parts = output.trim().split('\n');
      final manufacturer = parts.isNotEmpty ? parts[0].trim() : '';
      final model = parts.length > 1 ? parts[1].trim() : '';

      final label = _buildDeviceLabel(manufacturer, model, ip, port);
      await ref.read(savedDevicesProvider.notifier).saveDevice(
            ip: ip,
            port: port,
            label: label,
          );
    } catch (e) {
      // Best-effort label enrichment for the example UI.
      debugPrint('Failed to refresh device label for $ip:$port, error: $e');
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

  String? _qrStatusText(QrPairingSession session) {
    switch (session.status) {
      case QrPairingStatus.idle:
        return 'The host app will wait on mDNS for the requested studio-* pairing service after the device scans the QR code.';
      case QrPairingStatus.pairing:
        return 'Waiting for the device to scan the QR code and publish the requested pairing service over mDNS.';
      case QrPairingStatus.success:
        final connect = session.result?.connectEndpoint;
        if (connect == null) {
          return 'Pairing succeeded. No connect endpoint was discovered automatically.';
        }
        return 'Pairing succeeded. Next connect target: ${connect.host}:${connect.port}';
      case QrPairingStatus.error:
        return session.result?.errorMessage ?? 'QR pairing failed.';
    }
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
                    onPressed: _toggleCodePairing,
                    child: Text(_showPairing ? 'Hide Code Pairing' : 'Pair With Code'),
                  ),
                  OutlinedButton(
                    onPressed: _toggleQrPairing,
                    child: Text(_showQrPairing ? 'Hide QR Pairing' : 'Pair With QR'),
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
    final qrSession = ref.watch(qrPairingProvider);
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
        title: StreamBuilder<bool>(
          stream: ref.watch(adbConnectionProvider)?.onConnectionChanged,
          initialData: false,
          builder: (context, snapshot) {
            final connection = ref.watch(adbConnectionProvider);
            if (connection == null) {
              return Text(_showQrPairing ? 'QR Pairing' : 'ADB Flutter Example, Not connected',
                  style: const TextStyle(fontSize: 20));
            }
            if (snapshot.hasData) {
              if (snapshot.data ?? false) {
                return Text(
                  'ADB Flutter Example, Connected to: ${connection.ip}:${connection.port}',
                  style: const TextStyle(fontSize: 20),
                );
              }
              return const Text(
                'ADB Flutter Example, Connecting...',
                style: TextStyle(fontSize: 20),
              );
            }
            return const CircularProgressIndicator();
          },
        ),
      ),
      body: _showQrPairing
          ? QrPairingPanel(
              pairingData: qrSession.qrData,
              isPairing: qrSession.status == QrPairingStatus.pairing,
              statusText: _qrStatusText(qrSession),
              onStart: cryptoAsync.isLoading ? null : _startQrPairing,
              onCancel: _closeQrPairing,
            )
          : Padding(
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
      floatingActionButton: activeConnection == null || _showQrPairing
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
