{{flutter_js}}
{{flutter_build_config}}

// Flutter's own (deprecated) service worker is not registered: it would
// replace sw.js, which is what provides offline support.
_flutter.loader.load();
