// Copyright 2026 Pepe Tiebosch (byme.dev). All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:multicast_dns/multicast_dns.dart';

const String kAdbTlsPairingServiceType = '_adb-tls-pairing._tcp.local';
const String kAdbTlsConnectServiceType = '_adb-tls-connect._tcp.local';

final class AdbDiscoveredServiceEndpoint {
  const AdbDiscoveredServiceEndpoint({
    required this.serviceName,
    required this.host,
    required this.port,
    required this.addresses,
  });

  final String serviceName;
  final String host;
  final int port;
  final List<InternetAddress> addresses;

  InternetAddress? get preferredAddress {
    for (final address in addresses) {
      if (address.type == InternetAddressType.IPv4) {
        return address;
      }
    }
    return addresses.isEmpty ? null : addresses.first;
  }

  String get preferredHost => preferredAddress?.address ?? host;
}

abstract interface class MdnsRecordLookup {
  Future<void> start();

  Future<void> stop();

  Stream<String> lookupPtr(String serviceType);

  Future<List<MdnsSrvRecord>> lookupSrv(String domainName);

  Future<List<InternetAddress>> lookupAddresses(String host);
}

final class MdnsSrvRecord {
  const MdnsSrvRecord({
    required this.target,
    required this.port,
  });

  final String target;
  final int port;
}

final class AdbMdnsServiceDiscovery {
  AdbMdnsServiceDiscovery({MdnsRecordLookup? lookup}) : _lookup = lookup ?? MulticastDnsRecordLookup();

  final MdnsRecordLookup _lookup;

  Future<AdbDiscoveredServiceEndpoint?> resolvePairingService(
    String serviceName, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    await _lookup.start();
    try {
      await for (final domainName in _boundedPtrLookup(kAdbTlsPairingServiceType, timeout)) {
        if (_extractServiceName(domainName, kAdbTlsPairingServiceType) != serviceName) {
          continue;
        }
        final endpoint = await _resolveDomainName(domainName, serviceName);
        if (endpoint != null) {
          return endpoint;
        }
      }
      return null;
    } finally {
      await _lookup.stop();
    }
  }

  Future<AdbDiscoveredServiceEndpoint?> resolveConnectService({
    String? deviceGuid,
    InternetAddress? preferredAddress,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    await _lookup.start();
    try {
      AdbDiscoveredServiceEndpoint? guidMatch;
      AdbDiscoveredServiceEndpoint? hostMatch;
      AdbDiscoveredServiceEndpoint? fallback;
      await for (final domainName in _boundedPtrLookup(kAdbTlsConnectServiceType, timeout)) {
        final serviceName = _extractServiceName(domainName, kAdbTlsConnectServiceType);
        if (serviceName == null) continue;

        final endpoint = await _resolveDomainName(domainName, serviceName);
        if (endpoint == null) {
          continue;
        }

        if (deviceGuid != null && serviceName.startsWith('adb-$deviceGuid')) {
          guidMatch ??= endpoint;
        }
        if (preferredAddress != null &&
            endpoint.addresses.any(
              (address) => address.address == preferredAddress.address,
            )) {
          hostMatch ??= endpoint;
        }
        fallback ??= endpoint;
      }
      return guidMatch ?? hostMatch ?? fallback;
    } finally {
      await _lookup.stop();
    }
  }

  Stream<String> _boundedPtrLookup(String serviceType, Duration timeout) {
    final seen = <String>{};
    return _lookup.lookupPtr(serviceType).transform(
      StreamTransformer<String, String>.fromHandlers(
        handleData: (domainName, sink) {
          if (seen.add(domainName)) {
            sink.add(domainName);
          }
        },
      ),
    ).timeout(timeout, onTimeout: (sink) => sink.close());
  }

  Future<AdbDiscoveredServiceEndpoint?> _resolveDomainName(
    String domainName,
    String serviceName,
  ) async {
    final srvRecords = await _lookup.lookupSrv(domainName);
    for (final srv in srvRecords) {
      final addresses = await _lookup.lookupAddresses(srv.target);
      final sortedAddresses = [...addresses]..sort((a, b) {
          if (a.type == b.type) {
            return a.address.compareTo(b.address);
          }
          return a.type == InternetAddressType.IPv4 ? -1 : 1;
        });
      return AdbDiscoveredServiceEndpoint(
        serviceName: serviceName,
        host: srv.target,
        port: srv.port,
        addresses: sortedAddresses,
      );
    }
    return null;
  }
}

final class MulticastDnsRecordLookup implements MdnsRecordLookup {
  MulticastDnsRecordLookup({MDnsClient? client})
      : _client = client ?? MDnsClient(rawDatagramSocketFactory: _bindSocket);

