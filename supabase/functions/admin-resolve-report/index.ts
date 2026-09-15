import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const url = Deno.env.get('SUPABASE_URL')!;
const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json' },
  });
}

Deno.serve(async req => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return json({ error: 'method not allowed' }, 405);

  const jwt = (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '');
  if (!jwt) return json({ error: 'Unauthorized' }, 401);

  const body = await req.json().catch(() => ({}));
  const { report_id } = body as { report_id?: string };
  if (!report_id) return json({ error: 'report_id is required' }, 400);

  const db = createClient(url, key);
  const { data: authData, error: authError } = await db.auth.getUser(jwt);
  const adminUser = authData.user;
  if (authError || !adminUser) return json({ error: 'Unauthorized' }, 401);

  const email = (adminUser.email ?? '').toLowerCase();
  let isAdmin = email === 'sheenomatp@gmail.com';

  if (!isAdmin) {
    const { data: profile } = await db
      .from('profiles')
      .select('role')
      .eq('id', adminUser.id)
      .maybeSingle();
    isAdmin = profile?.role === 'admin';
  }

  if (!isAdmin) return json({ error: 'Forbidden' }, 403);

  const { error: updateError } = await db
    .from('reports')
    .update({ resolved_at: new Date().toISOString(), resolved_by: adminUser.id })
    .eq('id', report_id);

  if (updateError) return json({ error: updateError.message }, 500);

  return json({ ok: true });
});
