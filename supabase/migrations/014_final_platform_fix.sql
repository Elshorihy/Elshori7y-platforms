-- FINAL PLATFORM FIX
-- Run this file once in Supabase SQL Editor.
-- It is intentionally self-contained so older 009-013 chat/verification
-- policies cannot leave the app in a broken state.

create or replace function public.is_conversation_member(p_user_id uuid,p_conversation_id uuid)
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.conversation_participants cp where cp.conversation_id=p_conversation_id and cp.user_id=p_user_id);
$$;
grant execute on function public.is_conversation_member(uuid,uuid) to authenticated;

do $$
declare p record;
begin
 for p in select schemaname,tablename,policyname from pg_policies where schemaname='public' and tablename in('conversation_participants','conversations','messages') loop
  execute format('drop policy if exists %I on %I.%I',p.policyname,p.schemaname,p.tablename);
 end loop;
end $$;

create policy conversation_participants_select_own on public.conversation_participants for select to authenticated using(user_id=auth.uid());
create policy conversations_select_member on public.conversations for select to authenticated using(public.is_conversation_member(auth.uid(),id) or public.is_admin(auth.uid()));
create policy messages_select_member on public.messages for select to authenticated using(public.is_conversation_member(auth.uid(),conversation_id) or public.is_admin(auth.uid()));
create policy messages_insert_member on public.messages for insert to authenticated with check(sender_id=auth.uid() and public.is_conversation_member(auth.uid(),conversation_id));
create policy messages_update_own on public.messages for update to authenticated using(sender_id=auth.uid() or public.is_admin(auth.uid())) with check(sender_id=auth.uid() or public.is_admin(auth.uid()));

grant select on public.conversations to authenticated;
grant select on public.conversation_participants to authenticated;
grant select,insert,update on public.messages to authenticated;

create or replace function public.get_my_conversations()
returns table(id uuid,type text,created_at timestamptz)
language sql stable security definer set search_path=public as $$
 select c.id,c.type,c.created_at
 from public.conversations c
 join public.conversation_participants cp on cp.conversation_id=c.id
 where cp.user_id=auth.uid()
 order by c.created_at desc;
$$;
grant execute on function public.get_my_conversations() to authenticated;

create or replace function public.sync_email_verification()
returns trigger language plpgsql security definer set search_path=public,auth as $$
begin
 update public.profiles set verification_status=case when new.email_confirmed_at is not null then 'verified' else 'pending' end where id=new.id;
 return new;
end;
$$;
drop trigger if exists sync_email_verification on auth.users;
create trigger sync_email_verification after update of email_confirmed_at on auth.users for each row execute function public.sync_email_verification();
update public.profiles p set verification_status=case when u.email_confirmed_at is not null then 'verified' else 'pending' end from auth.users u where u.id=p.id;

create or replace function public.create_direct_conversation_by_credentials(target_username text,target_chat_key text)
returns uuid language plpgsql security definer set search_path=public,auth as $$
declare me uuid:=auth.uid();target uuid;conversation_id uuid;
begin
 if me is null then raise exception 'يجب تسجيل الدخول أولاً'; end if;
 if not exists(select 1 from auth.users where id=me and email_confirmed_at is not null) then raise exception 'أكد البريد الإلكتروني أولاً'; end if;
 select p.id into target from public.profiles p join auth.users u on u.id=p.id where lower(p.username)=lower(trim(target_username)) and p.chat_key=upper(trim(target_chat_key)) and p.is_banned=false and u.email_confirmed_at is not null and p.id<>me;
 if target is null then raise exception 'اسم المستخدم أو مفتاح المستخدم غير صحيح'; end if;
 select c.id into conversation_id from public.conversations c join public.conversation_participants p1 on p1.conversation_id=c.id and p1.user_id=me join public.conversation_participants p2 on p2.conversation_id=c.id and p2.user_id=target where c.type='direct' limit 1;
 if conversation_id is not null then return conversation_id; end if;
 insert into public.conversations(type) values('direct') returning id into conversation_id;
 insert into public.conversation_participants(conversation_id,user_id) values(conversation_id,me),(conversation_id,target);
 return conversation_id;
end;
$$;
grant execute on function public.create_direct_conversation_by_credentials(text,text) to authenticated;

create or replace function public.send_message(p_conversation_id uuid,p_body text,p_message_type text default 'text')
returns public.messages language plpgsql security definer set search_path=public,auth as $$
declare v_user_id uuid:=auth.uid();v_message public.messages;v_type text:=lower(trim(coalesce(p_message_type,'text')));
begin
 if v_user_id is null then raise exception 'not authenticated'; end if;
 if not exists(select 1 from auth.users where id=v_user_id and email_confirmed_at is not null) then raise exception 'أكد البريد الإلكتروني أولاً'; end if;
 if exists(select 1 from public.profiles where id=v_user_id and is_banned=true) then raise exception 'account is banned'; end if;
 if p_conversation_id is null then raise exception 'conversation is required'; end if;
 if nullif(btrim(coalesce(p_body,'')),'') is null then raise exception 'message cannot be empty'; end if;
 if v_type<>'text' then raise exception 'unsupported message type'; end if;
 if not exists(select 1 from public.conversation_participants where conversation_id=p_conversation_id and user_id=v_user_id) then raise exception 'not a conversation member'; end if;
 insert into public.messages(conversation_id,sender_id,body,message_type) values(p_conversation_id,v_user_id,btrim(p_body),v_type) returning * into v_message;
 return v_message;
end;
$$;
grant execute on function public.send_message(uuid,text,text) to authenticated;

create or replace function public.admin_dashboard_stats()
returns jsonb language plpgsql stable security definer set search_path=public as $$
begin
 if not public.is_admin(auth.uid()) then raise exception 'not authorized'; end if;
 return jsonb_build_object('total_users',(select count(*) from public.profiles),'banned_users',(select count(*) from public.profiles where is_banned=true),'messages_last_7_days',(select count(*) from public.messages where created_at>=now()-interval '7 days'),'open_reports',(select count(*) from public.reports where resolved_at is null));
end;
$$;
grant execute on function public.admin_dashboard_stats() to authenticated;

alter table public.messages replica identity full;
alter table public.conversation_participants replica identity full;
do $$
begin
 if exists(select 1 from pg_publication where pubname='supabase_realtime') then
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='messages') then execute 'alter publication supabase_realtime add table public.messages'; end if;
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='conversation_participants') then execute 'alter publication supabase_realtime add table public.conversation_participants'; end if;
 end if;
end $$;
