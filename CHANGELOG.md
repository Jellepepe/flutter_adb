## 0.2.0

* Added Android 11+ wireless pairing support via `AdbPairing.pair(...)`
* Added host-generated QR pairing via `AdbQrPairingData.generate()` and `AdbPairing.pairWithQr(...)`
* Added mDNS discovery for `_adb-tls-pairing._tcp` and `_adb-tls-connect._tcp`
* Expanded the example app with code pairing, QR pairing, saved devices, and automatic connect after QR pairing
* Added key persistence helpers and updated package/example documentation

## 0.1.1

* Removed Flutter dependency 

## 0.1.0

* Initial release
