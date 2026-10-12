create table public.message_read_positions (
  room_id uuid not null references public.chat_rooms(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  last_read_created_at timestamptz not null,
  last_read_message_id uuid not null references public.messages(id) on delete cascade,
  updated_at timestamptz not null default now(),
  primary key (room_id, user_id)
);

create index message_read_positions_user_idx
  on public.message_read_positions (user_id, room_id);

alter table public.message_read_positions enable row level security;

revoke all on public.message_read_positions from anon;
grant select on public.message_read_positions to authenticated;

create policy "users can read their own message position"
on public.message_read_positions for select to authenticated
using (user_id = (select auth.uid()));

create or replace function public.mark_message_read(
  p_room_id uuid,
  p_message_id uuid,
  p_created_at timestamptz
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not private.is_room_member(p_room_id) then
    raise exception 'room membership required';
  end if;

  if not exists (
    select 1 from public.messages
    where id = p_message_id
      and room_id = p_room_id
      and created_at = p_created_at
  ) then
    raise exception 'invalid message position';
  end if;

  insert into public.message_read_positions (
    room_id,
    user_id,
    last_read_created_at,
    last_read_message_id,
    updated_at
  ) values (
    p_room_id,
    auth.uid(),
    p_created_at,
    p_message_id,
    now()
  )
  on conflict (room_id, user_id) do update set
    last_read_created_at = excluded.last_read_created_at,
    last_read_message_id = excluded.last_read_message_id,
    updated_at = now()
  where (
    message_read_positions.last_read_created_at,
    message_read_positions.last_read_message_id
  ) < (
    excluded.last_read_created_at,
    excluded.last_read_message_id
  );
end;
$$;

revoke all on function public.mark_message_read(uuid, uuid, timestamptz)
  from public;
grant execute on function public.mark_message_read(uuid, uuid, timestamptz)
  to authenticated;
