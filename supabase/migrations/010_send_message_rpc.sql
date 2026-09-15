-- Reliable message sending through a SECURITY DEFINER RPC.
-- This avoids client-side RLS evaluation blocking inserts while still enforcing
-- authentication, active verification, ban status, and conversation membership.

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
    coalesce(nullif(btrim(p_message_type), ''), 'text')
  )
  returning * into v_message;

  return v_message;
end;
$$;

grant execute on function public.send_message(uuid, text, text) to authenticated;
