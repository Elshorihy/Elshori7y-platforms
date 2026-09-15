import React, { useState } from "react";
import { supabase } from "../lib/supabaseClient";

interface Props { onLoggedIn: () => void; deniedNonAdmin?: boolean; }
const ADMIN_REDIRECT = "https://elshori7y-admin.sheenomatp.workers.dev";

export default function Login({ onLoggedIn, deniedNonAdmin }: Props) {
  const [email, setEmail] = useState("sheenomatp@gmail.com");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [magicLoading, setMagicLoading] = useState(false);
  const [magicSent, setMagicSent] = useState(false);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setSubmitting(true);
    setError(null);
    setMagicSent(false);

    const { error: signInErr } = await supabase.auth.signInWithPassword({ email, password });
    setSubmitting(false);

    if (signInErr) {
      setError(signInErr.message);
      return;
    }

    onLoggedIn();
  };

  const handleMagicLink = async () => {
    if (!email.trim()) {
      setError("اكتب الإيميل الأول");
      return;
    }

    setMagicLoading(true);
    setError(null);
    setMagicSent(false);

    const { error: otpError } = await supabase.auth.signInWithOtp({
      email: email.trim(),
      options: {
        emailRedirectTo: ADMIN_REDIRECT,
        shouldCreateUser: false,
      },
    });

    setMagicLoading(false);

    if (otpError) {
      setError(otpError.message);
      return;
    }

    setMagicSent(true);
  };

  return (
    <div className="admin-login">
      <div className="admin-login__card">
        <h1>ELshori7y Admin</h1>
        {deniedNonAdmin && <p className="admin-login__denied">الحساب ده مش عنده صلاحية Admin.</p>}

        <form onSubmit={handleSubmit}>
          <label>
            Email
            <input
              type="email"
              value={email}
              onChange={e => setEmail(e.target.value)}
              required
              autoComplete="email"
            />
          </label>

          <label>
            Password
            <input
              type="password"
              value={password}
              onChange={e => setPassword(e.target.value)}
              required
              autoComplete="current-password"
            />
          </label>

          {error && <p className="admin-login__error">{error}</p>}
          {magicSent && <p className="admin-login__success">اتبعنا لينك الدخول اللي اتبعت على الإيميل.</p>}

          <button type="submit" disabled={submitting || magicLoading}>
            {submitting ? "Signing in…" : "Sign in"}
          </button>
        </form>

        <div style={{ textAlign: "center", margin: "16px 0", opacity: 0.6 }}>أو</div>

        <button type="button" onClick={handleMagicLink} disabled={submitting || magicLoading}>
          {magicLoading ? "Sending…" : "الدخول برابط على الإيميل"}
        </button>
      </div>
    </div>
  );
}
