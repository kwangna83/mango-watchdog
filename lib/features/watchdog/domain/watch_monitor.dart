class WatchMonitor {
  const WatchMonitor({required this.id, required this.ownerId, required this.config, required this.enabled, required this.intervalMinutes, required this.status, this.lastCheckedAt, this.lastError});
  final String id;
  final String ownerId;
  final Map<String, dynamic> config;
  final bool enabled;
  final int intervalMinutes;
  final String status;
  final DateTime? lastCheckedAt;
  final String? lastError;

  factory WatchMonitor.fromMap(Map<String, dynamic> map) => WatchMonitor(
    id: map['id'] as String, ownerId: map['owner_id'] as String,
    config: Map<String, dynamic>.from(map['config'] as Map? ?? const {}),
    enabled: map['enabled'] as bool? ?? true, intervalMinutes: map['interval_minutes'] as int? ?? 5,
    status: map['status'] as String? ?? 'unknown',
    lastCheckedAt: map['last_checked_at'] == null ? null : DateTime.tryParse(map['last_checked_at'] as String),
    lastError: map['last_error'] as String?,
  );
}
