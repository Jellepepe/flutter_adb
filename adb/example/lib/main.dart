import 'package:flutter/material.dart';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:adb/adb.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String _adbResponse = 'Unknown';
  Color _color = Colors.white;
  Stopwatch _sw = new Stopwatch();
  int _delay = 0;
  String _output = "";

  @override
  void initState() {
    super.initState();
  }

  // Platform messages are asynchronous, so we initialize in an async method.
  Future<void> sendAdbCommand(String command) async {
    String adbResponse;
    // Platform messages may fail, so we use a try/catch PlatformException.
    try {
      adbResponse = await Adb.attemptAdb(command);
    } on PlatformException {
      adbResponse = 'Failed to get platform version.';
    }

    // If the widget was removed from the tree while the asynchronous platform
    // message was in flight, we want to discard the reply rather than calling
    // setState to update our non-existent appearance.
    if (!mounted) return;

    setState(() {
      _adbResponse = adbResponse;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor: _color,
        appBar: AppBar(
          title: const Text('Plugin example app'),
        ),
        body: Stack(
          fit: StackFit.expand,
          children: [
            RawMaterialButton(
              onPressed: () {
                setState(() {
                  _delay = _sw.elapsedMilliseconds;
                  _sw.stop();
                  _sw.reset();
                  _color = Colors.green;
                  Future.delayed(Duration(seconds: 2)).then(
                    (_) => setState(() {
                    _color = Colors.white;
                    _output = "";
                    }));
                });
              },
            ),
            Column(
              children: [
                Center(
                  child: Text('Adb result: $_adbResponse\n'),
                ),
                IconButton(
                  icon: Icon(Icons.play_arrow),
                  iconSize: 64,
                  onPressed: () {
                    _delay = 0;
                    _sw.start();
                    sendAdbCommand("echo Waddup");
                  }
                ),
                Center(
                  child: Text('Measured adb delay: ' + ((_delay == 0) ? "Unknown" : _delay.toString() + 'ms') + '\n'),
                ),
                StreamBuilder(
                      stream: Adb.outputStream,
                      builder: (BuildContext context, AsyncSnapshot snapshot) {
                        if(snapshot.hasData) {
                          _output = _output + snapshot.data.toString();
                          return Text(
                            _output,
                          );
                        }
                        return Text(
                          _output,
                        );
                      }
                    )
              ]
            ),
          ]
        ),
      )
    );
  }
}
