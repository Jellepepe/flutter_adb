import 'dart:convert';

import 'package:flutter_adb/flutter_adb.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class SavedAdbDevice {
  SavedAdbDevice({
    required this.id,
    required this.label,
    required this.ip,
    required this.port,
    required this.updatedAt,
  });

  final String id;
  final String label;
  final String ip;
  final int port;
  final DateTime updatedAt;

  factory SavedAdbDevice.fromJson(Map<String, dynamic> json) {
    return SavedAdbDevice(
      id: json['id'] as String,
      label: json['label'] as String,
      ip: json['ip'] as String,
      port: json['port'] as int,
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'label': label,
      'ip': ip,
      'port': port,
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}

class ExampleStorage {
  static const _cryptoStorageKey = 'example.adb_crypto';
  static const _devicesPrefsKey = 'example.saved_adb_devices';
  static const _defaultKeyName = 'example@flutter-adb';

  final FlutterSecureStorage _secureStorage;

  ExampleStorage({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  Future<AdbCrypto> loadOrCreateCrypto() async {
    final stored = await _secureStorage.read(key: _cryptoStorageKey);
    if (stored != null && stored.isNotEmpty) {
      final decoded = jsonDecode(stored) as Map<String, dynamic>;
      final adbKeyName = decoded['adbKeyName'] as String? ?? _defaultKeyName;
      final keyPair = AdbCrypto.keyPairFromStorageMap(
        decoded['keyPair'] as Map<String, dynamic>,
      );
      return AdbCrypto(keyPair: keyPair, adbKeyName: adbKeyName);
    }

    final crypto = AdbCrypto(adbKeyName: _defaultKeyName);
    await _secureStorage.write(
      key: _cryptoStorageKey,
      value: jsonEncode(<String, dynamic>{
        'adbKeyName': crypto.adbKeyName,
        'keyPair': crypto.exportKeyPairForStorage(),
      }),
    );
    return crypto;
  }

  Future<List<SavedAdbDevice>> loadSavedDevices() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_devicesPrefsKey) ?? const <String>[];
    final devices = raw
        .map((entry) => SavedAdbDevice.fromJson(jsonDecode(entry) as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return devices;
  }

  Future<void> saveDevice({
    required String ip,
    required int port,
    String? label,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = await loadSavedDevices();
    final id = '$ip:$port';
    SavedAdbDevice? existingDevice;
    for (final entry in existing) {
      if (entry.id == id) {
        existingDevice = entry;
        break;
      }
    }
    final device = SavedAdbDevice(
      id: id,
      label: label ?? existingDevice?.label ?? id,
      ip: ip,
      port: port,
      updatedAt: DateTime.now().toUtc(),
    );

    final updated = <SavedAdbDevice>[
      device,
      ...existing.where((entry) => entry.id != id),
    ];

    await prefs.setStringList(
      _devicesPrefsKey,
      updated.map((entry) => jsonEncode(entry.toJson())).toList(),
    );
  }

  Future<void> deleteDevice(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final updated = (await loadSavedDevices()).where((entry) => entry.id != id).toList();
    await prefs.setStringList(
      _devicesPrefsKey,
      updated.map((entry) => jsonEncode(entry.toJson())).toList(),
    );
  }
}
