import { createClient } from "@supabase/supabase-js";

const url = "https://fxmsppakjrqgsebldhrs.supabase.co";
const publishableKey = "sb_publishable_59UHlLEq_Ni8W4ZawWGWyQ_n9_66JCx";

export const supabase = createClient(url, publishableKey);

export async function callAdminFunction<T>(
  name: string,
  body: Record<string, unknown>
): Promise<T> {
  const { data, error } = await supabase.functions.invoke<T>(name, { body });

  if (error) {
    throw new Error(error.message || `${name} failed`);
  }

  if (!data) {
    throw new Error(`${name} returned no data`);
  }

  return data;
}
