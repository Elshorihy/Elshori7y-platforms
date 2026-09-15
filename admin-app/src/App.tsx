import React, { useCallback, useEffect, useState } from "react";
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

  const applyAuthSession = useCallback(async (authSession: any) => {
    const user = authSession?.user;
    if (!user) { setSession(null); return; }
    const email = (user.email ?? "").toLowerCase();
    if (ADMIN_EMAILS.has(email)) { setSession({ userId: user.id, isAdmin: true }); return; }
    const { data: profile } = await supabase.from("profiles").select("role").eq("id", user.id).maybeSingle();
    setSession({ userId: user.id, isAdmin: profile?.role === "admin" });
  }, []);

  useEffect(() => {
    let alive = true;

    const boot = async () => {
      const url = new URL(window.location.href);
      const code = url.searchParams.get("code");

      // Google/Supabase PKCE callback: exchange the code before ANY auth gate
      // runs. This removes the login-page bounce after successful Google login.
      if (code) {
        const { error } = await supabase.auth.exchangeCodeForSession(code);
        if (error) console.error("OAuth code exchange failed:", error);
        url.searchParams.delete("code");
        url.searchParams.delete("state");
        window.history.replaceState({}, document.title, url.pathname + url.search + url.hash);
      }

      const { data } = await supabase.auth.getSession();
      if (alive) await applyAuthSession(data.session);
    };

    void boot();

    const { data: listener } = supabase.auth.onAuthStateChange((_event, authSession) => {
      if (alive) void applyAuthSession(authSession);
    });

    return () => { alive = false; listener.subscription.unsubscribe(); };
  }, [applyAuthSession]);

  const handleLoggedIn = useCallback(async () => {
    const { data } = await supabase.auth.getSession();
    await applyAuthSession(data.session);
  }, [applyAuthSession]);

  if (session === undefined) return <div className="admin-loading">Loading…</div>;
  if (!session || !session.isAdmin) {
    return <BrowserRouter><Login onLoggedIn={handleLoggedIn} deniedNonAdmin={!!session && !session.isAdmin} /></BrowserRouter>;
  }

  return <BrowserRouter><div className="admin-shell"><Sidebar onLogout={() => supabase.auth.signOut()} /><main className="admin-shell__content"><Routes><Route path="/" element={<Dashboard />} /><Route path="/users" element={<Users adminUserId={session.userId} />} /><Route path="/reports" element={<Reports />} /><Route path="*" element={<Navigate to="/" replace />} /></Routes></main></div></BrowserRouter>;
}
