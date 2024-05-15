# flutter_adb

Native dart implementation of the ADB network protocol, based loosely on the [Java version by Cameron Gutman](https://github.com/cgutman/AdbLib).  
This package can be used to connect to Android devices with an open ADB port on your network, with some configurations it even allows self-ADB, e.g. connecting to an ADB instance on the same device as the app running the flutter app.

## Usage

#### First create an ADB crypto object

Depending on the security settings of the device you are connecting to, you may need to authenticate with an RSA keypair.  
This package contains a helper class to generate the keypair and authenticate with the device, but you can also provide your own keypair.  
The package uses pointycastle for RSA encryption, so you can also use your own keypair generated with that library.  

```dart
final AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey> keyPair = AdbCrypto.generateRSAKeyPair();
final crypto = AdbCrypto(keyPair: keyPair);
// Optionally call without the keypair to automatically generate one
final crypto = AdbCrypto();
```
*The first time you connect to a device, you will need to authorize the connection from the device itself, after that the keypair will be stored on the device and you can connect without further interaction, provided you save and reuse the keypair.*  

#### Next, create an ADB connection
```dart
final adb = AdbConnection(
  '127.0.0.1',
  5555,
  crypto,
);
bool connected = await connection.connect();
// You can also listen for connection status changes
connection.onConnectionChanged.listen((connected) {
  print('Connected: $connected');
});
```
#### From here you can open a shell, etc.
```dart
final AdbStream shell = await connection.open('shell:');
// Alteratively, you can use the convenience method
final AdbStream shell = await connection.openShell();
```
#### Read and write to the stream
```dart
// Listen for incoming data
shell.onPayload.listen((payload) {
  print('Received: $payload');
});
// Write data to the stream
bool success = await shell.write('ls\n');

// Close the stream
shell.sendClose();
```

### OR:
#### Use the convenience method to open a shell, send a single command, and get the output
```dart
final String result = Adb.sendSingleCommand(
  'monkey -p com.google.android.googlequicksearchbox 1;sleep 3;input keyevent KEYCODE_HOME',
  ip: '127.0.0.1',
  port: 5555,
  crypto: crypto,
);
print(result);
```
*This method will automatically open a connection, open a shell, send a command, close the shell & connection, and then give the output, you can chain multiple commands together using the `;` operator.*
## Example
Check out the example app for a simple ADB terminal implementation (using riverpod).

## License
This project is licensed under a BSD-3 Clause License, see the included LICENSE file for the full text.
While no code was directly reused, concepts and class structure was based loosely on the work by Cameron Gutman, also licensed under BSD 3-Clause.

## Contribute
Issues and pull requests are always welcome!
If you found this project helpful, consider buying me a cup of :coffee:
- [PayPal](https://www.paypal.me/bymedev)