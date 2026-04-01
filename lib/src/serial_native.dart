import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:usb_serial/usb_serial.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';

import 'serial_manager.dart';

/// Native serial manager implementation specifically tailored for [usb_serial] acting as an OTG connector.
class AndroidSerialManager implements SerialManager {
  UsbPort? _port;
  final StreamController<Uint8List> _streamController = StreamController<Uint8List>.broadcast();
  StreamSubscription<Uint8List>? _subscription;
  String? _connectedPortAddress;

  static AndroidSerialManager? _activeInstance;
  static bool _exitHandlersRegistered = false;

  AndroidSerialManager() {
    _activeInstance = this;
    _registerExitHandlers();
  }

  static void _registerExitHandlers() {
    if (_exitHandlersRegistered) return;
    _exitHandlersRegistered = true;

    void handle(ProcessSignal signal) {
      final instance = _activeInstance;
      if (instance == null) return;
      unawaited(instance.disconnect());
    }

    ProcessSignal.sigterm.watch().listen(handle);
    ProcessSignal.sigint.watch().listen(handle);
  }

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
      if (portAddress == _connectedPortAddress) {
        return true;
      }
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
      if (!success) {
        await disconnect();
        return false;
      }

      await _port!.setPortParameters(
          baudRate, UsbPort.DATABITS_8, UsbPort.STOPBITS_1, UsbPort.PARITY_NONE);

      _subscription = _port!.inputStream!.listen(
        (data) {
          _streamController.sink.add(data);
        },
        onError: (error) {
          debugPrint('USB stream error: $error');
          unawaited(disconnect());
        },
        onDone: () {
          unawaited(disconnect());
        },
        cancelOnError: true,
      );

      _connectedPortAddress = portAddress;
      return true;
    } catch (e) {
      debugPrint('Failed to connect: $e');
      await disconnect();
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
    _connectedPortAddress = null;
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

  @override
  Stream<DeviceEvent> get deviceEventStream {
    return UsbSerial.usbEventStream?.map((event) {
      final type = event.event == UsbEvent.ACTION_USB_ATTACHED
          ? DeviceEventType.connected
          : DeviceEventType.disconnected;
      return DeviceEvent(type: type, deviceName: event.device?.deviceName);
    }) ?? const Stream.empty();
  }
}

/// Native serial manager implementation spanning Windows, Mac, and Linux leveraging [flutter_libserialport].
class DesktopSerialManager implements SerialManager {
  SerialPort? _port;
  SerialPortReader? _reader;
  final StreamController<Uint8List> _streamController = StreamController<Uint8List>.broadcast();
  StreamSubscription<Uint8List>? _subscription;
  String? _connectedPortAddress;

  StreamController<DeviceEvent>? _deviceEventController;
  Timer? _pollingTimer;
  List<String> _lastPorts = [];

  static DesktopSerialManager? _activeInstance;
  static bool _exitHandlersRegistered = false;

  DesktopSerialManager() {
    _activeInstance = this;
    _registerExitHandlers();
  }

  static void _registerExitHandlers() {
    if (_exitHandlersRegistered) return;
    _exitHandlersRegistered = true;

    void handle(ProcessSignal signal) {
      final instance = _activeInstance;
      if (instance == null) return;
      unawaited(instance.disconnect());
    }

    ProcessSignal.sigterm.watch().listen(handle);
    ProcessSignal.sigint.watch().listen(handle);
  }

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
      if (portAddress == _connectedPortAddress && _port!.isOpen) {
        return true;
      }
      await disconnect();
    }

    try {
      _port = SerialPort(portAddress);
      if (!_port!.openReadWrite()) {
        debugPrint('Failed to open port');
        await disconnect();
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
      _subscription = _reader!.stream.listen(
        (data) {
          _streamController.sink.add(data);
        },
        onError: (Object error) {
          debugPrint('Serial port stream error: $error');
          unawaited(disconnect());
        },
        onDone: () {
          unawaited(disconnect());
        },
        cancelOnError: true,
      );

      _connectedPortAddress = portAddress;
      return true;
    } catch (e) {
      debugPrint('Failed to connect: $e');
      await disconnect();
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
    _connectedPortAddress = null;
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

  @override
  Stream<DeviceEvent> get deviceEventStream {
    _deviceEventController ??= StreamController<DeviceEvent>.broadcast(
      onListen: () {
        _lastPorts = SerialPort.availablePorts;
        _pollingTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
          final currentPorts = SerialPort.availablePorts;
          final addedPorts = currentPorts.where((p) => !_lastPorts.contains(p));
          final removedPorts = _lastPorts.where((p) => !currentPorts.contains(p));
          
          for (final port in addedPorts) {
            _deviceEventController?.add(DeviceEvent(type: DeviceEventType.connected, deviceName: port));
          }
          for (final port in removedPorts) {
            _deviceEventController?.add(DeviceEvent(type: DeviceEventType.disconnected, deviceName: port));
          }
          _lastPorts = currentPorts;
        });
      },
      onCancel: () {
        _pollingTimer?.cancel();
        _pollingTimer = null;
      },
    );
    return _deviceEventController!.stream;
  }
}

/// Platform-aware factory evaluating dart:io globals to assign the right implementation implicitly.
SerialManager? _nativeSerialManagerSingleton;
SerialManager getSerialManager() {
  if (_nativeSerialManagerSingleton != null) return _nativeSerialManagerSingleton!;

  if (Platform.isAndroid) {
    _nativeSerialManagerSingleton = AndroidSerialManager();
  } else if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    _nativeSerialManagerSingleton = DesktopSerialManager();
  } else {
    throw UnsupportedError('Unsupported platform for serial communication');
  }

  return _nativeSerialManagerSingleton!;
}
