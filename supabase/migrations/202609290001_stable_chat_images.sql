alter table public.message_attachments
  add column width integer,
  add column height integer,
  add constraint message_attachments_width_positive
    check (width is null or width > 0),
  add constraint message_attachments_height_positive
    check (height is null or height > 0),
  add constraint message_attachments_dimensions_together
    check ((width is null) = (height is null));

drop function public.create_image_message(uuid, uuid, text, text, bigint);

create function public.create_image_message(
  p_room_id uuid,
  p_client_message_id uuid,
  p_storage_path text,
  p_mime_type text,
  p_size_bytes bigint,
  p_width integer default null,
  p_height integer default null
)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_message_id uuid;
begin
  if (p_width is null) <> (p_height is null)
     or p_width is not null and (p_width <= 0 or p_height <= 0) then
    raise exception 'Image dimensions must be positive or both null';
  end if;

  insert into public.messages (
    room_id, sender_id, client_message_id, message_type, body
  ) values (
    p_room_id, auth.uid(), p_client_message_id, 'image', '이미지'
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
    message_id, storage_path, mime_type, size_bytes, width, height
  ) values (
    v_message_id, p_storage_path, p_mime_type, p_size_bytes, p_width, p_height
  )
  on conflict (message_id) do nothing;

  return v_message_id;
end;
$$;

revoke all on function public.create_image_message(
  uuid, uuid, text, text, bigint, integer, integer
) from public;
grant execute on function public.create_image_message(
  uuid, uuid, text, text, bigint, integer, integer
) to authenticated;

drop function public.get_room_messages(uuid, timestamptz, uuid, integer);
drop function public.get_room_messages_after(uuid, timestamptz, uuid);

create function public.get_room_messages(
  p_room_id uuid,
  p_before_created_at timestamptz default null,
  p_before_id uuid default null,
  p_limit integer default 50
)
returns table (
  id uuid, room_id uuid, sender_id uuid, sender_nickname text,
  sender_avatar_path text, client_message_id uuid, message_type text,
  body text, created_at timestamptz, attachment_id uuid,
  attachment_bucket text, attachment_path text, attachment_mime_type text,
  attachment_size_bytes bigint, attachment_width integer,
  attachment_height integer, reply_to_message_id uuid,
  reply_sender_nickname text, reply_body text, reply_message_type text
)
language sql stable security invoker set search_path = public
as $$
  select m.id, m.room_id, m.sender_id, p.nickname, p.avatar_path,
         m.client_message_id, m.message_type, m.body, m.created_at,
         a.id, a.storage_bucket, a.storage_path, a.mime_type, a.size_bytes,
         a.width, a.height, m.reply_to_message_id,
         m.reply_sender_nickname, m.reply_body, m.reply_message_type
  from public.messages m
  join public.profiles p on p.id = m.sender_id
  left join public.message_attachments a on a.message_id = m.id
  where m.room_id = p_room_id
    and (p_before_created_at is null
      or (m.created_at, m.id) < (p_before_created_at, p_before_id))
  order by m.created_at desc, m.id desc
  limit least(greatest(p_limit, 1), 50);
$$;

create function public.get_room_messages_after(
  p_room_id uuid, p_after_created_at timestamptz, p_after_id uuid
)
returns table (
  id uuid, room_id uuid, sender_id uuid, sender_nickname text,
  sender_avatar_path text, client_message_id uuid, message_type text,
  body text, created_at timestamptz, attachment_id uuid,
  attachment_bucket text, attachment_path text, attachment_mime_type text,
  attachment_size_bytes bigint, attachment_width integer,
  attachment_height integer, reply_to_message_id uuid,
  reply_sender_nickname text, reply_body text, reply_message_type text
)
language sql stable security invoker set search_path = public
as $$
  select m.id, m.room_id, m.sender_id, p.nickname, p.avatar_path,
         m.client_message_id, m.message_type, m.body, m.created_at,
         a.id, a.storage_bucket, a.storage_path, a.mime_type, a.size_bytes,
         a.width, a.height, m.reply_to_message_id,
         m.reply_sender_nickname, m.reply_body, m.reply_message_type
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
