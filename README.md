# universal_serial

A unified, cross-platform Dart API for USB/UART serial communication across Web, Android, Windows, macOS, and Linux. This package intelligently abstracts away the fragmented underlying mechanics of standard serial ports (`flutter_libserialport`), Android USB OTG (`usb_serial`), and Browser Serial (`webserial`), presenting a single, elegant `SerialManager` interface.

## Supported Platforms
| Platform | Supported | Underlying Library |
| ---- | ---- | --- |
| **Android** | ✅ | `usb_serial` |
| **Web** | ✅ | `webserial` |
| **Windows** | ✅ | `flutter_libserialport` |
| **macOS** | ✅ | `flutter_libserialport` |
| **Linux** | ✅ | `flutter_libserialport` |
| iOS | ❌ | Apple restricts USB access |

## Features
- Agnostically return available ports (Lists devices silently on Desktop/Android, yields to popups on Web).
- Trigger security permissions using platform-specific guidelines automatically on `connect()`.
- Listen to robust byte streams effortlessly with `receiveStream`.
- Drop-in byte writing using `write(Uint8List)`.

## Installation

Add this to your package's `pubspec.yaml` file:
```yaml
dependencies:
  universal_serial: ^0.0.1
```

## Setup Requirements

### Android
Add the following to your `<application>` tag in `android/app/src/main/AndroidManifest.xml` to optionally allow intent filtering when devices are plugged in:
```xml
<meta-data
    android:name="android.hardware.usb.action.USB_DEVICE_ATTACHED"
    android:resource="@xml/device_filter" />
```

### macOS
If you use App Sandbox, you must add the following entitlement to your `macos/Runner/DebugProfile.entitlements` and `Release.entitlements`:
```xml
<key>com.apple.security.device.usb</key>
<true/>
<key>com.apple.security.device.serial</key>
<true/>
```

## Usage

```dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:universal_serial/universal_serial.dart';

void main() async {
  // Grab the correct global SerialManager for the current platform
  final manager = getSerialManager();

  // 1. Get Discovered Ports (Will be empty on Web to force the browser picker)
  final ports = await manager.getAvailablePorts();
  
  // 2. Connect to a port
  // On Desktop/Android, specify the portAddress. On Web, you can leave it null to trigger a popup!
  final connected = await manager.connect(
      portAddress: ports.isNotEmpty ? ports.first : null, 
      baudRate: 115200
  );

  if (connected) {
    debugPrint("Connected to the serial device successfully!");

    // 3. Listen to incoming UART data
    manager.receiveStream.listen((Uint8List data) {
       debugPrint("Raw bytes received: ${data.length}");
    });

    // 4. Send some data handling
    await manager.write(Uint8List.fromList([0x01, 0x02, 0x03]));
  } else {
    debugPrint("Failed to connect to the device or permission denied.");
  }
}
```
