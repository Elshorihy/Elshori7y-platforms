-- Fix the chat RLS recursion on conversation_participants.
-- Run this once in Supabase SQL Editor.
-- It replaces self-referencing participant policies with a SECURITY DEFINER membership helper.

create or replace function public.is_conversation_member(
  p_user_id uuid,
  p_conversation_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.conversation_participants cp
    where cp.conversation_id = p_conversation_id
      and cp.user_id = p_user_id
  );
$$;

grant execute on function public.is_conversation_member(uuid, uuid) to authenticated;

grant select on public.conversations to authenticated;
grant select, insert, update on public.messages to authenticated;
grant select on public.conversation_participants to authenticated;

-- Remove every existing policy on the chat tables so an older recursive policy
-- cannot continue to participate in the evaluation.
do $$
declare
  p record;
begin
  for p in
    select schemaname, tablename, policyname
    from pg_policies
    where schemaname = 'public'
      and tablename in ('conversation_participants', 'conversations', 'messages')
  loop
    execute format(
      'drop policy if exists %I on %I.%I',
      p.policyname,
      p.schemaname,
      p.tablename
    );
  end loop;
end $$;

-- Participants: a user can read only their own participant rows.
create policy conversation_participants_select_own
on public.conversation_participants
for select
to authenticated
using (
  user_id = auth.uid()
  or public.is_admin(auth.uid())
);

-- Conversations: membership is checked through the SECURITY DEFINER helper,
-- not by querying conversation_participants inside its own policy.
create policy conversations_select_member
on public.conversations
for select
to authenticated
using (
  public.is_conversation_member(auth.uid(), id)
  or public.is_admin(auth.uid())
);

-- Messages: members can read messages in their conversations.
create policy messages_select_member
on public.messages
for select
to authenticated
using (
  public.is_conversation_member(auth.uid(), conversation_id)
  or public.is_admin(auth.uid())
);

-- Messages: a member may send as themselves.
create policy messages_insert_member
on public.messages
for insert
to authenticated
with check (
  sender_id = auth.uid()
  and public.is_conversation_member(auth.uid(), conversation_id)
);

-- Keep direct message updates limited to the sender/admin. Read receipts are
-- handled by the existing SECURITY DEFINER mark_messages_read RPC.
create policy messages_update_own
on public.messages
for update
to authenticated
using (
  sender_id = auth.uid()
  or public.is_admin(auth.uid())
)
with check (
  sender_id = auth.uid()
  or public.is_admin(auth.uid())
);
