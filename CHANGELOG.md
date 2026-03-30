## 0.0.1

- Initial release.
- Added abstract `SerialManager` interface exposing uniform API for hardware connectivity.
- Implemented `flutter_libserialport` support resolving `/dev/` and `COM` devices concurrently for Window, Mac, and Linux.
- Added `webserial` bindings for Flutter Web compatibility utilizing `requestPort()` API popups.
- Configured dynamic compilation abstractions routing around OS restrictions perfectly.
