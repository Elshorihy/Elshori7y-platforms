-- Chat feature layer for ELshori7y
-- Safe to run after 014_final_platform_fix.sql

alter table public.messages
  add column if not exists edited_at timestamptz,
  add column if not exists deleted_at timestamptz,
  add column if not exists reply_to_id uuid references public.messages(id) on delete set null;

create index if not exists messages_conversation_created_idx
  on public.messages(conversation_id, created_at desc);

create table if not exists public.message_reactions (
  message_id uuid not null references public.messages(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  reaction text not null check (char_length(reaction) between 1 and 16),
  created_at timestamptz not null default now(),
  primary key(message_id,user_id,reaction)
);

alter table public.message_reactions enable row level security;
drop policy if exists message_reactions_select on public.message_reactions;
drop policy if exists message_reactions_write on public.message_reactions;
create policy message_reactions_select on public.message_reactions for select to authenticated using (
  exists(select 1 from public.messages m where m.id=message_id and public.is_conversation_member(auth.uid(),m.conversation_id))
);
create policy message_reactions_write on public.message_reactions for all to authenticated using (user_id=auth.uid()) with check (user_id=auth.uid());
grant select,insert,delete on public.message_reactions to authenticated;

create or replace function public.edit_message(p_message_id uuid,p_body text)
returns public.messages language plpgsql security definer set search_path=public,auth as $$
declare v public.messages;
begin
  if not exists(select 1 from public.messages where id=p_message_id and sender_id=auth.uid() and deleted_at is null and created_at >= now()-interval '15 minutes') then
    raise exception 'message cannot be edited';
  end if;
  if nullif(btrim(coalesce(p_body,'')),'') is null then raise exception 'message cannot be empty'; end if;
  update public.messages set body=btrim(p_body),edited_at=now() where id=p_message_id returning * into v;
  return v;
end;
$$;
grant execute on function public.edit_message(uuid,text) to authenticated;

create or replace function public.delete_message_for_everyone(p_message_id uuid)
returns public.messages language plpgsql security definer set search_path=public,auth as $$
declare v public.messages;
begin
  if not exists(select 1 from public.messages where id=p_message_id and sender_id=auth.uid() and deleted_at is null) then
    raise exception 'message cannot be deleted';
  end if;
  update public.messages set deleted_at=now(),body=null where id=p_message_id returning * into v;
  return v;
end;
$$;
grant execute on function public.delete_message_for_everyone(uuid) to authenticated;

create or replace function public.toggle_message_reaction(p_message_id uuid,p_reaction text)
returns boolean language plpgsql security definer set search_path=public,auth as $$
declare exists_row boolean;
begin
 if not exists(select 1 from public.messages m where m.id=p_message_id and public.is_conversation_member(auth.uid(),m.conversation_id)) then raise exception 'not authorized'; end if;
 select exists(select 1 from public.message_reactions where message_id=p_message_id and user_id=auth.uid() and reaction=p_reaction) into exists_row;
 if exists_row then delete from public.message_reactions where message_id=p_message_id and user_id=auth.uid() and reaction=p_reaction; return false;
 else insert into public.message_reactions(message_id,user_id,reaction) values(p_message_id,auth.uid(),p_reaction); return true; end if;
end;
$$;
grant execute on function public.toggle_message_reaction(uuid,text) to authenticated;

create table if not exists public.system_settings (
  key text primary key,
  value jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
alter table public.system_settings enable row level security;
drop policy if exists system_settings_admin on public.system_settings;
create policy system_settings_admin on public.system_settings for all to authenticated using(public.is_admin(auth.uid())) with check(public.is_admin(auth.uid()));
grant select,insert,update,delete on public.system_settings to authenticated;

create table if not exists public.cms_pages (
  slug text primary key,
  title text not null,
  body text not null default '',
  published boolean not null default true,
  updated_at timestamptz not null default now()
);
alter table public.cms_pages enable row level security;
drop policy if exists cms_pages_public_read on public.cms_pages;
drop policy if exists cms_pages_admin_write on public.cms_pages;
create policy cms_pages_public_read on public.cms_pages for select to anon,authenticated using(published=true or public.is_admin(auth.uid()));
create policy cms_pages_admin_write on public.cms_pages for all to authenticated using(public.is_admin(auth.uid())) with check(public.is_admin(auth.uid()));
grant select on public.cms_pages to anon,authenticated;
grant insert,update,delete on public.cms_pages to authenticated;

alter table public.message_reactions replica identity full;
do $$ begin
 if exists(select 1 from pg_publication where pubname='supabase_realtime') and not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='message_reactions') then
   execute 'alter publication supabase_realtime add table public.message_reactions';
 end if;
end $$;
