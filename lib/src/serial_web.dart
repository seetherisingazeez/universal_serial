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

  @override
  Future<List<String>> getAvailablePorts() async {
    return <String>[];
  }

  @override
  Future<bool> connect({String? portAddress, required int baudRate}) async {
    if (_port != null) {
      debugPrint("WebSerialManager: A port is already open.");
      return false;
    }

    try {
      final selectedPort = await requestWebSerialPort(<JSFilterObject>[].toJS);
      if (selectedPort != null) {
        _port = selectedPort;
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

        debugPrint("WebSerialManager: Port opened successfully.");

        _port!.ondisconnect = ((web.Event event) {
          debugPrint('WebSerialManager: The active port disconnected.');
          disconnect();
        } as void Function(web.Event)).toJS;

        _isReading = true;
        _readLoop();
        return true;
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
SerialManager getSerialManager() => WebSerialManager();
