/// Browser-only services (download, audio click, fullscreen, wake lock),
/// with no-op fallbacks so the rest of the app runs under `flutter test`.
library;

export 'platform_stub.dart' if (dart.library.js_interop) 'platform_web.dart';
