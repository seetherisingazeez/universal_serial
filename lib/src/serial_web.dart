import 'dart:async';
import 'dart:js_interop';


import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;
import 'package:webserial/webserial.dart';

import 'serial_manager.dart';

/// Manager parsing Javascript abstractions through [dart:js_interop] mapping to [webserial].
class WebSerialManager implements SerialManager {
  JSSerialPort? _port;
  web.ReadableStreamDefaultReader? _reader;
  bool _isReading = false;
  final StreamController<Uint8List> _streamController = StreamController<Uint8List>.broadcast();
  StreamController<DeviceEvent>? _deviceEventController;
  web.EventListener? _serialConnectListener;
  web.EventListener? _serialDisconnectListener;

  static WebSerialManager? _activeInstance;
  static bool _exitHandlersRegistered = false;

  WebSerialManager() {
    _activeInstance = this;
    _registerExitHandlers();
  }

  static void _registerExitHandlers() {
    if (_exitHandlersRegistered) return;
    _exitHandlersRegistered = true;

    void scheduleDisconnect(web.Event _) {
      final instance = _activeInstance;
      if (instance == null) return;
      // Best-effort cleanup; browsers may not allow awaiting during unload.
      unawaited(instance.disconnect());
    }

    final jsScheduleDisconnect = scheduleDisconnect.toJS;
    web.window.addEventListener('beforeunload', jsScheduleDisconnect);
    web.window.addEventListener('pagehide', jsScheduleDisconnect);
    web.window.addEventListener('unload', jsScheduleDisconnect);
  }

  @override
  Future<List<String>> getAvailablePorts() async {
    return <String>[];
  }

  @override
  Future<bool> connect({String? portAddress, required int baudRate}) async {
    if (_port != null) {
      debugPrint("WebSerialManager: A port is already open.");
      if (!_isReading && _port!.readable != null) {
        _isReading = true;
        _readLoop();
      }
      return _port!.readable != null || _port!.writable != null;
    }

    try {
      final selectedPort = await requestWebSerialPort(<JSFilterObject>[].toJS);
      if (selectedPort != null) {
        _port = selectedPort;
        bool opened = false;
        try {
          await _port!.open(
            JSSerialOptions(
              baudRate: baudRate,
              dataBits: 8,
              stopBits: 1,
              parity: "none",
              bufferSize: 2048,
              flowControl: "none",
            ),
          ).toDart;
          opened = true;
          debugPrint("WebSerialManager: Port opened successfully.");
        } catch (e) {
          // Some browsers throw if the port is already open (e.g., for granted/paired permissions).
          debugPrint("WebSerialManager: Port.open threw (treating as possibly already open): $e");
        }

        _port!.ondisconnect = ((web.Event event) {
          debugPrint('WebSerialManager: The active port disconnected.');
          _emitDeviceEvent(DeviceEventType.disconnected);
          unawaited(disconnect());
        } as void Function(web.Event)).toJS;

        final canRead = _port!.readable != null;
        if (opened || canRead) {
          _isReading = true;
          _readLoop();
          return true;
        }

        debugPrint("WebSerialManager: Port did not become readable.");
        await disconnect();
        return false;
      } else {
        debugPrint("WebSerialManager: No port selected.");
        return false;
      }
    } catch (e) {
      debugPrint("WebSerialManager: Error during connection process: $e");
      await disconnect();
      return false;
    }
  }

  @override
  Future<void> disconnect() async {
    if (_port == null) return;

    _isReading = false;
    final portToClose = _port;
    final readerToCancel = _reader;

    _port = null;
    _reader = null;

    try {
      if (readerToCancel != null) {
        await readerToCancel.cancel().toDart;
      }
    } catch (e) {
      debugPrint("WebSerialManager: Error cancelling reader: $e");
    }

    try {
      if (portToClose != null) {
        await portToClose.close().toDart;
      }
    } catch (e) {
      debugPrint("WebSerialManager: Error closing port: $e");
    }
  }

  @override
  Future<void> write(Uint8List data) async {
    if (_port?.writable == null) {
      throw StateError("WebSerialManager: Port is not writable.");
    }
    final writer = _port!.writable!.getWriter();
    final JSUint8Array jsReq = data.toJS;
    try {
      writer.write(jsReq);
    } finally {
      writer.releaseLock();
    }
  }

  @override
  Stream<Uint8List> get receiveStream => _streamController.stream;

  @override
  Stream<DeviceEvent> get deviceEventStream {
    _deviceEventController ??= StreamController<DeviceEvent>.broadcast(
      onListen: () {
        // Global navigator.serial connect/disconnect is often more reliable via
        // addEventListener than the onconnect/ondisconnect properties. Port-level
        // disconnect (see connect()) is still required for unplug while connected.
        _serialConnectListener = ((web.Event event) {
          _emitDeviceEvent(DeviceEventType.connected);
        }).toJS;
        _serialDisconnectListener = ((web.Event event) {
          _emitDeviceEvent(DeviceEventType.disconnected);
        }).toJS;
        serial.addEventListener('connect', _serialConnectListener);
        serial.addEventListener('disconnect', _serialDisconnectListener);
      },
      onCancel: () {
        if (_serialConnectListener != null) {
          serial.removeEventListener('connect', _serialConnectListener);
          _serialConnectListener = null;
        }
        if (_serialDisconnectListener != null) {
          serial.removeEventListener('disconnect', _serialDisconnectListener);
          _serialDisconnectListener = null;
        }
      },
    );
    return _deviceEventController!.stream;
  }

  void _emitDeviceEvent(DeviceEventType type, {String? deviceName}) {
    _deviceEventController?.add(DeviceEvent(type: type, deviceName: deviceName));
  }

  Future<void> _readLoop() async {
    if (_port?.readable == null) return;

    _reader = _port!.readable!.getReader() as web.ReadableStreamDefaultReader?;
    debugPrint("WebSerialManager: Starting read loop...");

    while (_isReading) {
      try {
        final result = await _reader!.read().toDart;
        if (result.done) {
          debugPrint("WebSerialManager: Reader reported stream is done.");
          break;
        }

        final value = result.value;
        if (value != null) {
          final jsArray = value as JSUint8Array;
          _streamController.sink.add(jsArray.toDart);
        }
      } catch (e) {
        debugPrint("WebSerialManager: Read loop failed. Error: $e");
        // An unexpected read error usually indicates a physical disconnection or dropped port.
        if (_isReading) {
          debugPrint("WebSerialManager: Emitting disconnect event due to read failure.");
          _emitDeviceEvent(DeviceEventType.disconnected);
        }
        break;
      }
    }
    debugPrint("WebSerialManager: Exited read loop.");
    await disconnect();
  }
}

/// Exposes a Dart library level getter so consumers can grab the Web implementation conditionally.
WebSerialManager? _webSerialManagerSingleton;
SerialManager getSerialManager() => _webSerialManagerSingleton ??= WebSerialManager();
