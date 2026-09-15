-- 013: account verification is automatic email verification, not an admin action.
-- The admin dashboard should only moderate bans; it must not approve users.

create or replace function public.sync_email_verification()
returns trigger
language plpgsql
security definer
set search_path=public,auth
as $$
begin
  update public.profiles
  set verification_status = case
    when new.email_confirmed_at is not null then 'verified'
    else 'pending'
  end
  where id = new.id;
  return new;
end;
$$;

drop trigger if exists sync_email_verification on auth.users;
create trigger sync_email_verification
after update of email_confirmed_at on auth.users
for each row execute function public.sync_email_verification();

-- Existing accounts are synchronized immediately.
update public.profiles p
set verification_status = case
  when u.email_confirmed_at is not null then 'verified'
  else 'pending'
end
from auth.users u
where u.id=p.id;

-- Chat access is based on confirmed email + not banned, never on an admin approval.
create or replace function public.create_direct_conversation_by_credentials(
  target_username text,
  target_chat_key text
)
returns uuid
language plpgsql
security definer
set search_path=public,auth
as $$
declare
  me uuid := auth.uid();
  target uuid;
  conversation_id uuid;
  me_confirmed boolean;
  target_confirmed boolean;
begin
  if me is null then raise exception 'يجب تسجيل الدخول أولاً'; end if;

  select email_confirmed_at is not null into me_confirmed from auth.users where id=me;
  if not coalesce(me_confirmed,false) then
    raise exception 'أكد البريد الإلكتروني أولاً';
  end if;

  select p.id, (u.email_confirmed_at is not null)
    into target, target_confirmed
  from public.profiles p
  join auth.users u on u.id=p.id
  where lower(p.username)=lower(trim(target_username))
    and p.chat_key=upper(trim(target_chat_key))
    and p.is_banned=false
    and p.id<>me;

  if target is null or not coalesce(target_confirmed,false) then
    raise exception 'اسم المستخدم أو مفتاح المستخدم غير صحيح';
  end if;

  select c.id into conversation_id
  from public.conversations c
  join public.conversation_participants p1 on p1.conversation_id=c.id and p1.user_id=me
  join public.conversation_participants p2 on p2.conversation_id=c.id and p2.user_id=target
  where c.type='direct'
  limit 1;

  if conversation_id is not null then return conversation_id; end if;

  insert into public.conversations(type) values('direct') returning id into conversation_id;
  insert into public.conversation_participants(conversation_id,user_id)
  values(conversation_id,me),(conversation_id,target);
  return conversation_id;
end;
$$;

grant execute on function public.create_direct_conversation_by_credentials(text,text) to authenticated;

-- send_message uses the same real verification rule.
create or replace function public.send_message(
  p_conversation_id uuid,
  p_body text,
  p_message_type text default 'text'
)
returns public.messages
language plpgsql
security definer
set search_path=public,auth
as $$
declare
  v_user_id uuid:=auth.uid();
  v_message public.messages;
  v_confirmed boolean;
  v_type text:=lower(trim(coalesce(p_message_type,'text')));
begin
  if v_user_id is null then raise exception 'not authenticated'; end if;
  select email_confirmed_at is not null into v_confirmed from auth.users where id=v_user_id;
  if not coalesce(v_confirmed,false) then raise exception 'أكد البريد الإلكتروني أولاً'; end if;
  if exists(select 1 from public.profiles where id=v_user_id and is_banned) then raise exception 'account is banned'; end if;
  if p_conversation_id is null then raise exception 'conversation is required'; end if;
  if nullif(btrim(coalesce(p_body,'')),'') is null then raise exception 'message cannot be empty'; end if;
  if v_type<>'text' then raise exception 'unsupported message type'; end if;
  if not exists(select 1 from public.conversation_participants where conversation_id=p_conversation_id and user_id=v_user_id) then raise exception 'not a conversation member'; end if;
  insert into public.messages(conversation_id,sender_id,body,message_type)
  values(p_conversation_id,v_user_id,btrim(p_body),v_type)
  returning * into v_message;
  return v_message;
end;
$$;

grant execute on function public.send_message(uuid,text,text) to authenticated;

-- Dashboard is about platform health/moderation, not manual verification.
create or replace function public.admin_dashboard_stats()
returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
begin
  if not public.is_admin(auth.uid()) then raise exception 'not authorized'; end if;
  return jsonb_build_object(
    'total_users',(select count(*) from public.profiles),
    'banned_users',(select count(*) from public.profiles where is_banned=true),
    'messages_last_7_days',(select count(*) from public.messages where created_at>=now()-interval '7 days'),
    'open_reports',(select count(*) from public.reports where resolved_at is null)
  );
end;
$$;

grant execute on function public.admin_dashboard_stats() to authenticated;
