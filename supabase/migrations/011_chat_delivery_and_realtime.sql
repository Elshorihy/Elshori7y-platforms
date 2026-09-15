-- Chat delivery hardening: make the realtime tables part of the Supabase
-- realtime publication. The UI also refreshes its inbox periodically so a
-- temporary realtime disconnect cannot hide a new message.

alter table public.messages replica identity full;
alter table public.conversation_participants replica identity full;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (
      select 1
      from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'messages'
    ) then
      execute 'alter publication supabase_realtime add table public.messages';
    end if;

    if not exists (
      select 1
      from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'conversation_participants'
    ) then
      execute 'alter publication supabase_realtime add table public.conversation_participants';
    end if;
  end if;
end $$;

-- A verified user's inbox is allowed to read its own participant rows.
-- Keep this policy explicit and non-recursive.
drop policy if exists conversation_participants_select_own on public.conversation_participants;
create policy conversation_participants_select_own
on public.conversation_participants
for select
to authenticated
using (
  user_id = auth.uid()
  or public.is_admin(auth.uid())
);

-- Make the sender RPC return a deterministic single row and prevent arbitrary
-- message types from being injected by the client.
create or replace function public.send_message(
  p_conversation_id uuid,
  p_body text,
  p_message_type text default 'text'
)
returns public.messages
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_message public.messages;
  v_type text := lower(trim(coalesce(p_message_type, 'text')));
begin
  if v_user_id is null then
    raise exception 'not authenticated';
  end if;

  if not public.is_active_verified_user(v_user_id) then
    raise exception 'account is not verified or is banned';
  end if;

  if p_conversation_id is null then
    raise exception 'conversation is required';
  end if;

  if nullif(btrim(coalesce(p_body, '')), '') is null then
    raise exception 'message cannot be empty';
  end if;

  if v_type <> 'text' then
    raise exception 'unsupported message type';
  end if;

  if not exists (
    select 1
    from public.conversation_participants cp
    where cp.conversation_id = p_conversation_id
      and cp.user_id = v_user_id
  ) then
    raise exception 'not a conversation member';
  end if;

  insert into public.messages (
    conversation_id,
    sender_id,
    body,
    message_type
  )
  values (
    p_conversation_id,
    v_user_id,
    btrim(p_body),
    v_type
  )
  returning * into v_message;

  return v_message;
end;
$$;

grant execute on function public.send_message(uuid, text, text) to authenticated;
