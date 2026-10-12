create extension if not exists pgcrypto;

create table if not exists public.watch_monitors (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  adapter_key text not null default 'amano_booking',
  name text not null default '인천공항 T2 아마노 발렛',
  config jsonb not null default '{}'::jsonb,
  enabled boolean not null default true,
  interval_minutes integer not null default 5 check (interval_minutes between 1 and 1440),
  status text not null default 'unknown' check (status in ('unknown','available','unavailable','failed')),
  last_checked_at timestamptz,
  last_success_at timestamptz,
  last_successful_match boolean,
  last_error text,
  transition_seq integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.watch_check_runs (
  id uuid primary key default gen_random_uuid(),
  monitor_id uuid not null references public.watch_monitors(id) on delete cascade,
  owner_id uuid not null references auth.users(id) on delete cascade,
  checked_at timestamptz not null default now(),
  outcome text not null check (outcome in ('success','failed')),
  matched boolean,
  http_status integer,
  duration_ms integer,
  summary text,
  error text,
  response_excerpt text,
  push_sent integer not null default 0,
  push_failed integer not null default 0
);

create table if not exists public.watch_push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  installation_id text not null,
  platform text not null default 'web',
  token text not null,
  enabled boolean not null default true,
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(owner_id, installation_id),
  unique(token)
);

create table if not exists public.watch_availability_events (
  id uuid primary key default gen_random_uuid(),
  monitor_id uuid not null references public.watch_monitors(id) on delete cascade,
  owner_id uuid not null references auth.users(id) on delete cascade,
  transition_seq integer not null,
  adapter_key text not null,
  title text not null,
  body text not null,
  url text,
  created_at timestamptz not null default now(),
  unique(monitor_id, transition_seq)
);

create table if not exists public.watch_notification_deliveries (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.watch_availability_events(id) on delete cascade,
  subscription_id uuid not null references public.watch_push_subscriptions(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','sent','failed','invalid_token')),
  error_code text,
  provider_message_id text,
  attempted_at timestamptz,
  created_at timestamptz not null default now(),
  unique(event_id, subscription_id)
);

create index if not exists watch_check_runs_monitor_checked_idx on public.watch_check_runs(monitor_id, checked_at desc);
create index if not exists watch_events_owner_created_idx on public.watch_availability_events(owner_id, created_at desc);

alter table public.watch_monitors enable row level security;
alter table public.watch_check_runs enable row level security;
alter table public.watch_push_subscriptions enable row level security;
alter table public.watch_availability_events enable row level security;
alter table public.watch_notification_deliveries enable row level security;

drop policy if exists "watch monitors own" on public.watch_monitors;
drop policy if exists "watch runs own read" on public.watch_check_runs;
drop policy if exists "watch subscriptions own" on public.watch_push_subscriptions;
drop policy if exists "watch events own read" on public.watch_availability_events;
drop policy if exists "watch deliveries own read" on public.watch_notification_deliveries;

create policy "watch monitors own" on public.watch_monitors for all using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy "watch runs own read" on public.watch_check_runs for select using (owner_id = auth.uid());
create policy "watch subscriptions own" on public.watch_push_subscriptions for all using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy "watch events own read" on public.watch_availability_events for select using (owner_id = auth.uid());
create policy "watch deliveries own read" on public.watch_notification_deliveries for select using (
  exists (select 1 from public.watch_availability_events e where e.id = event_id and e.owner_id = auth.uid())
);

create or replace function public.watchdog_touch_updated_at()
returns trigger language plpgsql as $$ begin new.updated_at = now(); return new; end $$;
drop trigger if exists watch_monitors_updated_at on public.watch_monitors;
create trigger watch_monitors_updated_at before update on public.watch_monitors for each row execute function public.watchdog_touch_updated_at();

create or replace function public.record_watchdog_check(
  p_monitor_id uuid,
  p_matched boolean,
  p_http_status integer,
  p_duration_ms integer,
  p_summary text,
  p_response_excerpt text default null
) returns jsonb language plpgsql security definer set search_path = public as $$
declare m public.watch_monitors%rowtype; seq integer; event_id uuid; transition boolean := false;
begin
  select * into m from public.watch_monitors where id = p_monitor_id for update;
  if not found then raise exception 'monitor_not_found'; end if;
  transition := p_matched and coalesce(m.last_successful_match, false) = false;
  seq := m.transition_seq + case when transition then 1 else 0 end;
  update public.watch_monitors set status = case when p_matched then 'available' else 'unavailable' end,
    last_checked_at = now(), last_success_at = now(), last_successful_match = p_matched,
    last_error = null, transition_seq = seq where id = p_monitor_id;
  insert into public.watch_check_runs(monitor_id, owner_id, outcome, matched, http_status, duration_ms, summary, response_excerpt)
    values (m.id, m.owner_id, 'success', p_matched, p_http_status, p_duration_ms, p_summary, p_response_excerpt);
  if transition then
    insert into public.watch_availability_events(monitor_id, owner_id, transition_seq, adapter_key, title, body, url)
      values (m.id, m.owner_id, seq, m.adapter_key, '예약 가능', coalesce(p_summary, '아마노 발렛 예약이 가능합니다.'), 'https://valet.amanopark.co.kr/booking')
      on conflict (monitor_id, transition_seq) do nothing returning id into event_id;
  end if;
  return jsonb_build_object('transition', transition, 'transition_seq', seq, 'event_id', event_id);
end $$;

create or replace function public.record_watchdog_failure(
  p_monitor_id uuid, p_error text, p_http_status integer default null, p_duration_ms integer default null
) returns void language plpgsql security definer set search_path = public as $$
declare m public.watch_monitors%rowtype;
begin
  select * into m from public.watch_monitors where id = p_monitor_id for update;
  if not found then raise exception 'monitor_not_found'; end if;
  update public.watch_monitors set status = 'failed', last_checked_at = now(), last_error = left(p_error, 1000) where id = p_monitor_id;
  insert into public.watch_check_runs(monitor_id, owner_id, outcome, http_status, duration_ms, error)
    values (m.id, m.owner_id, 'failed', p_http_status, p_duration_ms, left(p_error, 2000));
end $$;

revoke all on function public.record_watchdog_check(uuid, boolean, integer, integer, text, text) from public;
revoke all on function public.record_watchdog_failure(uuid, text, integer, integer) from public;
grant execute on function public.record_watchdog_check(uuid, boolean, integer, integer, text, text) to service_role;
grant execute on function public.record_watchdog_failure(uuid, text, integer, integer) to service_role;
