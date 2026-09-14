-- Public username + private chat key.
-- Username can be shared publicly, but a direct chat requires BOTH username and key.

alter table public.profiles
  add column if not exists username text,
  add column if not exists chat_key text;

create unique index if not exists profiles_username_lower_unique
  on public.profiles (lower(username))
  where username is not null;

create unique index if not exists profiles_chat_key_unique
  on public.profiles (chat_key)
  where chat_key is not null;

create or replace function public.make_chat_key()
returns text
language plpgsql
as $$
declare
  v text;
begin
  loop
    v := upper(substr(encode(gen_random_bytes(6), 'hex'), 1, 10));
    exit when not exists (select 1 from public.profiles where chat_key = v);
  end loop;
  return v;
end;
$$;

create or replace function public.ensure_profile_identity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  desired_username text;
begin
  desired_username := lower(trim(coalesce(new.raw_user_meta_data->>'username', '')));

  if desired_username !~ '^[a-z0-9_]{3,24}$' then
    desired_username := 'user_' || substr(replace(new.id::text, '-', ''), 1, 8);
  end if;

  update public.profiles
  set username = coalesce(username, desired_username),
      chat_key = coalesce(chat_key, public.make_chat_key())
  where id = new.id;

  return new;
end;
$$;

drop trigger if exists z_ensure_profile_identity on auth.users;
create trigger z_ensure_profile_identity
after insert on auth.users
for each row execute function public.ensure_profile_identity();

-- Backfill profiles that already existed before this migration.
update public.profiles
set username = lower('user_' || substr(replace(id::text, '-', ''), 1, 8))
where username is null;

update public.profiles
set chat_key = public.make_chat_key()
where chat_key is null;

alter table public.profiles
  alter column username set not null,
  alter column chat_key set not null;

-- Do not expose chat_key through normal profile reads. The key is checked only inside this RPC.
create or replace function public.create_direct_conversation_by_credentials(
  target_username text,
  target_chat_key text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
  target uuid;
  conversation_id uuid;
begin
  if me is null then
    raise exception 'يجب تسجيل الدخول أولاً';
  end if;

  select id into target
  from public.profiles
  where lower(username) = lower(trim(target_username))
    and chat_key = upper(trim(target_chat_key))
    and verification_status = 'verified'
    and is_banned = false
    and id <> me;

  if target is null then
    raise exception 'اسم المستخدم أو مفتاح المستخدم غير صحيح';
  end if;

  select c.id into conversation_id
  from public.conversations c
  join public.conversation_participants p1 on p1.conversation_id = c.id and p1.user_id = me
  join public.conversation_participants p2 on p2.conversation_id = c.id and p2.user_id = target
  where c.type = 'direct'
  limit 1;

  if conversation_id is not null then
    return conversation_id;
  end if;

  insert into public.conversations(type) values ('direct') returning id into conversation_id;
  insert into public.conversation_participants(conversation_id, user_id) values (conversation_id, me), (conversation_id, target);
  return conversation_id;
end;
$$;

grant execute on function public.create_direct_conversation_by_credentials(text, text) to authenticated;
