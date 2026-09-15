-- 012: final chat RLS cleanup + secure admin dashboard stats.
-- This migration removes every old chat policy first, so a stale recursive
-- policy cannot survive from an earlier migration.

do $$
declare
  p record;
begin
  for p in
    select schemaname, tablename, policyname
    from pg_policies
    where schemaname='public'
      and tablename in ('conversation_participants','conversations','messages')
  loop
    execute format('drop policy if exists %I on %I.%I',p.policyname,p.schemaname,p.tablename);
  end loop;
end $$;

-- Participant rows are read directly only for the signed-in user's own row.
-- No admin helper is called here, so this policy cannot recurse.
create policy conversation_participants_select_own
on public.conversation_participants
for select to authenticated
using (user_id=auth.uid());

-- Conversations and messages use the SECURITY DEFINER membership helper.
create policy conversations_select_member
on public.conversations
for select to authenticated
using (public.is_conversation_member(auth.uid(),id) or public.is_admin(auth.uid()));

create policy messages_select_member
on public.messages
for select to authenticated
using (public.is_conversation_member(auth.uid(),conversation_id) or public.is_admin(auth.uid()));

create policy messages_insert_member
on public.messages
for insert to authenticated
with check (
  sender_id=auth.uid()
  and public.is_conversation_member(auth.uid(),conversation_id)
);

create policy messages_update_own
on public.messages
for update to authenticated
using (sender_id=auth.uid() or public.is_admin(auth.uid()))
with check (sender_id=auth.uid() or public.is_admin(auth.uid()));

grant select on public.conversations to authenticated;
grant select,insert,update on public.messages to authenticated;
grant select on public.conversation_participants to authenticated;

-- Inbox loader used by the main app. It bypasses participant-table RLS safely
-- and returns only conversations belonging to the current authenticated user.
create or replace function public.get_my_conversations()
returns table(id uuid,type text,created_at timestamptz)
language sql
stable
security definer
set search_path=public
as $$
  select c.id,c.type,c.created_at
  from public.conversations c
  join public.conversation_participants cp on cp.conversation_id=c.id
  where cp.user_id=auth.uid()
  order by c.created_at desc;
$$;

grant execute on function public.get_my_conversations() to authenticated;

-- Dashboard counts are read through one SECURITY DEFINER function so the
-- admin UI does not depend on table-specific RLS policies for aggregate stats.
create or replace function public.admin_dashboard_stats()
returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  result jsonb;
  since_ts timestamptz := now()-interval '7 days';
begin
  if not public.is_admin(auth.uid()) then
    raise exception 'not authorized';
  end if;

  select jsonb_build_object(
    'pending_verifications',(select count(*) from public.profiles where verification_status='pending'),
    'open_reports',(select count(*) from public.reports where resolved_at is null),
    'messages_last_7_days',(select count(*) from public.messages where created_at>=since_ts),
    'verified_users',(select count(*) from public.profiles where verification_status='verified' and is_banned=false)
  ) into result;

  return result;
end;
$$;

grant execute on function public.admin_dashboard_stats() to authenticated;

-- Keep realtime enabled for the two tables used by the inbox.
alter table public.messages replica identity full;
alter table public.conversation_participants replica identity full;

do $$
begin
  if exists(select 1 from pg_publication where pubname='supabase_realtime') then
    if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='messages') then
      execute 'alter publication supabase_realtime add table public.messages';
    end if;
    if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='conversation_participants') then
      execute 'alter publication supabase_realtime add table public.conversation_participants';
    end if;
  end if;
end $$;
