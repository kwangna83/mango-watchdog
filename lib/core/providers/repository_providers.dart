import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/data/supabase_auth_repository.dart';
import '../../features/auth/domain/auth_repository.dart';
import '../../features/chat/data/supabase_chat_repository.dart';
import '../../features/chat/data/chat_image_cache.dart';
import '../../features/chat/data/chat_image_resolver.dart';
import '../../features/chat/domain/chat_repository.dart';
import '../../features/chat/presentation/decoded_chat_image_cache.dart';
import '../../features/notifications/data/firebase_notification_repository.dart';
import '../../features/notifications/domain/notification_repository.dart';
import '../config/app_config.dart';
import '../services/installation_id_store.dart';

final supabaseClientProvider = Provider<SupabaseClient>(
  (ref) => Supabase.instance.client,
);

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => SupabaseAuthRepository(ref.watch(supabaseClientProvider)),
);

final chatRepositoryProvider = Provider<ChatRepository>(
  (ref) => SupabaseChatRepository(ref.watch(supabaseClientProvider)),
);

final chatImageCacheProvider = Provider<PersistentChatImageCache>(
  (ref) => createPersistentChatImageCache(),
);

final decodedChatImageCacheProvider = Provider<DecodedChatImageCache>((ref) {
  final cache = DecodedChatImageCache();
  ref.onDispose(cache.dispose);
  return cache;
});

final chatImageResolverProvider = Provider<ChatImageResolver>(
  (ref) => ChatImageResolver(
    cache: ref.watch(chatImageCacheProvider),
    repository: ref.watch(chatRepositoryProvider),
  ),
);

final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  final firebase = AppConfig.fromEnvironment().firebaseWeb;
  return FirebaseNotificationRepository(vapidKey: firebase?.vapidKey);
});

final installationIdStoreProvider = Provider<InstallationIdStore>(
  (ref) => InstallationIdStore(SharedPreferencesAsync()),
);
