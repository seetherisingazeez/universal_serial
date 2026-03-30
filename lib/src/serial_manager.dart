import 'dart:typed_data';

abstract class SerialManager {
  Future<List<String>> getAvailablePorts();
  Future<bool> connect({String? portAddress, required int baudRate});
  Future<void> disconnect();
  Future<void> write(Uint8List data);
  Stream<Uint8List> get receiveStream;
}
