# flutter_adb_example

This example demonstrates the working `flutter_adb` flow end to end:

- create a reusable `AdbCrypto`
- pair with an Android 11+ device using a pairing code
- pair with an Android 11+ device using a generated QR code
- connect to the device's normal ADB port
- open an interactive shell stream in a simple terminal UI

## Running the Example

From the package root:

```bash
flutter run -d <your-device-or-desktop>
```

## Device Setup

The example supports both Android 11+ wireless pairing modes:

- code pairing, where the device shows IP, pairing port, and a 6-digit code
- QR pairing, where the example app generates the QR code and the device scans it

On the Android 11+ device you want to control:

1. Enable **Developer options**.
2. Enable **Wireless debugging**.

For 6-digit pairing code:
3. Select **Pair device with pairing code**.
4. Note the pairing IP/port and the 6-digit code.
5. After pairing, use the device's regular ADB port in the main connect form.

For QR pairing:

1. Press **Pair With QR** in the example app.
2. The app generates an Android Studio style `WIFI:T:ADB;...` QR code and waits for mDNS discovery.
3. On the Android device, open **Wireless debugging** and select **Pair device with QR code** to scan that QR code.
4. After pairing, the example fills in the discovered connect endpoint automatically when possible.

For self-ADB or Android 10 devices:

1. Enable TCP/IP debugging, or run `adb tcpip 5555` using usb debugging on your device.
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
- On Android hosts, mDNS discovery may need extra platform-specific multicast enablement on some devices.

## Main Package

For the package API and usage examples, see the main [README](../README.md).
