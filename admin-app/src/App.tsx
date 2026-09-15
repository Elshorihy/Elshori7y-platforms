import React, { useEffect, useState } from "react";
import { BrowserRouter, Routes, Route, Navigate } from "react-router-dom";
import { supabase } from "./lib/supabaseClient";
import Login from "./pages/Login";
import Dashboard from "./pages/Dashboard";
import Users from "./pages/Users";
import Reports from "./pages/Reports";
import Sidebar from "./components/Sidebar";

interface AdminSession { userId: string; isAdmin: boolean; }

const ADMIN_EMAILS = new Set(["sheenomatp@gmail.com"]);

export default function App() {
  const [session, setSession] = useState<AdminSession | null | undefined>(undefined);

  async function applyAuthSession(authSession: any) {
    const user = authSession?.user;
    if (!user) {
      setSession(null);
      return;
    }

    const email = (user.email ?? "").toLowerCase();
    if (ADMIN_EMAILS.has(email)) {
      setSession({ userId: user.id, isAdmin: true });
      return;
    }

    const { data: profile } = await supabase
      .from("profiles")
      .select("role")
      .eq("id", user.id)
      .maybeSingle();

    setSession({ userId: user.id, isAdmin: profile?.role === "admin" });
  }

  useEffect(() => {
    let mounted = true;

    const boot = async () => {
      // IMPORTANT: complete the Supabase PKCE OAuth exchange before the
      // initial auth gate can decide that the user is logged out.
      const code = new URLSearchParams(window.location.search).get("code");
      if (code) {
        const { error } = await supabase.auth.exchangeCodeForSession(code);
        if (error) {
          console.error("OAuth code exchange failed:", error);
        }
        window.history.replaceState({}, document.title, window.location.pathname);
      }

      const { data } = await supabase.auth.getSession();
      if (mounted) await applyAuthSession(data.session);
    };

    boot();

    const { data: listener } = supabase.auth.onAuthStateChange((_event, authSession) => {
      if (mounted) {
        void applyAuthSession(authSession);
      }
    });

    return () => {
      mounted = false;
      listener.subscription.unsubscribe();
    };
  }, []);

  if (session === undefined) return <div className="admin-loading">Loading…</div>;

  if (!session || !session.isAdmin) {
    return (
      <BrowserRouter>
        <Login
          onLoggedIn={() => supabase.auth.getSession().then(({ data }) => applyAuthSession(data.session))}
          deniedNonAdmin={!!session && !session.isAdmin}
        />
      </BrowserRouter>
    );
  }

  return (
    <BrowserRouter>
      <div className="admin-shell">
        <Sidebar onLogout={() => supabase.auth.signOut()} />
        <main className="admin-shell__content">
          <Routes>
            <Route path="/" element={<Dashboard />} />
            <Route path="/users" element={<Users adminUserId={session.userId} />} />
            <Route path="/reports" element={<Reports />} />
            <Route path="*" element={<Navigate to="/" replace />} />
          </Routes>
        </main>
      </div>
    </BrowserRouter>
  );
}
