import 'dart:js_interop';

import 'package:web/web.dart' as web;

Future<void> clearAppBadge() async {
  try {
    await web.window.navigator.clearAppBadge().toDart;
  } catch (_) {
    // Badging is optional and may be unavailable outside an installed PWA.
  }
  web.window.navigator.serviceWorker.controller?.postMessage(
    <String, Object?>{'type': 'CLEAR_APP_BADGE'}.jsify(),
  );
}
