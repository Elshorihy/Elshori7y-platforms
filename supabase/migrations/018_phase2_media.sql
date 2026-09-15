-- Phase 2: secure chat media access helpers.
-- Files are stored under: <user_id>/<conversation_id>/<uuid>-<filename>
-- Run after 016_media_calls.sql.

drop policy if exists chat_files_read on storage.objects;
drop policy if exists chat_files_insert on storage.objects;
drop policy if exists chat_files_delete on storage.objects;

create policy chat_files_read on storage.objects
for select to authenticated
using (
  bucket_id = 'chat-files'
  and (
    owner_id = auth.uid()::text
    or (
      split_part(name, '/', 2) ~ '^[0-9a-fA-F-]{36}$'
      and public.is_conversation_member(auth.uid(), split_part(name, '/', 2)::uuid)
    )
  )
);

create policy chat_files_insert on storage.objects
for insert to authenticated
with check (
  bucket_id = 'chat-files'
  and owner_id = auth.uid()::text
  and split_part(name, '/', 1) = auth.uid()::text
  and split_part(name, '/', 2) ~ '^[0-9a-fA-F-]{36}$'
  and public.is_conversation_member(auth.uid(), split_part(name, '/', 2)::uuid)
);

create policy chat_files_delete on storage.objects
for delete to authenticated
using (bucket_id = 'chat-files' and owner_id = auth.uid()::text);
