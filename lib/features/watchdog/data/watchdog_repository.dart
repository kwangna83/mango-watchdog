import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/watch_monitor.dart';

class WatchdogRepository {
  WatchdogRepository(this._client);
  final SupabaseClient _client;

  Future<WatchMonitor> ensureMonitor(String ownerId) async {
    final existing = await _client.from('watch_monitors').select().eq('owner_id', ownerId).order('created_at').limit(1).maybeSingle();
    if (existing != null) return WatchMonitor.fromMap(existing);
    final row = await _client.from('watch_monitors').insert({
      'owner_id': ownerId,
      'config': {'entryDate': '2026-11-07', 'entryTime': '13:00', 'exitDate': '2026-11-10', 'exitTime': '17:30', 'bookingType': 'BASIC'},
    }).select().single();
    return WatchMonitor.fromMap(row);
  }

  Future<WatchMonitor> getMonitor(String id) async => WatchMonitor.fromMap(await _client.from('watch_monitors').select().eq('id', id).single());

  Future<void> updateMonitor(String id, {required Map<String, dynamic> config, required bool enabled, required int intervalMinutes}) async {
    await _client.from('watch_monitors').update({'config': config, 'enabled': enabled, 'interval_minutes': intervalMinutes}).eq('id', id);
  }

  Future<List<Map<String, dynamic>>> recentRuns(String id) async => List<Map<String, dynamic>>.from(await _client.from('watch_check_runs').select().eq('monitor_id', id).order('checked_at', ascending: false).limit(20));

  Future<void> checkNow(String id) async => await _client.functions.invoke('check-watchdog', body: {'monitor_id': id, 'force': true});

  Future<void> savePushSubscription({required String ownerId, required String installationId, required String token}) async {
    await _client.from('watch_push_subscriptions').upsert({'owner_id': ownerId, 'installation_id': installationId, 'platform': 'web', 'token': token, 'enabled': true, 'last_seen_at': DateTime.now().toUtc().toIso8601String()}, onConflict: 'owner_id,installation_id');
  }
}
