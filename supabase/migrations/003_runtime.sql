create or replace function public.create_direct_conversation(other_user_id uuid)
returns uuid language plpgsql security definer set search_path=public as $$
declare existing_id uuid; new_id uuid;
begin
 if auth.uid() is null or not public.is_active_verified_user(auth.uid()) then raise exception 'not allowed'; end if;
 if not public.is_active_verified_user(other_user_id) or other_user_id=auth.uid() then raise exception 'invalid recipient'; end if;
 select c.id into existing_id from conversations c join conversation_participants a on a.conversation_id=c.id and a.user_id=auth.uid() join conversation_participants b on b.conversation_id=c.id and b.user_id=other_user_id where c.type='direct' limit 1;
 if existing_id is not null then return existing_id; end if;
 insert into conversations(type) values('direct') returning id into new_id;
 insert into conversation_participants(conversation_id,user_id) values(new_id,auth.uid()),(new_id,other_user_id);
 return new_id;
end; $$;

grant execute on function public.create_direct_conversation(uuid) to authenticated;

create or replace function public.mark_messages_read(conversation_uuid uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
 update messages set read_at=coalesce(read_at,now()) where conversation_id=conversation_uuid and sender_id<>auth.uid() and exists(select 1 from conversation_participants where conversation_id=conversation_uuid and user_id=auth.uid());
end; $$;

grant execute on function public.mark_messages_read(uuid) to authenticated;

drop policy if exists profiles_admin_select on public.profiles;
create policy profiles_admin_select on public.profiles for select using(public.is_admin(auth.uid()));
