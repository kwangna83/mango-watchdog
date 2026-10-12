alter table public.messages
  drop constraint if exists messages_message_type_check;

alter table public.messages
  add constraint messages_message_type_check
  check (message_type in ('text', 'image'));

create table public.message_attachments (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null unique
    references public.messages(id) on delete cascade,
  storage_bucket text not null default 'chat-images'
    check (storage_bucket = 'chat-images'),
  storage_path text not null unique,
  mime_type text not null
    check (mime_type in ('image/jpeg', 'image/png', 'image/webp')),
  size_bytes bigint not null check (size_bytes between 1 and 10485760),
  created_at timestamptz not null default now()
);

alter table public.message_attachments enable row level security;

grant select, insert on public.message_attachments to authenticated;

create policy "members can read message attachments"
on public.message_attachments for select to authenticated
using (
  exists (
    select 1
    from public.messages message
    where message.id = message_id
      and private.is_room_member(message.room_id)
  )
);

create policy "members can attach to their own messages"
on public.message_attachments for insert to authenticated
with check (
  exists (
    select 1
    from public.messages message
    where message.id = message_id
      and message.sender_id = auth.uid()
      and message.message_type = 'image'
      and private.is_room_member(message.room_id)
  )
);

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'chat-images',
  'chat-images',
  false,
  10485760,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create policy "room members can read chat images"
on storage.objects for select to authenticated
using (
  bucket_id = 'chat-images'
  and private.is_room_member(((storage.foldername(name))[1])::uuid)
);

create policy "room members can upload their own chat images"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'chat-images'
  and private.is_room_member(((storage.foldername(name))[1])::uuid)
  and (storage.foldername(name))[2] = auth.uid()::text
);

create policy "users can delete their own chat images"
on storage.objects for delete to authenticated
using (
  bucket_id = 'chat-images'
  and (storage.foldername(name))[2] = auth.uid()::text
);

create or replace function public.create_image_message(
  p_room_id uuid,
  p_client_message_id uuid,
  p_storage_path text,
  p_mime_type text,
  p_size_bytes bigint
)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_message_id uuid;
begin
  insert into public.messages (
    room_id,
    sender_id,
    client_message_id,
    message_type,
    body
  ) values (
    p_room_id,
    auth.uid(),
    p_client_message_id,
    'image',
    '이미지'
  )
  on conflict (sender_id, client_message_id) do nothing
  returning id into v_message_id;

  if v_message_id is null then
    select id into v_message_id
    from public.messages
    where sender_id = auth.uid()
      and client_message_id = p_client_message_id;
  end if;

  if not exists (
    select 1 from public.messages
    where id = v_message_id
      and room_id = p_room_id
      and sender_id = auth.uid()
      and message_type = 'image'
  ) then
    raise exception 'Image message retry does not match the original message';
  end if;

  insert into public.message_attachments (
    message_id,
    storage_path,
    mime_type,
    size_bytes
  ) values (
    v_message_id,
    p_storage_path,
    p_mime_type,
    p_size_bytes
  )
  on conflict (message_id) do nothing;

  return v_message_id;
end;
$$;

revoke all on function public.create_image_message(uuid, uuid, text, text, bigint)
  from public;
grant execute on function public.create_image_message(uuid, uuid, text, text, bigint)
  to authenticated;

drop function public.get_room_messages(uuid, timestamptz, uuid, integer);
drop function public.get_room_messages_after(uuid, timestamptz, uuid);

create function public.get_room_messages(
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
  message_type text,
  body text,
  created_at timestamptz,
  attachment_bucket text,
  attachment_path text,
  attachment_mime_type text,
  attachment_size_bytes bigint
)
language sql
stable
security invoker
set search_path = public
as $$
  select m.id, m.room_id, m.sender_id, p.nickname, m.client_message_id,
         m.message_type, m.body, m.created_at,
         a.storage_bucket, a.storage_path, a.mime_type, a.size_bytes
  from public.messages m
  join public.profiles p on p.id = m.sender_id
  left join public.message_attachments a on a.message_id = m.id
  where m.room_id = p_room_id
    and (
      p_before_created_at is null
      or (m.created_at, m.id) < (p_before_created_at, p_before_id)
    )
  order by m.created_at desc, m.id desc
  limit least(greatest(p_limit, 1), 50);
$$;

create function public.get_room_messages_after(
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
  message_type text,
  body text,
  created_at timestamptz,
  attachment_bucket text,
  attachment_path text,
  attachment_mime_type text,
  attachment_size_bytes bigint
)
language sql
stable
security invoker
set search_path = public
as $$
  select m.id, m.room_id, m.sender_id, p.nickname, m.client_message_id,
         m.message_type, m.body, m.created_at,
         a.storage_bucket, a.storage_path, a.mime_type, a.size_bytes
  from public.messages m
  join public.profiles p on p.id = m.sender_id
  left join public.message_attachments a on a.message_id = m.id
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
