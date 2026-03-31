## 0.0.6

- feat: implement exit handlers for Android, Desktop, and Web serial managers to ensure proper disconnection on process termination

## 0.0.5

- feat: add device connection event stream to serial manager and implement across native and web platforms

## 0.0.4

- Fixed CHANGELOG missing version issue.

## 0.0.3

- Updated project metadata and configuration.

## 0.0.2

- Added `topics` and `issue_tracker` in pubspec to maximize pub.dev SEO score and discoverability tags mapping.

## 0.0.1

- Initial release.
- Added abstract `SerialManager` interface exposing uniform API for hardware connectivity.
- Implemented `flutter_libserialport` support resolving `/dev/` and `COM` devices concurrently for Window, Mac, and Linux.
- Added `webserial` bindings for Flutter Web compatibility utilizing `requestPort()` API popups.
- Configured dynamic compilation abstractions routing around OS restrictions perfectly.
