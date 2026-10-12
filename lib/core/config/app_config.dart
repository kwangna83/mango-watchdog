class AppConfig {
  const AppConfig({
    required this.supabaseUrl,
    required this.publishableKey,
    required this.firebaseWeb,
  });

  final String supabaseUrl;
  final String publishableKey;
  final FirebaseWebConfig? firebaseWeb;

  static AppConfig fromEnvironment() {
    const url = String.fromEnvironment('SUPABASE_URL');
    const key = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
    if (url.isEmpty || key.isEmpty) {
      throw const AppConfigException(
        'SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY are required.',
      );
    }
    return AppConfig(
      supabaseUrl: url,
      publishableKey: key,
      firebaseWeb: FirebaseWebConfig.fromEnvironment(),
    );
  }
}

class FirebaseWebConfig {
  const FirebaseWebConfig({
    required this.apiKey,
    required this.authDomain,
    required this.projectId,
    required this.storageBucket,
    required this.messagingSenderId,
    required this.appId,
    required this.vapidKey,
  });

  final String apiKey;
  final String authDomain;
  final String projectId;
  final String storageBucket;
  final String messagingSenderId;
  final String appId;
  final String vapidKey;

  static FirebaseWebConfig? fromEnvironment() {
    const config = FirebaseWebConfig(
      apiKey: String.fromEnvironment('FIREBASE_WEB_API_KEY'),
      authDomain: String.fromEnvironment('FIREBASE_WEB_AUTH_DOMAIN'),
      projectId: String.fromEnvironment('FIREBASE_PROJECT_ID'),
      storageBucket: String.fromEnvironment('FIREBASE_STORAGE_BUCKET'),
      messagingSenderId: String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID'),
      appId: String.fromEnvironment('FIREBASE_WEB_APP_ID'),
      vapidKey: String.fromEnvironment('FIREBASE_WEB_VAPID_KEY'),
    );
    return config._isComplete ? config : null;
  }

  bool get _isComplete =>
      apiKey.isNotEmpty &&
      authDomain.isNotEmpty &&
      projectId.isNotEmpty &&
      storageBucket.isNotEmpty &&
      messagingSenderId.isNotEmpty &&
      appId.isNotEmpty &&
      vapidKey.isNotEmpty;
}

class AppConfigException implements Exception {
  const AppConfigException(this.message);

  final String message;

  @override
  String toString() => message;
}
