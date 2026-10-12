import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('web deployment activates only the Firebase service worker', () {
    final workflow =
        File('.github/workflows/deploy-web.yml').readAsStringSync();
    final index = File('web/index.html').readAsStringSync();
    final worker = File('web/firebase-messaging-sw.js').readAsStringSync();

    expect(workflow, contains('--pwa-strategy=none'));
    expect(
      RegExp(r'navigator\.serviceWorker\.register\(').allMatches(index),
      hasLength(1),
    );
    expect(index, contains("register('firebase-messaging-sw.js')"));
    expect(worker, contains('self.skipWaiting()'));
    expect(worker, contains('self.clients.claim()'));
  });

  test('badge clearing uses the page API with a worker fallback', () {
    final implementation =
        File('lib/core/platform/app_badge_web.dart').readAsStringSync();

    expect(implementation, contains('navigator.clearAppBadge()'));
    expect(implementation, contains('serviceWorker.controller?.postMessage'));
    expect(implementation, contains("'type': 'CLEAR_APP_BADGE'"));
  });
}
