import React, { useEffect, useState } from "react";
import { BrowserRouter, Routes, Route, Navigate } from "react-router-dom";
import { supabase } from "./lib/supabaseClient";
import Login from "./pages/Login";
import Dashboard from "./pages/Dashboard";
import Users from "./pages/Users";
import Reports from "./pages/Reports";
import Sidebar from "./components/Sidebar";
interface AdminSession { userId: string; isAdmin: boolean; }
export default function App() {
 const [session,setSession]=useState<AdminSession|null|undefined>(undefined);
 useEffect(()=>{checkSession(); const {data:sub}=supabase.auth.onAuthStateChange(()=>checkSession()); return()=>sub.subscription.unsubscribe();},[]);
 async function checkSession(){const {data}=await supabase.auth.getSession(); const user=data.session?.user; if(!user){setSession(null);return;} const {data:profile}=await supabase.from("profiles").select("role").eq("id",user.id).single(); setSession({userId:user.id,isAdmin:profile?.role==="admin"});}
 if(session===undefined)return <div className="admin-loading">Loading…</div>;
 if(!session||!session.isAdmin)return <BrowserRouter><Login onLoggedIn={checkSession} deniedNonAdmin={!!session&&!session.isAdmin}/></BrowserRouter>;
 return <BrowserRouter><div className="admin-shell"><Sidebar onLogout={()=>supabase.auth.signOut()}/><main className="admin-shell__content"><Routes><Route path="/" element={<Dashboard/>}/><Route path="/users" element={<Users adminUserId={session.userId}/>}/><Route path="/reports" element={<Reports/>}/><Route path="*" element={<Navigate to="/" replace/>}/></Routes></main></div></BrowserRouter>;
}
