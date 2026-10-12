import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const url = Deno.env.get('SUPABASE_URL')!;
const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const admin = createClient(url, serviceKey);
const scheduleGraceMs = 30_000;
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });

type Monitor = { id:string; owner_id:string; adapter_key:string; config:Record<string,unknown>; enabled:boolean; interval_minutes:number; last_checked_at:string|null };
type Result = { matched:boolean; summary:string; httpStatus:number; excerpt?:string };

async function amano(config:Record<string,unknown>): Promise<Result> {
  const date = String(config.entryDate ?? ''); const type = String(config.bookingType ?? 'BASIC');
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) throw new Error('entryDate 형식이 올바르지 않습니다.');
  const controller = new AbortController(); const timeout = setTimeout(() => controller.abort(), 15000);
  try {
    const response = await fetch(`https://api.amanopark.co.kr/api/web/setting/booking/check?date=${encodeURIComponent(date)}&type=${encodeURIComponent(type)}`, {signal: controller.signal, headers:{accept:'application/json'}});
    const text = await response.text();
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    let body: any; try { body = JSON.parse(text); } catch { throw new Error('JSON 파싱 실패'); }
    if (body?.result?.code !== 200 || typeof body?.data !== 'boolean') throw new Error('API 응답 형식 오류');
    return {matched: body.data, summary: body.data ? '예약 가능' : '예약 불가', httpStatus: response.status, excerpt: text.slice(0,500)};
  } finally { clearTimeout(timeout); }
}

async function userId(req: Request): Promise<string|null> {
  const auth = req.headers.get('authorization') ?? '';
  const token = auth.match(/^Bearer\s+(.+)$/i)?.[1];
  if (!token) return null;
  const {data, error} = await admin.auth.getUser(token);
  if (error) return null;
  return data.user?.id ?? null;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return json({ error: 'Method Not Allowed' }, 405);
  const auth = req.headers.get('authorization') ?? '';
  const cronSecret = Deno.env.get('WATCHDOG_CRON_SECRET');
  const privileged = auth === `Bearer ${serviceKey}` || (cronSecret && auth === `Bearer ${cronSecret}`);
  const input = await req.json().catch(() => ({}));
  let monitors: Monitor[] = [];
  if (privileged) {
    const q = admin.from('watch_monitors').select('*').eq('enabled', true);
    const {data,error} = await q; if (error) return json({error:error.message},500); monitors = data as Monitor[];
  } else {
    const owner = await userId(req); if (!owner) return json({error:'Unauthorized'},401);
    let q = admin.from('watch_monitors').select('*').eq('owner_id', owner);
    if (!input.monitor_id) q = q.eq('enabled', true); else q = q.eq('id', input.monitor_id);
    const {data,error} = await q; if (error) return json({error:error.message},500); monitors = data as Monitor[];
  }
  const now = Date.now(); const results:any[] = [];
  for (const monitor of monitors) {
    // Cron can fire a few milliseconds before the exact interval boundary.
    // Keep a small grace window so a 5-minute schedule is not skipped at 14:15:00.
    const minimumIntervalMs = Math.max(0, monitor.interval_minutes * 60_000 - scheduleGraceMs);
    if (!input.force && monitor.last_checked_at && now - Date.parse(monitor.last_checked_at) < minimumIntervalMs) continue;
    const started = Date.now();
    try {
      const result = monitor.adapter_key === 'amano_booking' ? await amano(monitor.config) : (() => { throw new Error(`알 수 없는 adapter_key: ${monitor.adapter_key}`); })();
      const {error} = await admin.rpc('record_watchdog_check', {p_monitor_id:monitor.id,p_matched:result.matched,p_http_status:result.httpStatus,p_duration_ms:Date.now()-started,p_summary:result.summary,p_response_excerpt:result.excerpt});
      if (error) throw error; results.push({id:monitor.id, ...result});
    } catch (e) {
      const message = e instanceof Error ? e.message : String(e);
      await admin.rpc('record_watchdog_failure', {p_monitor_id:monitor.id,p_error:message,p_duration_ms:Date.now()-started});
      results.push({id:monitor.id,error:message});
    }
  }
  return json({processed:results.length, results});
});
