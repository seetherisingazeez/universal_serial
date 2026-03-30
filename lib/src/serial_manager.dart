import 'dart:typed_data';

/// Enumerates the type of physical device event occurring on a serial bus.
enum DeviceEventType {
  connected,
  disconnected,
}

/// Represents a physical plug/unplug event on the host machine.
class DeviceEvent {
  final DeviceEventType type;
  final String? deviceName;

  const DeviceEvent({required this.type, this.deviceName});

  @override
  String toString() => 'DeviceEvent(type: $type, deviceName: $deviceName)';
}

/// The shared architectural interface for Universal Serial.
/// Inherit this class to build new OS abstractions.
abstract class SerialManager {
  /// Queries the system or browser for available connected devices.
  /// On Native Desktop: Returns COM/tty list.
  /// On Native Android: Returns UsbDevice device names.
  /// On Web: Returns [] as scanning randomly isn't permitted by Chrome.
  Future<List<String>> getAvailablePorts();

  /// Prompts a connection intent.
  /// Returns [true] if successfully opened and streaming data.
  Future<bool> connect({String? portAddress, required int baudRate});

  /// Releases the stream and frees the hardware locks.
  Future<void> disconnect();

  /// Synchronously pipes [data] through the serial port output.
  Future<void> write(Uint8List data);

  /// Asynchronous broadcasting stream yielding raw bytes from the peripheral.
  Stream<Uint8List> get receiveStream;

  /// Asynchronous broadcasting stream yielding hardware connect/disconnect events.
  Stream<DeviceEvent> get deviceEventStream;
}