  final MDnsClient _client;
  bool _started = false;

  static Future<RawDatagramSocket> _bindSocket(
    dynamic host,
    int port, {
    bool reuseAddress = false,
    bool reusePort = false,
    int ttl = 1,
  }) {
    return RawDatagramSocket.bind(
      host,
      port,
      reuseAddress: reuseAddress,
      reusePort: Platform.isWindows ? false : reusePort,
      ttl: ttl,
    );
  }

  static Future<Iterable<NetworkInterface>> _interfacesFactory(
    InternetAddressType type,
  ) async {
    final interfaces = await NetworkInterface.list(
      includeLinkLocal: true,
      includeLoopback: false,
      type: type,
    );

    if (!Platform.isWindows) {
      return interfaces;
    }

    final filtered = interfaces.where(_isUsableWindowsInterface).toList();
    if (filtered.isNotEmpty) {
      return filtered;
    }

    return interfaces.where((interface) {
      return interface.addresses.any(
        (address) => !address.isLoopback && address.type == InternetAddressType.IPv4 && !_isLinkLocalIPv4(address),
      );
    });
  }

  static bool _isUsableWindowsInterface(NetworkInterface interface) {
    final name = interface.name.toLowerCase();
    if (name.contains('tailscale') ||
        name.contains('hyper-v') ||
        name.contains('wsl') ||
        name.contains('virtual') ||
        name.contains('vpn') ||
        name.contains('bluetooth') ||
        name.contains('loopback') ||
        name.contains('pseudo') ||
        name.startsWith('local area connection*')) {
      return false;
    }

    for (final address in interface.addresses) {
      if (address.type != InternetAddressType.IPv4) {
        continue;
      }
      if (address.isLoopback || _isLinkLocalIPv4(address)) {
        continue;
      }
      return true;
    }
    return false;
  }

  static bool _isLinkLocalIPv4(InternetAddress address) {
    return address.address.startsWith('169.254.');
  }

  @override
  Future<void> start() async {
    if (_started) return;
    await _client.start(interfacesFactory: _interfacesFactory);
    _started = true;
  }

  @override
  Future<void> stop() async {
    if (!_started) return;
    _client.stop();
    _started = false;
  }

  @override
  Stream<String> lookupPtr(String serviceType) {
    return _client
        .lookup<PtrResourceRecord>(
          ResourceRecordQuery.serverPointer(serviceType),
        )
        .map((record) => record.domainName);
  }

  @override
  Future<List<MdnsSrvRecord>> lookupSrv(String domainName) async {
    final records = await _client.lookup<SrvResourceRecord>(ResourceRecordQuery.service(domainName)).toList();
    return records
        .map(
          (record) => MdnsSrvRecord(target: record.target, port: record.port),
        )
        .toList();
  }

  @override
  Future<List<InternetAddress>> lookupAddresses(String host) async {
    final records = <IPAddressResourceRecord>[
      ...await _client
          .lookup<IPAddressResourceRecord>(
            ResourceRecordQuery.addressIPv4(host),
          )
          .toList(),
      ...await _client
          .lookup<IPAddressResourceRecord>(
            ResourceRecordQuery.addressIPv6(host),
          )
          .toList(),
    ];
    return records.map((record) => record.address).toList();
  }
}

String? _extractServiceName(String domainName, String serviceType) {
  final suffix = '.$serviceType';
  if (!domainName.endsWith(suffix)) {
    return null;
  }
  return domainName.substring(0, domainName.length - suffix.length);
}
