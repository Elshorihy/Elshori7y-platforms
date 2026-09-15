import React,{useCallback,useEffect,useState}from"react";
import{supabase}from"../lib/supabaseClient";
import StatCard from"../components/StatCard";

interface Stats{pendingVerifications:number;openReports:number;messagesLast7Days:number;verifiedUsers:number;}

export default function Dashboard(){
 const[stats,setStats]=useState<Stats|null>(null);const[error,setError]=useState<string|null>(null);const[refreshing,setRefreshing]=useState(false);
 const load=useCallback(async()=>{
  setRefreshing(true);setError(null);
  try{
   const{data,error:rpcError}=await supabase.rpc("admin_dashboard_stats");
   if(rpcError)throw new Error(rpcError.message);
   if(!data)throw new Error("لم ترجع قاعدة البيانات بيانات لوحة التحكم");
   setStats({pendingVerifications:Number(data.pending_verifications??0),openReports:Number(data.open_reports??0),messagesLast7Days:Number(data.messages_last_7_days??0),verifiedUsers:Number(data.verified_users??0)});
  }catch(e:any){setError(e?.message||"تعذر تحميل بيانات لوحة التحكم");}
  finally{setRefreshing(false)}
 },[]);
 useEffect(()=>{void load();const id=window.setInterval(()=>{if(document.visibilityState==="visible")void load()},15000);return()=>window.clearInterval(id)},[load]);
 return <div className="admin-dashboard">
  <div className="page-heading"><div><span className="eyebrow">ELSHORI7Y CONTROL CENTER</span><h1>لوحة التحكم</h1><p>نظرة سريعة على حالة المنصة والمستخدمين والمحادثات.</p></div><button className="primary-btn" onClick={()=>void load()} disabled={refreshing}>{refreshing?"جاري التحديث…":"تحديث البيانات"}</button></div>
  {error&&<div className="admin-error admin-error--box"><b>تعذر تحميل بعض بيانات اللوحة</b><span>{error}</span><button onClick={()=>void load()}>إعادة المحاولة</button></div>}
  <div className="admin-dashboard__stats">
   <StatCard label="طلبات التوثيق" value={stats?.pendingVerifications??"—"}/>
   <StatCard label="بلاغات مفتوحة" value={stats?.openReports??"—"}/>
   <StatCard label="رسائل آخر 7 أيام" value={stats?.messagesLast7Days??"—"}/>
   <StatCard label="حسابات موثقة" value={stats?.verifiedUsers??"—"}/>
  </div>
  <div className="dashboard-panel"><div><span className="panel-kicker">SYSTEM STATUS</span><h2>المنصة شغالة من مكان واحد</h2><p>إدارة المستخدمين، التوثيق والبلاغات أصبحت مباشرة من لوحة الإدارة بدون الاعتماد على استعلامات RLS الثقيلة.</p></div><div className="status-pill"><i/> ONLINE</div></div>
 </div>
}
