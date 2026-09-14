-- Fix signup after adding required username/chat_key columns.
-- The original handle_new_user() was inserting profiles without the new required fields.
-- Populate username + chat_key directly in the auth.users signup trigger.

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  desired_username text;
  generated_username text;
  generated_chat_key text;
begin
  desired_username := lower(trim(coalesce(new.raw_user_meta_data->>'username', '')));

  if desired_username !~ '^[a-z0-9_]{3,24}$' then
    generated_username := 'user_' || substr(replace(new.id::text, '-', ''), 1, 8);
  else
    generated_username := desired_username;
  end if;

  generated_chat_key := public.make_chat_key();

  insert into public.profiles(
    id,
    display_name,
    email,
    verification_status,
    username,
    chat_key
  )
  values(
    new.id,
    coalesce(new.raw_user_meta_data->>'display_name', 'User'),
    new.email,
    case
      when new.email_confirmed_at is not null then 'verified'
      else 'pending'
    end,
    generated_username,
    generated_chat_key
  )
  on conflict(id)
  do update set
    email = excluded.email,
    username = coalesce(public.profiles.username, excluded.username),
    chat_key = coalesce(public.profiles.chat_key, excluded.chat_key);

  return new;
end;
$$;

-- Identity is now populated by handle_new_user(), so the extra auth.users trigger
-- and profiles BEFORE INSERT trigger are no longer needed.
drop trigger if exists z_ensure_profile_identity on auth.users;
drop trigger if exists z_fill_profile_identity on public.profiles;
