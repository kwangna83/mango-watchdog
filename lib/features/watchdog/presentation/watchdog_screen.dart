import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/installation_id_store.dart';
import '../../../core/theme/app_theme.dart';
import '../../notifications/data/firebase_notification_repository.dart';
import '../../notifications/domain/notification_repository.dart';
import '../data/watchdog_repository.dart';
import '../domain/watch_monitor.dart';

class WatchdogScreen extends StatefulWidget {
  const WatchdogScreen({super.key});
  @override State<WatchdogScreen> createState() => _WatchdogScreenState();
}

class _WatchdogScreenState extends State<WatchdogScreen> {
  final _repo = WatchdogRepository(Supabase.instance.client);
  WatchMonitor? _monitor;
  List<Map<String, dynamic>> _runs = [];
  Timer? _timer;
  bool _busy = true;
  bool _saving = false;
  bool _pushBusy = false;
  String? _error;
  late final TextEditingController _entryDate, _entryTime, _exitDate, _exitTime;
  int _interval = 5;
  bool _enabled = true;

  @override void initState() { super.initState(); _entryDate=TextEditingController(); _entryTime=TextEditingController(); _exitDate=TextEditingController(); _exitTime=TextEditingController(); _load(); _timer=Timer.periodic(const Duration(seconds: 15), (_) => _refresh()); }
  @override void dispose() { _timer?.cancel(); for (final c in [_entryDate,_entryTime,_exitDate,_exitTime]) { c.dispose(); } super.dispose(); }

