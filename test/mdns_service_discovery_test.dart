import 'dart:async';
import 'dart:io';

import 'package:flutter_adb/src/mdns_service_discovery.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('resolvePairingService returns the exact requested instance', () async {
    final discovery = AdbMdnsServiceDiscovery(
      lookup: _FakeLookup(
        ptrRecords: {
          kAdbTlsPairingServiceType: [
            'studio-other._adb-tls-pairing._tcp.local',
            'studio-target._adb-tls-pairing._tcp.local',
          ],
        },
        srvRecords: {
          'studio-target._adb-tls-pairing._tcp.local': [
            const MdnsSrvRecord(target: 'target.local', port: 37123),
          ],
        },
        addressRecords: {
          'target.local': [InternetAddress('192.168.1.44')],
        },
      ),
    );

    final endpoint = await discovery.resolvePairingService(
      'studio-target',
      timeout: const Duration(milliseconds: 50),
    );

    expect(endpoint, isNotNull);
    expect(endpoint!.serviceName, 'studio-target');
    expect(endpoint.preferredHost, '192.168.1.44');
    expect(endpoint.port, 37123);
  });

  test('resolveConnectService prefers the matching host and IPv4 address', () async {
    final discovery = AdbMdnsServiceDiscovery(
      lookup: _FakeLookup(
        ptrRecords: {
          kAdbTlsConnectServiceType: [
            'adb-guid123-random._adb-tls-connect._tcp.local',
          ],
        },
        srvRecords: {
          'adb-guid123-random._adb-tls-connect._tcp.local': [
            const MdnsSrvRecord(target: 'phone.local', port: 45555),
          ],
        },
        addressRecords: {
          'phone.local': [
            InternetAddress('fe80::1'),
            InternetAddress('192.168.1.55'),
          ],
        },
      ),
    );

    final endpoint = await discovery.resolveConnectService(
      deviceGuid: 'guid123',
      preferredAddress: InternetAddress('192.168.1.55'),
      timeout: const Duration(milliseconds: 50),
    );

    expect(endpoint, isNotNull);
    expect(endpoint!.preferredHost, '192.168.1.55');
    expect(endpoint.port, 45555);
  });

  test('resolveConnectService falls back to preferred host when guid name does not match', () async {
    final discovery = AdbMdnsServiceDiscovery(
      lookup: _FakeLookup(
        ptrRecords: {
          kAdbTlsConnectServiceType: [
            'not-the-guid._adb-tls-connect._tcp.local',
          ],
        },
        srvRecords: {
          'not-the-guid._adb-tls-connect._tcp.local': [
            const MdnsSrvRecord(target: 'phone.local', port: 5555),
          ],
        },
        addressRecords: {
          'phone.local': [InternetAddress('192.168.1.88')],
        },
      ),
    );

    final endpoint = await discovery.resolveConnectService(
      deviceGuid: 'guid123',
      preferredAddress: InternetAddress('192.168.1.88'),
      timeout: const Duration(milliseconds: 50),
    );

    expect(endpoint, isNotNull);
    expect(endpoint!.preferredHost, '192.168.1.88');
    expect(endpoint.port, 5555);
  });

  test('resolvePairingService returns null on timeout', () async {
    final discovery = AdbMdnsServiceDiscovery(lookup: _FakeLookup());

    final endpoint = await discovery.resolvePairingService(
      'studio-missing',
      timeout: const Duration(milliseconds: 20),
    );

    expect(endpoint, isNull);
  });
}

final class _FakeLookup implements MdnsRecordLookup {
  _FakeLookup({
    this.ptrRecords = const {},
    this.srvRecords = const {},
    this.addressRecords = const {},
  });

  final Map<String, List<String>> ptrRecords;
  final Map<String, List<MdnsSrvRecord>> srvRecords;
  final Map<String, List<InternetAddress>> addressRecords;

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  Stream<String> lookupPtr(String serviceType) async* {
    for (final record in ptrRecords[serviceType] ?? const <String>[]) {
      yield record;
    }
  }

  @override
  Future<List<InternetAddress>> lookupAddresses(String host) async {
    return addressRecords[host] ?? const <InternetAddress>[];
  }

  @override
  Future<List<MdnsSrvRecord>> lookupSrv(String domainName) async {
    return srvRecords[domainName] ?? const <MdnsSrvRecord>[];
  }
}
