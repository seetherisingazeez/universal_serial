/// The primary entry point exposing the abstract `SerialManager` and dynamic platform resolution via conditional exports.
library universal_serial;

export 'src/serial_manager.dart';

export 'src/serial_native.dart'
    if (dart.library.html) 'src/serial_web.dart';
