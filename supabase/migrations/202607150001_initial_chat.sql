create extension if not exists pgcrypto;

create type public.chat_room_type as enum ('public', 'direct', 'group');
create type public.room_member_role as enum ('member', 'admin');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  nickname text not null check (char_length(btrim(nickname)) between 2 and 20),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.chat_rooms (
  id uuid primary key default gen_random_uuid(),
  type public.chat_room_type not null,
  name text not null check (char_length(btrim(name)) between 1 and 100),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create table public.room_members (
  room_id uuid not null references public.chat_rooms(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role public.room_member_role not null default 'member',
  joined_at timestamptz not null default now(),
  primary key (room_id, user_id)
);

create table public.messages (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.chat_rooms(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete restrict,
  client_message_id uuid not null,
  message_type text not null default 'text' check (message_type = 'text'),
  body text not null check (char_length(btrim(body)) between 1 and 2000),
  created_at timestamptz not null default now(),
  unique (sender_id, client_message_id)
);

create index messages_room_cursor_idx
  on public.messages (room_id, created_at desc, id desc);

create index room_members_user_idx
  on public.room_members (user_id, room_id);

insert into public.chat_rooms (id, type, name)
values ('00000000-0000-4000-8000-000000000001', 'public', '모두의 채팅방')
on conflict (id) do nothing;

create schema if not exists private;

create or replace function private.is_room_member(
  p_room_id uuid,
  p_user_id uuid default auth.uid()
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.room_members
    where room_id = p_room_id and user_id = p_user_id
  );
$$;

revoke all on function private.is_room_member(uuid, uuid) from public;
grant usage on schema private to authenticated;
grant execute on function private.is_room_member(uuid, uuid) to authenticated;

alter table public.profiles enable row level security;
alter table public.chat_rooms enable row level security;
alter table public.room_members enable row level security;
alter table public.messages enable row level security;

revoke all on public.profiles, public.chat_rooms, public.room_members,
  public.messages from anon;
grant select, insert, update on public.profiles to authenticated;
grant select on public.chat_rooms to authenticated;
grant select, insert on public.room_members to authenticated;
grant select, insert on public.messages to authenticated;

create policy "authenticated users can read profiles"
on public.profiles for select to authenticated using (true);

create policy "users can create their own profile"
on public.profiles for insert to authenticated
with check (id = auth.uid());

create policy "users can update their own profile"
on public.profiles for update to authenticated
using (id = auth.uid()) with check (id = auth.uid());

create policy "users can read public or joined rooms"
on public.chat_rooms for select to authenticated
using (type = 'public' or private.is_room_member(id));

create policy "members can read memberships"
on public.room_members for select to authenticated
using (user_id = auth.uid() or private.is_room_member(room_id));

create policy "users can join public rooms as themselves"
on public.room_members for insert to authenticated
with check (
  user_id = auth.uid()
  and role = 'member'
  and exists (
    select 1 from public.chat_rooms room
    where room.id = room_id and room.type = 'public'
  )
);

create policy "members can read messages"
on public.messages for select to authenticated
using (private.is_room_member(room_id));

create policy "members can send as themselves"
on public.messages for insert to authenticated
with check (
  sender_id = auth.uid()
  and private.is_room_member(room_id)
  and message_type = 'text'
);

create or replace function public.get_room_messages(
  p_room_id uuid,
  p_before_created_at timestamptz default null,
  p_before_id uuid default null,
  p_limit integer default 50
)
returns table (
  id uuid,
  room_id uuid,
  sender_id uuid,
  sender_nickname text,
  client_message_id uuid,
  body text,
  created_at timestamptz
)
language sql
stable
security invoker
set search_path = public
as $$
  select m.id, m.room_id, m.sender_id, p.nickname, m.client_message_id,
         m.body, m.created_at
  from public.messages m
  join public.profiles p on p.id = m.sender_id
  where m.room_id = p_room_id
    and (
      p_before_created_at is null
      or (m.created_at, m.id) < (p_before_created_at, p_before_id)
    )
  order by m.created_at desc, m.id desc
  limit least(greatest(p_limit, 1), 50);
$$;

create or replace function public.get_room_messages_after(
  p_room_id uuid,
  p_after_created_at timestamptz,
  p_after_id uuid
)
returns table (
  id uuid,
  room_id uuid,
  sender_id uuid,
  sender_nickname text,
  client_message_id uuid,
  body text,
  created_at timestamptz
)
language sql
stable
security invoker
set search_path = public
as $$
  select m.id, m.room_id, m.sender_id, p.nickname, m.client_message_id,
         m.body, m.created_at
  from public.messages m
  join public.profiles p on p.id = m.sender_id
  where m.room_id = p_room_id
    and (m.created_at, m.id) > (p_after_created_at, p_after_id)
  order by m.created_at asc, m.id asc
  limit 200;
$$;

revoke all on function public.get_room_messages(uuid, timestamptz, uuid, integer)
  from public;
revoke all on function public.get_room_messages_after(uuid, timestamptz, uuid)
  from public;
grant execute on function public.get_room_messages(uuid, timestamptz, uuid, integer)
  to authenticated;
grant execute on function public.get_room_messages_after(uuid, timestamptz, uuid)
  to authenticated;

alter publication supabase_realtime add table public.messages;
