import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

void downloadFile(String name, Uint8List bytes, String mime) {
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mime));
  final url = web.URL.createObjectURL(blob);
  final a = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = name;
  web.document.body!.appendChild(a);
  a.click();
  a.remove();
  web.URL.revokeObjectURL(url);
}

web.AudioContext? _audio;

/// Short metronome tick synthesised with Web Audio.
void playClick({bool accent = false}) {
  final ctx = _audio ??= web.AudioContext();
  if (ctx.state == 'suspended') ctx.resume();
  final now = ctx.currentTime;
  final osc = ctx.createOscillator()..frequency.value = accent ? 1600 : 1000;
  final gain = ctx.createGain();
  gain.gain.setValueAtTime(0.5, now);
  gain.gain.exponentialRampToValueAtTime(0.001, now + 0.06);
  osc.connect(gain);
  gain.connect(ctx.destination);
  osc.start(now);
  osc.stop(now + 0.07);
}

Future<void> setFullscreen(bool on) async {
  try {
    if (on && web.document.fullscreenElement == null) {
      await web.document.documentElement!.requestFullscreen().toDart;
    } else if (!on && web.document.fullscreenElement != null) {
      await web.document.exitFullscreen().toDart;
    }
  } catch (_) {
    // Fullscreen is refused outside a user gesture and on iOS Safari.
  }
}

web.WakeLockSentinel? _lock;

Future<void> setWakeLock(bool on) async {
  try {
    if (on) {
      _lock ??= await web.window.navigator.wakeLock.request('screen').toDart;
    } else {
      await _lock?.release().toDart;
      _lock = null;
    }
  } catch (_) {
    _lock = null; // unsupported browser or page not visible
  }
}

bool get isStandalone => web.window.matchMedia('(display-mode: standalone)').matches;

/// Opens a link, or the mail client for a `mailto:` one.
void openUrl(String url) => web.window.open(url, '_blank');
