# flutter_adb_example

This example demonstrates the working `flutter_adb` flow end to end:

- create a reusable `AdbCrypto`
- pair with an Android 11+ device using a pairing code
- connect to the device's normal ADB port
- open an interactive shell stream in a simple terminal UI

## Running the Example

From the package root:

```bash
flutter run -d <your-device-or-desktop>
```

## Device Setup

On the Android 11+ device you want to control:

1. Enable **Developer options**.
2. Enable **Wireless debugging**.
3. For first-time setup, open **Pair device with pairing code**.
4. Note the pairing IP/port and the 6-digit code.
5. After pairing, use the device's regular ADB port in the main connect form.

For self-ADB or Android 10 devices:

1. Enable TCP/IP debugging, or run `adb tcpip 5555` on your device.
2. You can connect immediately by entering the IP (e.g. `127.0.0.1` for self-ADB) and port in the main connect form.

## How the Example Works

The example keeps a single `AdbCrypto` in a Riverpod provider and reuses it for:
- pairing
- regular ADB connections
- one-off shell commands

That reuse is important. Pairing succeeds only for the RSA keypair that was paired, so later ADB connections must use the same `AdbCrypto` instance or the same restored keypair.

The example persists:
- the RSA keypair in secure storage
- the saved device list in shared preferences

## Notes

- Saved connections are convenience metadata only; device trust still depends on restoring the same RSA keypair.
- The example enables verbose logging to make protocol behavior visible during development.

## Main Package

For the package API and usage examples, see the main [README](../README.md).
