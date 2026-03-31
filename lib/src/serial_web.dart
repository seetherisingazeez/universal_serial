import 'dart:async';
import 'dart:js_interop';


import 'dart:html' as html;

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

  static WebSerialManager? _activeInstance;
  static bool _exitHandlersRegistered = false;

  WebSerialManager() {
    _activeInstance = this;
    _registerExitHandlers();
  }

  static void _registerExitHandlers() {
    if (_exitHandlersRegistered) return;
    _exitHandlersRegistered = true;

    void scheduleDisconnect(html.Event _) {
      final instance = _activeInstance;
      if (instance == null) return;
      // Best-effort cleanup; browsers may not allow awaiting during unload.
      unawaited(instance.disconnect());
    }

    html.window.addEventListener('beforeunload', scheduleDisconnect);
    html.window.addEventListener('pagehide', scheduleDisconnect);
    html.window.addEventListener('unload', scheduleDisconnect);
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
          disconnect();
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
        serial.onconnect = ((web.Event event) {
          _deviceEventController?.add(const DeviceEvent(type: DeviceEventType.connected));
        } as void Function(web.Event)).toJS;
        
        serial.ondisconnect = ((web.Event event) {
          _deviceEventController?.add(const DeviceEvent(type: DeviceEventType.disconnected));
        } as void Function(web.Event)).toJS;
      },
      onCancel: () {
        serial.onconnect = null;
        serial.ondisconnect = null;
      },
    );
    return _deviceEventController!.stream;
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
