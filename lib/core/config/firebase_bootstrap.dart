import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'app_config.dart';

abstract final class FirebaseBootstrap {
  static Future<bool> initialize(AppConfig config) async {
    final web = config.firebaseWeb;
    if (!kIsWeb || web == null) return false;
    await Firebase.initializeApp(
      options: FirebaseOptions(
        apiKey: web.apiKey,
        authDomain: web.authDomain,
        projectId: web.projectId,
        storageBucket: web.storageBucket,
        messagingSenderId: web.messagingSenderId,
        appId: web.appId,
      ),
    );
    return true;
  }
}
