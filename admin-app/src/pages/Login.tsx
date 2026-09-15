import React, { useEffect, useState } from "react";
import { supabase } from "../lib/supabaseClient";

interface Props { onLoggedIn: () => void; deniedNonAdmin?: boolean; }
const ADMIN_REDIRECT = "https://elshori7y-admin.sheenomatp.workers.dev";

export default function Login({ onLoggedIn, deniedNonAdmin }: Props) {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [googleLoading, setGoogleLoading] = useState(false);

  useEffect(() => {
    let cancelled = false;

    const finishOAuth = async () => {
      const search = new URLSearchParams(window.location.search);
      const code = search.get("code");
      const hash = window.location.hash;

      if (code) {
        const { error: exchangeError } = await supabase.auth.exchangeCodeForSession(code);
        if (exchangeError && !cancelled) setError(exchangeError.message);
      }

      if (hash.includes("access_token")) {
        await new Promise((resolve) => setTimeout(resolve, 300));
      }

      const { data } = await supabase.auth.getSession();
      if (!cancelled && data.session) {
        window.history.replaceState({}, document.title, window.location.pathname);
        onLoggedIn();
      }
    };

    finishOAuth();
    return () => { cancelled = true; };
  }, [onLoggedIn]);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setSubmitting(true);
    setError(null);
    const { error: signInErr } = await supabase.auth.signInWithPassword({ email, password });
    setSubmitting(false);
    if (signInErr) { setError(signInErr.message); return; }
    onLoggedIn();
  };

  const handleGoogle = async () => {
    setGoogleLoading(true);
    setError(null);
    const { error: oauthErr } = await supabase.auth.signInWithOAuth({
      provider: "google",
      options: {
        redirectTo: ADMIN_REDIRECT,
        queryParams: { access_type: "offline", prompt: "select_account" },
      },
    });
    if (oauthErr) {
      setGoogleLoading(false);
      setError(oauthErr.message);
    }
  };

  return (
    <div className="admin-login">
      <div className="admin-login__card">
        <h1>ELshori7y Admin</h1>
        {deniedNonAdmin && <p className="admin-login__denied">That account doesn't have admin access.</p>}
        <button type="button" onClick={handleGoogle} disabled={googleLoading}>
          {googleLoading ? "Connecting…" : "Continue with Google"}
        </button>
        <div style={{ textAlign: "center", margin: "14px 0", opacity: 0.6 }}>or</div>
        <form onSubmit={handleSubmit}>
          <label>Email<input type="email" value={email} onChange={e => setEmail(e.target.value)} required /></label>
          <label>Password<input type="password" value={password} onChange={e => setPassword(e.target.value)} required /></label>
          {error && <p className="admin-login__error">{error}</p>}
          <button type="submit" disabled={submitting}>{submitting ? "Signing in…" : "Sign in"}</button>
        </form>
      </div>
    </div>
  );
}
