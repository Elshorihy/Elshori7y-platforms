-- Fix message editing so the RPC is deterministic and always returns one updated message row.
-- Safe to run after 015_chat_features.sql / 016_media_calls.sql.

drop function if exists public.edit_message(uuid,text);

create or replace function public.edit_message(
  p_message_id uuid,
  p_body text
)
returns public.messages
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_message public.messages;
  v_body text := nullif(btrim(coalesce(p_body, '')), '');
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  if v_body is null then
    raise exception 'message cannot be empty';
  end if;

  select * into v_message
  from public.messages
  where id = p_message_id
    and sender_id = auth.uid()
    and deleted_at is null;

  if not found then
    raise exception 'message cannot be edited';
  end if;

  if v_message.created_at < now() - interval '15 minutes' then
    raise exception 'message edit window expired';
  end if;

  update public.messages
  set body = v_body,
      edited_at = now()
  where id = p_message_id
  returning * into v_message;

  return v_message;
end;
$$;

grant execute on function public.edit_message(uuid,text) to authenticated;
