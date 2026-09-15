import { createClient } from "@supabase/supabase-js";

const url = (
  import.meta.env.VITE_SUPABASE_URL ||
  "https://fxmsppakjrqgsebldhrs.supabase.co"
).trim();

// Supabase now recommends the publishable key for browser apps.
// Keep the old variable name as a compatibility fallback for Cloudflare.
const publishableKey = (
  import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY ||
  import.meta.env.VITE_SUPABASE_ANON_KEY ||
  "sb_publishable_59UHlEQni8W4ZawWGyQ_n9_66JCx"
).trim();

if (!url || !publishableKey) {
  throw new Error("Missing Supabase environment variables");
}

export const supabase = createClient(url, publishableKey);

export async function callAdminFunction<T>(
  name: string,
  body: Record<string, unknown>
): Promise<T> {
  const { data: sessionData } = await supabase.auth.getSession();
  const jwt = sessionData.session?.access_token;
  if (!jwt) throw new Error("Not authenticated");

  const res = await fetch(`${url}/functions/v1/${name}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      apikey: publishableKey,
      Authorization: `Bearer ${jwt}`,
    },
    body: JSON.stringify(body),
  });

  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    throw new Error(err.error ?? `${name} failed (${res.status})`);
  }

  return res.json();
}
