create table if not exists public.push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  installation_id uuid not null,
  platform text not null check (platform in ('web', 'android', 'ios')),
  token text not null check (char_length(token) between 20 and 4096),
  enabled boolean not null default true,
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, installation_id),
  unique (token)
);

create index if not exists push_subscriptions_user_enabled_idx
  on public.push_subscriptions (user_id, enabled)
  where enabled;

create table if not exists public.push_deliveries (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references public.messages(id) on delete cascade,
  subscription_id uuid not null references public.push_subscriptions(id) on delete cascade,
  status text not null default 'pending'
    check (status in ('pending', 'sent', 'failed', 'invalid_token')),
  provider_message_id text,
  error_code text,
  attempted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (message_id, subscription_id)
);

alter table public.push_subscriptions enable row level security;
alter table public.push_deliveries enable row level security;

drop policy if exists "users can read own push subscriptions"
  on public.push_subscriptions;

create policy "users can read own push subscriptions"
  on public.push_subscriptions for select
  to authenticated
  using (user_id = auth.uid());

drop policy if exists "users can create own push subscriptions"
  on public.push_subscriptions;

create policy "users can create own push subscriptions"
  on public.push_subscriptions for insert
  to authenticated
  with check (user_id = auth.uid());

drop policy if exists "users can update own push subscriptions"
  on public.push_subscriptions;

create policy "users can update own push subscriptions"
  on public.push_subscriptions for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "users can delete own push subscriptions"
  on public.push_subscriptions;

create policy "users can delete own push subscriptions"
  on public.push_subscriptions for delete
  to authenticated
  using (user_id = auth.uid());

comment on table public.push_subscriptions is
  'FCM registration tokens owned by an authenticated user installation.';
comment on table public.push_deliveries is
  'Server-only idempotency and delivery status for message push notifications.';
