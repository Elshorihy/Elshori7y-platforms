-- Final signup hardening: make the auth.users -> profiles trigger self-contained.
-- This avoids depending on the older identity trigger or make_chat_key() during signup.

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

  -- Never let a duplicate username abort auth signup. If the requested name
  -- is already used, append a short unique suffix while keeping it valid.
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
    username = coalesce(public.profiles.username, excluded.username),
    chat_key = coalesce(public.profiles.chat_key, excluded.chat_key);

  return new;
end;
$$;

-- Remove legacy identity triggers. handle_new_user now does everything required.
drop trigger if exists z_ensure_profile_identity on auth.users;
drop trigger if exists z_fill_profile_identity on public.profiles;

-- Make sure the intended signup trigger exists exactly once.
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();
