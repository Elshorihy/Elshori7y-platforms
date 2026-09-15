-- Media/call support. Run after 015_chat_features.sql.

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('chat-files','chat-files',false,52428800,array['image/*','audio/*','video/*','application/pdf','text/plain'])
on conflict(id) do update set file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists chat_files_read on storage.objects;
drop policy if exists chat_files_insert on storage.objects;
drop policy if exists chat_files_delete on storage.objects;
create policy chat_files_read on storage.objects for select to authenticated using(bucket_id='chat-files');
create policy chat_files_insert on storage.objects for insert to authenticated with check(bucket_id='chat-files' and owner_id=auth.uid()::text);
create policy chat_files_delete on storage.objects for delete to authenticated using(bucket_id='chat-files' and owner_id=auth.uid()::text);

create or replace function public.get_conversation_peer(p_conversation_id uuid)
returns uuid language sql stable security definer set search_path=public as $$
 select cp.user_id from public.conversation_participants cp where cp.conversation_id=p_conversation_id and cp.user_id<>auth.uid() limit 1;
$$;
grant execute on function public.get_conversation_peer(uuid) to authenticated;
