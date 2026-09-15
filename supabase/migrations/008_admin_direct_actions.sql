-- Direct admin actions used by the web dashboard.
-- Run this once in Supabase SQL Editor after migration 007.
-- No service-role key is used in the browser.

-- Profiles: admins can update verification/ban fields.
drop policy if exists profiles_admin_update on public.profiles;
create policy profiles_admin_update
on public.profiles
for update
to authenticated
using (public.is_admin(auth.uid()))
with check (public.is_admin(auth.uid()));

grant select, update on public.profiles to authenticated;

-- Reports: keep report reads/admin resolution protected by the same admin check.
drop policy if exists reports_select on public.reports;
drop policy if exists reports_update on public.reports;
drop policy if exists reports_admin_select on public.reports;
drop policy if exists reports_admin_update on public.reports;

create policy reports_admin_select
on public.reports
for select
to authenticated
using (public.is_admin(auth.uid()));

create policy reports_admin_update
on public.reports
for update
to authenticated
using (public.is_admin(auth.uid()))
with check (public.is_admin(auth.uid()));

grant select, update on public.reports to authenticated;
