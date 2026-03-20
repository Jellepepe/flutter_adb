# flutter_adb

`flutter_adb` is a pure Dart client for network ADB (Android Debug Bridge).

It supports:
- Connecting to an existing ADB TCP endpoint
- Android 11+ wireless pairing with `STLS` transport upgrade and `SPAKE2` pairing code flow
- Android Studio style QR pairing with mDNS discovery
- Opening shell streams and sending one-off commands

The package is intended for Flutter and Dart apps that need to talk directly to `adbd` over the network, including apps that connect to another device on the LAN or to an ADB daemon running on the same device.

## Features

- Pure Dart implementation(!)
- RSA key generation for ADB authentication
- Custom ADB key name metadata such as `user@host`
- Wireless pairing via `AdbPairing.pair(...)`
- QR pairing via `AdbQrPairingData.generate()` + `AdbPairing.pairWithQr(...)`
- Regular ADB transport via `AdbConnection`
- Convenience helper for single shell commands via `Adb.sendSingleCommand(...)`

## Quick Start

### 1. Create or provide an ADB keypair

`AdbCrypto` holds the RSA keypair used for both pairing and later ADB connections.
You must reuse the same `AdbCrypto` instance, or the same underlying keypair, after pairing.

```dart
final crypto = AdbCrypto(
  adbKeyName: 'my-app@dart',
);
```

You can also provide your own PointyCastle RSA keypair:

```dart
final crypto = AdbCrypto(
  keyPair: myKeyPair,
  adbKeyName: 'my-app@dart',
);
```

### 2a. [OPTIONAL] Pair with an Android 11+ device using a 6-digit pairing code

Use the wireless debugging pairing port and 6-digit pairing code shown on the device.

```dart
final paired = await AdbPairing.pair(
  '[IP_ADDRESS]',
  6666,
  '123456',
  crypto,
  verbose: true,
);

if (!paired) {
  throw Exception('Pairing failed');
}
```

After pairing succeeds, connect to the device's regular ADB port with the same `crypto` object.

### 2b. [OPTIONAL] Pair with an Android 11+ device using a generated QR code

This matches Android Studio's host-generated QR flow: the host app creates a QR payload, the device scans it, then the host discovers the requested pairing service over mDNS.

```dart
final qr = AdbQrPairingData.generate();

// Render qr.qrPayload as a QR code in your Flutter UI.
final result = await AdbPairing.pairWithQr(
  qr,
  crypto,
  verbose: true,
);

if (!result.success) {
  throw Exception(result.errorMessage ?? 'QR pairing failed');
}

if (result.connectEndpoint != null) {
  print('Resolved connect endpoint: ${result.connectEndpoint!.host}:${result.connectEndpoint!.port}');
}
```

### 3. Open an ADB connection

```dart
final connection = AdbConnection(
  '[IP_ADDRESS]',
  5555,
  crypto,
  verbose: true,
);

final connected = await connection.connect();
if (!connected) {
  throw Exception('ADB connection failed');
}
```

You can also observe connection state:

```dart
connection.onConnectionChanged.listen((connected) {
  print('Connected: $connected');
});
```

### 4. Open a shell stream

```dart
final shell = await connection.openShell();

shell.onPayload.listen((payload) {
  print(utf8.decode(payload));
});

await shell.writeString('pm list packages\n');
```

When done:

```dart
await shell.sendClose();
await connection.disconnect();
```

## Single Command Helper

For simple use cases, `Adb.sendSingleCommand(...)` opens a connection, runs a shell command, collects the output, and disconnects. 

> Note: For Android 11+ devices you need to pair first.

```dart
final output = await Adb.sendSingleCommand(
  'date',
  ip: '[IP_ADDRESS]',
  port: 5555,
  crypto: crypto,
);

print(output);
```

## Self-ADB or Android 10 Flow

1. Enable TCP/IP debugging, or run `adb tcpip 5555` on your device.
2. Connect to the device's normal ADB port with `AdbConnection(..., crypto)`.
3. The device will ask you to authorize the connection. Reuse the same `AdbCrypto` for future sessions to avoid this popup in the future.


## Typical Android 11+ Flow

1. Enable **Wireless debugging** on the device.
2. Start **Pair device with pairing code** on the device.
3. Call `AdbPairing.pair(pairingIp, pairingPort, pairingCode, crypto)`.
4. Connect to the device's normal ADB port with `AdbConnection(..., crypto)`.
5. Reuse the same `crypto` for future sessions.

## Typical QR Flow

1. Create `final qr = AdbQrPairingData.generate()`.
2. Render `qr.qrPayload` as a QR code in your app.
3. On the Android device, open **Wireless debugging** and scan that QR code.
4. Call `AdbPairing.pairWithQr(qr, crypto)`.
5. If `result.connectEndpoint` is present, use it with `AdbConnection`; otherwise resolve or enter the regular ADB connect endpoint separately.

## Persisting Keys

The package generates keys in memory, but it does not persist them by default.
If you want a device to keep trusting your app across launches, you need to persist the RSA keypair. The example app shows an example of how to do this.

## Android Host Caveat

QR pairing relies on mDNS. On Android hosts, multicast discovery may require extra platform-specific multicast enablement on some devices and ROMs.

## Example App

The example app demonstrates:
- Pairing with a device by pairing code
- Pairing with a device by generated QR code
- Connecting to the paired device
- Opening a shell-backed terminal UI
- Persisting the RSA keypair and saved devices

See [example/README.md](example/README.md) for details.

## License

This project is licensed under the BSD 3-Clause License. See [LICENSE](LICENSE).

The implementation is based conceptually on the ADB protocol specifications and was initially inspired by the [Java ADB client](https://github.com/cgutman/AdbLib) by Cameron Gutman. Some SPAKE2 code was written by referencing the [boringSSL](https://github.com/google/boringssl) implementation.
