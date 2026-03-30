import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:usb_serial/usb_serial.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';

import 'serial_manager.dart';

class AndroidSerialManager implements SerialManager {
  UsbPort? _port;
  final StreamController<Uint8List> _streamController = StreamController<Uint8List>.broadcast();
  StreamSubscription<Uint8List>? _subscription;

  @override
  Future<List<String>> getAvailablePorts() async {
    final devices = await UsbSerial.listDevices();
    return devices.map((d) => d.deviceName).toList();
  }

  @override
  Future<bool> connect({String? portAddress, required int baudRate}) async {
    if (portAddress == null) {
      throw ArgumentError('portAddress is required for Android');
    }

    if (_port != null) {
      await disconnect();
    }

    final devices = await UsbSerial.listDevices();
    final device = devices.cast<UsbDevice?>().firstWhere(
          (d) => d?.deviceName == portAddress,
          orElse: () => null,
        );

    if (device == null) {
      debugPrint('Device not found: $portAddress');
      return false;
    }

    // Call create to trigger OS permission popup and create port
    try {
      _port = await device.create();
      if (_port == null) return false;

      final success = await _port!.open();
      if (!success) return false;

      await _port!.setPortParameters(
          baudRate, UsbPort.DATABITS_8, UsbPort.STOPBITS_1, UsbPort.PARITY_NONE);

      _subscription = _port!.inputStream!.listen((data) {
        _streamController.sink.add(data);
      });

      return true;
    } catch (e) {
      debugPrint('Failed to connect: $e');
      return false;
    }
  }

  @override
  Future<void> disconnect() async {
    await _subscription?.cancel();
    _subscription = null;
    if (_port != null) {
      await _port!.close();
      _port = null;
    }
  }

  @override
  Future<void> write(Uint8List data) async {
    if (_port == null) {
      throw StateError('Port is not connected');
    }
    await _port!.write(data);
  }

  @override
  Stream<Uint8List> get receiveStream => _streamController.stream;
}

class DesktopSerialManager implements SerialManager {
  SerialPort? _port;
  SerialPortReader? _reader;
  final StreamController<Uint8List> _streamController = StreamController<Uint8List>.broadcast();
  StreamSubscription<Uint8List>? _subscription;

  @override
  Future<List<String>> getAvailablePorts() async {
    return SerialPort.availablePorts;
  }

  @override
  Future<bool> connect({String? portAddress, required int baudRate}) async {
    if (portAddress == null) {
      throw ArgumentError('portAddress is required for Desktop');
    }

    if (_port != null) {
      await disconnect();
    }

    try {
      _port = SerialPort(portAddress);
      if (!_port!.openReadWrite()) {
        debugPrint('Failed to open port');
        return false;
      }

      final config = _port!.config;
      config.baudRate = baudRate;
      config.bits = 8;
      config.stopBits = 1;
      config.parity = SerialPortParity.none;
      config.setFlowControl(SerialPortFlowControl.none);
      _port!.config = config;
      config.dispose();

      _reader = SerialPortReader(_port!);
      _subscription = _reader!.stream.listen((data) {
        _streamController.sink.add(data);
      });

      return true;
    } catch (e) {
      debugPrint('Failed to connect: $e');
      return false;
    }
  }

  @override
  Future<void> disconnect() async {
    await _subscription?.cancel();
    _subscription = null;
    _reader?.close();
    _reader = null;
    if (_port != null) {
      if (_port!.isOpen) {
        _port!.close();
      }
      _port!.dispose();
      _port = null;
    }
  }

  @override
  Future<void> write(Uint8List data) async {
    if (_port == null || !_port!.isOpen) {
      throw StateError('Port is not connected');
    }
    final bytesWritten = _port!.write(data, timeout: 0);
    if (bytesWritten < 0) {
      throw Exception('Failed to write data');
    }
  }

  @override
  Stream<Uint8List> get receiveStream => _streamController.stream;
}

SerialManager getSerialManager() {
  if (Platform.isAndroid) {
    return AndroidSerialManager();
  } else if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    return DesktopSerialManager();
  } else {
    throw UnsupportedError('Unsupported platform for serial communication');
  }
}
