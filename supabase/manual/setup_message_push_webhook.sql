-- MangoTalk message push webhook fallback.
-- Use this only when the managed `supabase_functions` schema is unavailable.
--
-- Before running in the Supabase SQL Editor, replace the placeholder below with
-- the complete `sb_secret_...` key from Project Settings > API Keys.

do $$
declare
  push_edge_function_secret constant text := 'PASTE_SB_SECRET_KEY_HERE';
begin
  if push_edge_function_secret !~ '^sb_secret_' then
    raise exception
      'Replace PASTE_SB_SECRET_KEY_HERE with the complete sb_secret_... key';
  end if;

  if exists (
    select 1
    from vault.decrypted_secrets
    where name = 'mangotalk_push_edge_function_secret'
  ) then
    raise exception
      'Vault secret mangotalk_push_edge_function_secret already exists; rotate it instead of creating a duplicate';
  end if;

  perform vault.create_secret(
    push_edge_function_secret,
    'mangotalk_push_edge_function_secret',
    'Authenticates the messages INSERT trigger to send-message-push'
  );
end;
$$;

create or replace function private.notify_message_push()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, vault, net
as $$
declare
  edge_function_secret text;
  request_id bigint;
begin
  select decrypted_secret
    into edge_function_secret
  from vault.decrypted_secrets
  where name = 'mangotalk_push_edge_function_secret'
  order by created_at desc
  limit 1;

  if edge_function_secret is null then
    raise warning 'MangoTalk push webhook secret is missing; message % was not queued', new.id;
    return new;
  end if;

  select net.http_post(
    url := 'https://qmzpyoulawdlecmtjkib.supabase.co/functions/v1/send-message-push',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'apikey', edge_function_secret
    ),
    body := jsonb_build_object(
      'type', 'INSERT',
      'table', tg_table_name,
      'schema', tg_table_schema,
      'record', to_jsonb(new),
      'old_record', null
    ),
    timeout_milliseconds := 5000
  ) into request_id;

  return new;
exception
  when others then
    -- Push delivery must never block saving a chat message.
    raise warning 'Failed to queue MangoTalk push for message %: %', new.id, sqlerrm;
    return new;
end;
$$;

revoke all on function private.notify_message_push() from public;

drop trigger if exists messages_insert_send_push on public.messages;

create trigger messages_insert_send_push
after insert on public.messages
for each row
execute function private.notify_message_push();

comment on function private.notify_message_push() is
  'Queues the send-message-push Edge Function through pg_net when a message is inserted.';

-- Verification (the trigger should be listed as enabled):
select trigger_name, event_manipulation, action_timing
from information_schema.triggers
where event_object_schema = 'public'
  and event_object_table = 'messages'
  and trigger_name = 'messages_insert_send_push';

-- Recent pg_net responses can be inspected after sending a test message:
-- select id, status_code, error_msg, content, created
-- from net._http_response
-- order by created desc
-- limit 10;

-- Rollback (run separately if push notifications must be disabled):
-- drop trigger if exists messages_insert_send_push on public.messages;
-- drop function if exists private.notify_message_push();
-- select vault.delete_secret(id)
-- from vault.decrypted_secrets
-- where name = 'mangotalk_push_edge_function_secret';
