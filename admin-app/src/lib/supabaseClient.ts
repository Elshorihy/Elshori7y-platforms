import { createClient } from "@supabase/supabase-js";

// Cloudflare should normally provide these as build-time environment variables.
// The publishable Supabase key is safe to ship in a browser app; the service-role key is never used here.
const url = import.meta.env.VITE_SUPABASE_URL || "https://fxmsppakjrqgsebldhrs.supabase.co";
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY || "sb_publishable_59UHlEQni8W4ZawWGyQ_n9_66JCx";

export const supabase = createClient(url, anonKey);

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
