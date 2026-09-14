-- Fix: new-user signup was failing because the existing auth.users -> profiles trigger
-- inserts a profile before the old auth.users AFTER trigger could fill username/chat_key.
-- We therefore populate the identity on profiles BEFORE INSERT instead.

create or replace function public.fill_profile_identity()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  desired_username text;
begin
  if new.username is null or btrim(new.username) = '' then
    select lower(trim(coalesce(raw_user_meta_data->>'username', '')))
      into desired_username
    from auth.users
    where id = new.id;

    if desired_username !~ '^[a-z0-9_]{3,24}$' then
      desired_username := 'user_' || substr(replace(new.id::text, '-', ''), 1, 8);
    end if;

    new.username := desired_username;
  else
    new.username := lower(trim(new.username));
  end if;

  if new.chat_key is null or btrim(new.chat_key) = '' then
    new.chat_key := public.make_chat_key();
  end if;

  return new;
end;
$$;

drop trigger if exists z_fill_profile_identity on public.profiles;
create trigger z_fill_profile_identity
before insert on public.profiles
for each row execute function public.fill_profile_identity();

-- The old auth.users trigger is no longer needed and could run after the profile
-- has already been created. Remove it to avoid duplicate work.
drop trigger if exists z_ensure_profile_identity on auth.users;

-- Make sure existing rows are complete before enforcing NOT NULL.
update public.profiles
set username = lower(trim(username))
where username is not null;

update public.profiles
set username = 'user_' || substr(replace(id::text, '-', ''), 1, 8)
where username is null or btrim(username) = '';

update public.profiles
set chat_key = public.make_chat_key()
where chat_key is null or btrim(chat_key) = '';

alter table public.profiles
  alter column username set not null,
  alter column chat_key set not null;
