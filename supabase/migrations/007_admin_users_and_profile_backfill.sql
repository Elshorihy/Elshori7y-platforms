-- Admin/user visibility hardening.
-- Safe to run after the existing signup migrations.

-- 1) Make the admin check agree with the Admin app's allowlisted admin email,
--    while still honoring profiles.role = 'admin' when present.
create or replace function public.is_admin(user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select exists (
    select 1
    from auth.users u
    where u.id = user_id
      and lower(coalesce(u.email, '')) = 'sheenomatp@gmail.com'
  )
  or exists (
    select 1
    from public.profiles p
    where p.id = user_id
      and lower(coalesce(p.role, '')) = 'admin'
  );
$$;

grant execute on function public.is_admin(uuid) to authenticated;

-- 2) Backfill a profile for any Auth user that somehow exists without one.
--    This does not modify existing profile data.
insert into public.profiles (
  id,
  display_name,
  email,
  verification_status,
  username,
  chat_key
)
select
  u.id,
  coalesce(nullif(trim(u.raw_user_meta_data->>'display_name'), ''), 'User'),
  u.email,
  case when u.email_confirmed_at is not null then 'verified' else 'pending' end,
  'user_' || substr(replace(u.id::text, '-', ''), 1, 8),
  upper(substr(encode(gen_random_bytes(6), 'hex'), 1, 10))
from auth.users u
where not exists (
  select 1 from public.profiles p where p.id = u.id
)
on conflict (id) do nothing;

-- 3) Repair any accidental username/chat-key collisions created by the
--    backfill before the unique constraints are relied upon.
update public.profiles p
set username = 'user_' || substr(replace(p.id::text, '-', ''), 1, 8)
where p.username is null or btrim(p.username) = '';

update public.profiles p
set chat_key = upper(substr(encode(gen_random_bytes(6), 'hex'), 1, 10))
where p.chat_key is null or btrim(p.chat_key) = '';

-- 4) Ensure the signup trigger is present, so future Auth users get profiles.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  desired_username text;
  final_username text;
  generated_key text;
  suffix text;
begin
  desired_username := lower(trim(coalesce(new.raw_user_meta_data->>'username', '')));

  if desired_username ~ '^[a-z0-9_]{3,24}$' then
    final_username := desired_username;
  else
    final_username := 'user_' || substr(replace(new.id::text, '-', ''), 1, 8);
  end if;

  if exists (select 1 from public.profiles where lower(username) = lower(final_username) and id <> new.id) then
    suffix := substr(replace(new.id::text, '-', ''), 1, 5);
    final_username := substr(final_username, 1, 18) || '_' || suffix;
  end if;

  loop
    generated_key := upper(substr(encode(gen_random_bytes(6), 'hex'), 1, 10));
    exit when not exists (select 1 from public.profiles where chat_key = generated_key);
  end loop;

  insert into public.profiles (
    id,
    display_name,
    email,
    verification_status,
    username,
    chat_key
  )
  values (
    new.id,
    coalesce(nullif(trim(new.raw_user_meta_data->>'display_name'), ''), 'User'),
    new.email,
    case when new.email_confirmed_at is not null then 'verified' else 'pending' end,
    final_username,
    generated_key
  )
  on conflict (id) do update set
    email = excluded.email,
    display_name = coalesce(nullif(public.profiles.display_name, ''), excluded.display_name),
    username = coalesce(public.profiles.username, excluded.username),
    chat_key = coalesce(public.profiles.chat_key, excluded.chat_key);

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

-- 5) The Admin app needs to list all profiles, including pending users.
drop policy if exists profiles_admin_select on public.profiles;
create policy profiles_admin_select
on public.profiles
for select
to authenticated
using (public.is_admin(auth.uid()));
