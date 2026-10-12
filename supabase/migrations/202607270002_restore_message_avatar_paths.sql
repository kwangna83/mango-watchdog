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
  sender_avatar_path text,
  client_message_id uuid,
  message_type text,
  body text,
  created_at timestamptz,
  attachment_bucket text,
  attachment_path text,
  attachment_mime_type text,
  attachment_size_bytes bigint,
  reply_to_message_id uuid,
  reply_sender_nickname text,
  reply_body text,
  reply_message_type text
)
language sql
stable
security invoker
set search_path = public
as $$
  select m.id, m.room_id, m.sender_id, p.nickname, p.avatar_path,
         m.client_message_id, m.message_type, m.body, m.created_at,
         a.storage_bucket, a.storage_path, a.mime_type, a.size_bytes,
         m.reply_to_message_id, m.reply_sender_nickname, m.reply_body,
         m.reply_message_type
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
  sender_avatar_path text,
  client_message_id uuid,
  message_type text,
  body text,
  created_at timestamptz,
  attachment_bucket text,
  attachment_path text,
  attachment_mime_type text,
  attachment_size_bytes bigint,
  reply_to_message_id uuid,
  reply_sender_nickname text,
  reply_body text,
  reply_message_type text
)
language sql
stable
security invoker
set search_path = public
as $$
  select m.id, m.room_id, m.sender_id, p.nickname, p.avatar_path,
         m.client_message_id, m.message_type, m.body, m.created_at,
         a.storage_bucket, a.storage_path, a.mime_type, a.size_bytes,
         m.reply_to_message_id, m.reply_sender_nickname, m.reply_body,
         m.reply_message_type
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
