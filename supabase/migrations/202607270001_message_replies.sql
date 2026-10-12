alter table public.messages
  add column reply_to_message_id uuid
    references public.messages(id) on delete set null,
  add column reply_sender_nickname text,
  add column reply_body text,
  add column reply_message_type text;

alter table public.messages
  add constraint messages_reply_snapshot_check check (
    (reply_sender_nickname is null and reply_body is null and reply_message_type is null)
    or (
      reply_sender_nickname is not null
      and reply_body is not null
      and reply_message_type in ('text', 'image')
    )
  );

create index messages_reply_to_idx
  on public.messages (reply_to_message_id)
  where reply_to_message_id is not null;

create or replace function public.populate_message_reply_snapshot()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  original public.messages%rowtype;
  original_nickname text;
begin
  if new.reply_to_message_id is null then
    new.reply_sender_nickname := null;
    new.reply_body := null;
    new.reply_message_type := null;
    return new;
  end if;

  select m.*
    into original
  from public.messages m
  where m.id = new.reply_to_message_id;

  if original.id is null or original.room_id <> new.room_id then
    raise exception 'reply target must belong to the same room'
      using errcode = '23514';
  end if;

  select p.nickname into original_nickname
  from public.profiles p
  where p.id = original.sender_id;

  new.reply_sender_nickname := original_nickname;
  new.reply_body :=
    case when original.message_type = 'image'
      then '사진'
      else left(original.body, 160)
    end;
  new.reply_message_type := original.message_type;
  return new;
end;
$$;

create trigger populate_message_reply_snapshot
before insert or update of reply_to_message_id on public.messages
for each row execute function public.populate_message_reply_snapshot();

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
  client_message_id uuid, message_type text, body text, created_at timestamptz,
  attachment_bucket text, attachment_path text, attachment_mime_type text,
  attachment_size_bytes bigint, reply_to_message_id uuid,
  reply_sender_nickname text, reply_body text, reply_message_type text
)
language sql stable security invoker set search_path = public
as $$
  select m.id, m.room_id, m.sender_id, p.nickname, m.client_message_id,
         m.message_type, m.body, m.created_at,
         a.storage_bucket, a.storage_path, a.mime_type, a.size_bytes,
         m.reply_to_message_id, m.reply_sender_nickname, m.reply_body,
         m.reply_message_type
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
  client_message_id uuid, message_type text, body text, created_at timestamptz,
  attachment_bucket text, attachment_path text, attachment_mime_type text,
  attachment_size_bytes bigint, reply_to_message_id uuid,
  reply_sender_nickname text, reply_body text, reply_message_type text
)
language sql stable security invoker set search_path = public
as $$
  select m.id, m.room_id, m.sender_id, p.nickname, m.client_message_id,
         m.message_type, m.body, m.created_at,
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

revoke all on function public.get_room_messages(uuid, timestamptz, uuid, integer) from public;
revoke all on function public.get_room_messages_after(uuid, timestamptz, uuid) from public;
grant execute on function public.get_room_messages(uuid, timestamptz, uuid, integer) to authenticated;
grant execute on function public.get_room_messages_after(uuid, timestamptz, uuid) to authenticated;