  Future<void> _load() async {
    try {
      var user = Supabase.instance.client.auth.currentUser;
      user ??= (await Supabase.instance.client.auth.signInAnonymously()).user;
      if (user == null) throw Exception('익명 로그인에 실패했습니다.');
      final m = await _repo.ensureMonitor(user.id); _apply(m); await _refresh();
    } catch (e) { if (mounted) setState(() { _error = '$e'; _busy = false; }); }
  }
  void _apply(WatchMonitor m) { _monitor=m; final c=m.config; _entryDate.text=c['entryDate'] as String? ?? '2026-11-07'; _entryTime.text=c['entryTime'] as String? ?? '13:00'; _exitDate.text=c['exitDate'] as String? ?? '2026-11-10'; _exitTime.text=c['exitTime'] as String? ?? '17:30'; _interval=m.intervalMinutes; _enabled=m.enabled; if (mounted) setState(() => _busy=false); }
  Future<void> _refresh() async { final m=_monitor; if(m==null) return; try { final fresh=await _repo.getMonitor(m.id); final runs=await _repo.recentRuns(m.id); if(mounted) { _monitor=fresh; final c=fresh.config; _entryDate.text=c['entryDate'] as String? ?? _entryDate.text; _entryTime.text=c['entryTime'] as String? ?? _entryTime.text; _exitDate.text=c['exitDate'] as String? ?? _exitDate.text; _exitTime.text=c['exitTime'] as String? ?? _exitTime.text; setState(() { _interval=fresh.intervalMinutes; _enabled=fresh.enabled; _runs=runs; }); } } catch (_) {} }
  Future<void> _save() async { final m=_monitor; if(m==null) return; setState(()=>_saving=true); try { await _repo.updateMonitor(m.id, config:{'entryDate':_entryDate.text.trim(),'entryTime':_entryTime.text.trim(),'exitDate':_exitDate.text.trim(),'exitTime':_exitTime.text.trim(),'bookingType':'BASIC'}, enabled:_enabled, intervalMinutes:_interval); await _refresh(); if(mounted) _snack('저장했습니다.'); } catch(e) { if(mounted) _snack('저장 실패: $e'); } finally { if(mounted) setState(()=>_saving=false); } }
  Future<void> _check() async { final m=_monitor; if(m==null) return; setState(()=>_saving=true); try { await _repo.checkNow(m.id); await _refresh(); if(mounted) _snack('서버 확인을 요청했습니다.'); } catch(e) { if(mounted) _snack('확인 실패: $e'); } finally { if(mounted) setState(()=>_saving=false); } }
  Future<void> _enablePush() async { final user=Supabase.instance.client.auth.currentUser; if(user==null) return; setState(()=>_pushBusy=true); try { final vapid=const String.fromEnvironment('FIREBASE_WEB_VAPID_KEY'); final n=FirebaseNotificationRepository(vapidKey:vapid.isEmpty?null:vapid); final p=await n.requestPermission(); if(p!=PushPermissionStatus.authorized) throw Exception('브라우저 알림 권한이 허용되지 않았습니다.'); final token=await n.token(); if(token==null) throw Exception('푸시 토큰을 가져오지 못했습니다.'); final install=await InstallationIdStore(SharedPreferencesAsync()).getOrCreate(); await _repo.savePushSubscription(ownerId:user.id,installationId:install,token:token); if(mounted) _snack('푸시 알림을 등록했습니다.'); } catch(e) { if(mounted) _snack('푸시 등록 실패: $e'); } finally { if(mounted) setState(()=>_pushBusy=false); } }
  void _snack(String s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  @override
  Widget build(BuildContext context) {
    if (_busy) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_error != null) return Scaffold(body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!))));
    final monitor = _monitor!;
    final available = monitor.status == 'available';
    return Scaffold(
      appBar: AppBar(title: const Text('mango-watchdog'), actions: [IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh))]),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        _statusCard(monitor, available),
        const SizedBox(height: 16),
        Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('감시 설정', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 14),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('감시 활성화'), value: _enabled, onChanged: (v) => setState(() => _enabled = v)),
          Row(children: [Expanded(child: _field('입차 날짜', _entryDate)), const SizedBox(width: 10), Expanded(child: _field('입차 시간', _entryTime))]),
          Row(children: [Expanded(child: _field('출차 날짜', _exitDate)), const SizedBox(width: 10), Expanded(child: _field('출차 시간', _exitTime))]),
          DropdownButtonFormField<int>(initialValue: _interval, decoration: const InputDecoration(labelText: '확인 간격'), items: [5, 10, 15, 30, 60].map((v) => DropdownMenuItem(value: v, child: Text('$v분마다'))).toList(), onChanged: (v) { if (v != null) setState(() => _interval = v); }),
          const SizedBox(height: 12),
          Row(children: [Expanded(child: FilledButton.icon(onPressed: _saving ? null : _save, icon: const Icon(Icons.save), label: Text(_saving ? '처리 중…' : '설정 저장'))), const SizedBox(width: 10), IconButton.filled(onPressed: _saving ? null : _check, icon: const Icon(Icons.play_arrow), tooltip: '지금 확인')]),
        ]))),
        const SizedBox(height: 16),
        Row(children: [Expanded(child: OutlinedButton.icon(onPressed: _pushBusy ? null : _enablePush, icon: const Icon(Icons.notifications_active), label: Text(_pushBusy ? '등록 중…' : '스마트폰 푸시 등록'))), const SizedBox(width: 10), OutlinedButton.icon(onPressed: _openBooking, icon: const Icon(Icons.open_in_new), label: const Text('예약 사이트'))]),
        const SizedBox(height: 20),
        Text('최근 확인 이력', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        ..._runs.map(_runTile),
      ],),
    );
  }

  Widget _statusCard(WatchMonitor m, bool available) => Card(color: available ? AppColors.leaf.withValues(alpha: .12) : null, child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text('현재 예약 가능 여부', style: Theme.of(context).textTheme.titleLarge),
    const SizedBox(height: 8),
    Row(children: [Icon(available ? Icons.check_circle : Icons.cancel, color: available ? AppColors.leaf : Colors.grey, size: 34), const SizedBox(width: 10), Text(m.status == 'available' ? '예약 가능' : m.status == 'unavailable' ? '예약 불가' : m.status == 'failed' ? '확인 실패' : '미확인', style: Theme.of(context).textTheme.headlineMedium)]),
    const SizedBox(height: 8),
    Text('마지막 확인: ${_format(m.lastCheckedAt)}'),
    if (m.lastError != null) Text('오류: ${m.lastError}', style: const TextStyle(color: Colors.red)),
  ])));
  Widget _field(String label,TextEditingController c)=>TextField(controller:c,decoration:InputDecoration(labelText:label));
  Widget _runTile(Map<String,dynamic> r){final ok=r['outcome']=='success'; return ListTile(dense:true,leading:Icon(ok?(r['matched']==true?Icons.check_circle:Icons.remove_circle):Icons.error_outline,color:ok?null:Colors.red),title:Text(r['summary'] as String? ?? r['error'] as String? ?? '확인'),subtitle:Text(_format(DateTime.tryParse(r['checked_at'] as String? ?? ''))));}
  String _format(DateTime? d)=>d==null?'없음':d.toLocal().toString().substring(0,16);
  Future<void> _openBooking() async { final uri=Uri.parse('https://valet.amanopark.co.kr/booking'); if(!await launchUrl(uri,mode:LaunchMode.externalApplication) && mounted) _snack('예약 사이트를 열 수 없습니다.'); }
}
