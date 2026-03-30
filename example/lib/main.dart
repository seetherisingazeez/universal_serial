import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:universal_serial/universal_serial.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Universal Serial Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const SerialDemoPage(),
    );
  }
}

class SerialDemoPage extends StatefulWidget {
  const SerialDemoPage({super.key});

  @override
  State<SerialDemoPage> createState() => _SerialDemoPageState();
}

class _SerialDemoPageState extends State<SerialDemoPage> {
  final SerialManager _manager = getSerialManager();
  List<String> _ports = [];
  bool _isConnected = false;
  String _status = 'Disconnected';
  final List<String> _logs = [];

  @override
  void initState() {
    super.initState();
    _loadPorts();
  }

  Future<void> _loadPorts() async {
    final ports = await _manager.getAvailablePorts();
    setState(() {
      _ports = ports;
    });
  }

  Future<void> _connect(String? port) async {
    setState(() {
      _status = 'Connecting...';
    });

    final success = await _manager.connect(portAddress: port, baudRate: 115200);
    
    setState(() {
      _isConnected = success;
      _status = success ? 'Connected ${port ?? ''}' : 'Failed to connect';
    });

    if (success) {
      _manager.receiveStream.listen((Uint8List data) {
        setState(() {
          _logs.add('Received: ${data.length} bytes');
          if (_logs.length > 20) _logs.removeAt(0);
        });
      }, onError: (e) {
        setState(() {
          _status = 'Error: $e';
          _isConnected = false;
        });
      });
    }
  }

  Future<void> _disconnect() async {
    await _manager.disconnect();
    setState(() {
      _isConnected = false;
      _status = 'Disconnected';
    });
  }

  Future<void> _sendPing() async {
    if (!_isConnected) return;
    try {
      await _manager.write(Uint8List.fromList([0x50, 0x69, 0x6E, 0x67])); // 'Ping'
      setState(() {
        _logs.add('Sent: Ping (4 bytes)');
        if (_logs.length > 20) _logs.removeAt(0);
      });
    } catch (e) {
      setState(() {
        _status = 'Write Error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Serial Terminal'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadPorts(),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text('Status: $_status', style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          if (!_isConnected) ...[
            Expanded(
              child: ListView.builder(
                itemCount: _ports.length + 1, // +1 for the web fallback button
                itemBuilder: (context, index) {
                  if (index == 0) {
                     return ListTile(
                      leading: const Icon(Icons.usb),
                      title: const Text("Open Native/Browser Picker"),
                      subtitle: const Text("Use if your port isn't listed or you are on Web"),
                      trailing: ElevatedButton(
                        onPressed: () => _connect(null),
                        child: const Text('Connect'),
                      ),
                    );
                  }
                  final port = _ports[index - 1];
                  return ListTile(
                    leading: const Icon(Icons.cable),
                    title: Text(port),
                    trailing: ElevatedButton(
                      onPressed: () => _connect(port),
                      child: const Text('Connect'),
                    ),
                  );
                },
              ),
            ),
          ] else ...[
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(
                    onPressed: _sendPing,
                    child: const Text('Send Ping'),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade100),
                    onPressed: _disconnect,
                    child: const Text('Disconnect'),
                  ),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: ListView.builder(
                reverse: true,
                itemCount: _logs.length,
                itemBuilder: (context, index) {
                   // reverse order display
                  return ListTile(
                    dense: true,
                    title: Text(_logs[_logs.length - 1 - index]),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
