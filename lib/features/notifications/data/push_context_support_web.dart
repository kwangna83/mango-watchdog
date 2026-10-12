import 'package:web/web.dart' as web;

bool get isPushContextSupported {
  final navigator = web.window.navigator;
  final userAgent = navigator.userAgent.toLowerCase();
  final isAppleMobile =
      userAgent.contains('iphone') ||
      userAgent.contains('ipad') ||
      userAgent.contains('ipod') ||
      (userAgent.contains('macintosh') && navigator.maxTouchPoints > 1);

  if (!isAppleMobile) return true;
  return web.window.matchMedia('(display-mode: standalone)').matches;
}
