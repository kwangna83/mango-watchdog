drop policy if exists "members can send as themselves"
on public.messages;

create policy "members can send as themselves"
on public.messages for insert to authenticated
with check (
  sender_id = auth.uid()
  and private.is_room_member(room_id)
  and message_type in ('text', 'image')
);
