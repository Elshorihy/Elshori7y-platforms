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

function adminSessionFromUser(user: { id: string; email?: string | null }): AdminSession {
  return {
    userId: user.id,
    isAdmin: ADMIN_EMAILS.has((user.email ?? "").toLowerCase()),
  };
}

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

    supabase.auth.getSession().then(({ data }) => {
      if (mounted) applyAuthSession(data.session);
    });

    const { data: listener } = supabase.auth.onAuthStateChange((_event, authSession) => {
      // Use the session supplied by Supabase instead of calling getSession()
      // from inside the auth callback. This prevents the OAuth callback from
      // racing the initial auth check and bouncing the user back to Login.
      if (mounted) applyAuthSession(authSession);
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
