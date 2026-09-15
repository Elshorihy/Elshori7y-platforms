import React,{useEffect,useMemo,useState}from'react';
import{createRoot}from'react-dom/client';
import{supabase}from'./lib/supabaseClient';
import'./styles.css';

type Profile={id:string;display_name:string|null;username:string;chat_key?:string;verification_status:string;is_banned:boolean};
type Conv={id:string;type:string;created_at:string};
type Msg={id:string;conversation_id:string;sender_id:string;body:string|null;message_type:string;created_at:string;read_at:string|null};
type UserResult=Pick<Profile,'id'|'display_name'|'username'>;

const passwordRules=[
 {ok:(v:string)=>v.length>=12,text:'12 حرف على الأقل'},
 {ok:(v:string)=>/[A-Z]/.test(v),text:'حرف إنجليزي كبير'},
 {ok:(v:string)=>/[a-z]/.test(v),text:'حرف إنجليزي صغير'},
 {ok:(v:string)=>/[0-9]/.test(v),text:'رقم'},
 {ok:(v:string)=>/[^A-Za-z0-9\s]/.test(v),text:'رمز خاص'},
 {ok:(v:string)=>! /\s/.test(v),text:'بدون مسافات'}
];
function strongPassword(v:string){return passwordRules.every(r=>r.ok(v))}

function Auth({refresh}:{refresh:()=>void}){
 const[signup,setSignup]=useState(false),[email,setEmail]=useState(''),[password,setPassword]=useState(''),[name,setName]=useState(''),[username,setUsername]=useState(''),[error,setError]=useState(''),[busy,setBusy]=useState(false);
 async function submit(e:React.FormEvent){
  e.preventDefault();setError('');
  if(signup&&!strongPassword(password)){setError('كلمة السر ضعيفة. لازم تكون 12 حرف على الأقل وتحتوي على حرف كبير وحرف صغير ورقم ورمز خاص وبدون مسافات.');return}
  if(!signup&&password.length<1){setError('اكتب كلمة السر');return}
  setBusy(true);
  try{
   if(signup){
    const u=username.trim().toLowerCase();
    if(!/^[a-z0-9_]{3,24}$/.test(u)){setError('اسم المستخدم لازم يكون 3-24 حرف إنجليزي أو أرقام أو _');return}
    const r=await supabase.auth.signUp({email:email.trim(),password,options:{data:{display_name:name.trim(),username:u}}});
    if(r.error)setError(r.error.message);
    else if(r.data.session)refresh();
    else setError('تم إنشاء الحساب. أكد الإيميل ثم سجل الدخول.');
   }else{
    const r=await supabase.auth.signInWithPassword({email:email.trim(),password});
    if(r.error)setError(r.error.message);else refresh();
   }
  }catch(err:any){setError(err?.message||'حصل خطأ غير متوقع');}
  finally{setBusy(false)}
 }
 return <div className="auth"><form className="card auth-card" onSubmit={submit}>
  <div className="brand"><div className="brand-mark">E</div><div><h1>ELshori7y</h1><small>منصة محادثات آمنة</small></div></div>
  {signup&&<>
   <label>الاسم الظاهر</label><input required placeholder="مثال: حمزة" value={name} onChange={e=>setName(e.target.value)}/>
   <label>اسم المستخدم</label><input required minLength={3} maxLength={24} pattern="[A-Za-z0-9_]+" placeholder="مثال: hamza_7" value={username} onChange={e=>setUsername(e.target.value)}/>
   <small className="hint">اسم المستخدم عام ويمكن مشاركته، ومفتاح الدردشة هو الجزء السري.</small>
  </>}
  <label>الإيميل</label><input required type="email" placeholder="example@email.com" value={email} onChange={e=>setEmail(e.target.value)}/>
  <label>كلمة السر</label><input required minLength={signup?12:1} type="password" placeholder="••••••••••••" value={password} onChange={e=>setPassword(e.target.value)}/>
  {signup&&<div className="password-rules">{passwordRules.map(r=><span className={r.ok(password)?'ok':''} key={r.text}>{r.ok(password)?'✓':'•'} {r.text}</span>)}</div>}
  <button disabled={busy}>{busy?'جاري التنفيذ...':signup?'إنشاء حساب':'دخول'}</button>
  {error&&<p className="error">{error}</p>}
  <button type="button" className="ghost" onClick={()=>{setSignup(!signup);setError('')}}>{signup?'عندي حساب بالفعل':'إنشاء حساب جديد'}</button>
 </form></div>
}

function App(){
 const[session,setSession]=useState<any>(null),[profile,setProfile]=useState<Profile|null>(null),[users,setUsers]=useState<UserResult[]>([]),[convs,setConvs]=useState<Conv[]>([]),[active,setActive]=useState<string|null>(null),[messages,setMessages]=useState<Msg[]>([]),[query,setQuery]=useState(''),[key,setKey]=useState(''),[text,setText]=useState(''),[loading,setLoading]=useState(true),[busy,setBusy]=useState(false),[notice,setNotice]=useState(''),[showKey,setShowKey]=useState(false),[newMessage,setNewMessage]=useState(false);
 const uid=session?.user?.id;

 async function load(){
  const{data,error}=await supabase.auth.getSession();
  if(error){setSession(null);setProfile(null);setLoading(false);return}
  setSession(data.session);
  if(data.session){
   const{data:p,error:pe}=await supabase.from('profiles').select('id,display_name,username,chat_key,verification_status,is_banned').eq('id',data.session.user.id).single();
   if(pe)setProfile(null);else setProfile(p);
   await loadConvs(data.session.user.id);
  }else{setProfile(null);setConvs([]);setActive(null);setMessages([])}
  setLoading(false);
 }

 async function loadConvs(id:string){
  const{data,error}=await supabase.from('conversation_participants').select('conversation_id').eq('user_id',id);
  if(error){setNotice(error.message);setConvs([]);return}
  const ids=(data??[]).map(x=>x.conversation_id);
  if(!ids.length){setConvs([]);return}
  const{data:c,error:ce}=await supabase.from('conversations').select('id,type,created_at').in('id',ids).order('created_at',{ascending:false});
  if(ce){setNotice(ce.message);setConvs([]);return}
  setConvs(c??[]);
 }

 async function loadMessages(id:string,markRead=true){
  const{data,error}=await supabase.from('messages').select('*').eq('conversation_id',id).order('created_at',{ascending:true});
  if(error){setNotice(error.message);return false}
  setMessages(data??[]);
  if(markRead){
   const{error:readError}=await supabase.rpc('mark_messages_read',{conversation_uuid:id});
   if(readError)setNotice(readError.message);
  }
  return true;
 }

 async function openConv(id:string){
  setActive(id);setNewMessage(false);await loadMessages(id,true);
 }

 async function newChat(){
  const u=query.trim().toLowerCase(),k=key.trim().toUpperCase();
  if(!u||!k){setNotice('اكتب اسم المستخدم ومفتاح المستخدم');return}
  setBusy(true);setNotice('');
  const{data,error}=await supabase.rpc('create_direct_conversation_by_credentials',{target_username:u,target_chat_key:k});
  setBusy(false);
  if(error){setNotice(error.message);return}
  await loadConvs(uid);if(data)await openConv(data);setQuery('');setKey('');
 }

 async function send(){
  const body=text.trim();if(!body||!active||!uid)return;
  setBusy(true);setNotice('');
  const{data,error}=await supabase.rpc('send_message',{p_conversation_id:active,p_body:body,p_message_type:'text'});
  setBusy(false);
  if(error){setNotice(error.message);return}
  const row=(Array.isArray(data)?data[0]:data) as Msg|undefined;
  setText('');
  if(row)setMessages(m=>m.some(x=>x.id===row.id)?m:[...m,row]);
 }

 async function copyKey(){
  if(!profile?.chat_key)return;
  try{await navigator.clipboard.writeText(profile.chat_key);setNotice('تم نسخ مفتاح الدردشة')}catch{setNotice('انسخ المفتاح يدويًا: '+profile.chat_key)}
 }

 async function logout(){await supabase.auth.signOut();setSession(null);setProfile(null);setConvs([]);setMessages([]);setActive(null)}

 useEffect(()=>{load();const{data}=supabase.auth.onAuthStateChange((event,next)=>{if(event==='SIGNED_OUT'){setSession(null);setProfile(null)}else if(event==='SIGNED_IN'||event==='USER_UPDATED'){setSession(next);setTimeout(load,0)}});return()=>data.subscription.unsubscribe()},[]);

 useEffect(()=>{
  if(!uid)return;
  const channel=supabase.channel('inbox-'+uid)
   .on('postgres_changes',{event:'INSERT',schema:'public',table:'conversation_participants',filter:'user_id=eq.'+uid},()=>loadConvs(uid))
   .on('postgres_changes',{event:'INSERT',schema:'public',table:'messages'},payload=>{
    const msg=payload.new as Msg;
    if(msg.sender_id!==uid){setNewMessage(true);if(active===msg.conversation_id)setMessages(m=>m.some(x=>x.id===msg.id)?m:[...m,msg]);else loadConvs(uid)}
   })
   .subscribe();
  return()=>{supabase.removeChannel(channel)}
 },[uid,active]);

 useEffect(()=>{
  if(!uid)return;
  const timer=window.setInterval(()=>{loadConvs(uid);if(active)loadMessages(active,false)},5000);
  return()=>window.clearInterval(timer);
 },[uid,active]);

 useEffect(()=>{if(!uid)return;(async()=>{const{data,error}=await supabase.from('profiles').select('id,display_name,username').eq('verification_status','verified').eq('is_banned',false).neq('id',uid).order('username').limit(100);if(error){setNotice(error.message);return}setUsers(data??[])})()},[uid]);

 const filtered=useMemo(()=>{const q=query.trim().toLowerCase();if(!q)return[];return users.filter(u=>u.username.toLowerCase().includes(q)).slice(0,8)},[users,query]);
 const activeTitle=active?'محادثة آمنة':'اختر محادثة';

 if(loading)return <div className="center"><div className="loader-card">جاري تحميل ELshori7y...</div></div>;
 if(!session)return <Auth refresh={load}/>;
 if(!profile)return <div className="center"><div className="card"><h2>تعذر تحميل الحساب</h2><p>تأكد إن Migration قاعدة البيانات اتنفذت بالكامل.</p><button onClick={load}>إعادة المحاولة</button></div></div>;
 if(profile.is_banned)return <div className="center"><div className="card"><h2>الحساب محظور</h2><button onClick={logout}>خروج</button></div></div>;
 if(profile.verification_status!=='verified')return <div className="center"><div className="card review"><div className="status-icon">✓</div><h2>الحساب قيد المراجعة</h2><p>بعد التحقق من الحساب هتقدر تستخدم المحادثات وكل مميزات الحساب الموثق.</p><button onClick={logout}>خروج</button></div></div>;

 return <div className="app-shell">
  <header><div className="header-brand"><div className="brand-mark small">E</div><b>ELshori7y</b></div><div className="header-user"><span className="verified-header">✓ موثّق</span>@{profile.username}<button className="logout" onClick={logout}>خروج</button></div></header>
  <div className="layout">
   <aside>
    <div className="identity">
     <div className="identity-top"><div><b>{profile.display_name||profile.username}</b><small>@{profile.username}</small></div><span className="verified">✓ موثّق</span></div>
     <div className="verified-features"><b>مميزات الحساب الموثق</b><span>✓ هوية موثوقة</span><span>✓ دخول للمحادثات الآمنة</span><span>✓ يظهر حسابك كموثّق للآخرين</span></div>
     <div className="key-box"><small>مفتاح الدردشة الخاص بك</small><div><strong>{showKey?profile.chat_key:'••••••••••'}</strong><button type="button" className="icon-btn" onClick={()=>setShowKey(!showKey)}>{showKey?'إخفاء':'إظهار'}</button></div><button type="button" className="copy-btn" onClick={copyKey}>نسخ المفتاح</button><small className="hint">شارك الـUsername عادي، لكن لا تشارك المفتاح إلا مع الشخص المسموح له ببدء محادثة معك.</small></div>
    </div>
    <div className="new-chat">
     <h3>بدء دردشة جديدة</h3>
     <input placeholder="اسم المستخدم @username" value={query} onChange={e=>setQuery(e.target.value.replace(/^@/,''))}/>
     <input placeholder="مفتاح المستخدم" value={key} onChange={e=>setKey(e.target.value.toUpperCase())}/>
     {filtered.length>0&&<div className="userResults">{filtered.map(u=><button className="user" key={u.id} onClick={()=>setQuery(u.username)}><span><b>@{u.username}</b><small>{u.display_name||'مستخدم'}</small></span><span>اختيار</span></button>)}</div>}
     <button disabled={busy} onClick={newChat}>{busy?'جاري التحقق...':'بدء دردشة آمنة'}</button>
     <p className="hint">لا يتم فتح المحادثة إلا إذا تطابق اسم المستخدم مع مفتاحه وكان الحساب موثّقًا وغير محظور.</p>
    </div>
    <div className="conversation-list"><div className="section-title">محادثاتك <span>{convs.length}</span></div>{convs.map(c=><button className={'conv '+(active===c.id?'active':'')} key={c.id} onClick={()=>openConv(c.id)}><span className="conv-avatar">{c.type==='direct'?'↔':'#'}</span><span><b>محادثة مباشرة</b><small>{new Date(c.created_at).toLocaleDateString('ar-EG')}</small></span></button>)}{!convs.length&&<p className="empty">لسه مفيش محادثات. ابدأ واحدة من فوق.</p>}</div>
   </aside>
   <section className="chat">
    <div className="chat-head"><div><b>{activeTitle}</b>{active&&<small>الاتصال مؤمّن باسم المستخدم + المفتاح</small>}</div>{newMessage&&<button className="new-msg" onClick={()=>{setNewMessage(false);if(active)loadMessages(active,true)}}>رسالة جديدة</button>}</div>
    {notice&&<div className="notice">{notice}<button onClick={()=>setNotice('')}>×</button></div>}
    <div className="msgs">{active?messages.map(m=><div className={'msg '+(m.sender_id===uid?'mine':'')} key={m.id}><div>{m.body??''}</div><small>{new Date(m.created_at).toLocaleTimeString('ar-EG',{hour:'2-digit',minute:'2-digit'})}</small></div>):<div className="empty-chat"><div className="empty-icon">🔒</div><h2>محادثات ELshori7y</h2><p>ابحث عن المستخدم، أدخل مفتاحه، وابدأ دردشة آمنة.</p></div>}</div>
    {active&&<form className="composer" onSubmit={e=>{e.preventDefault();send()}}><input autoFocus value={text} onChange={e=>setText(e.target.value)} placeholder="اكتب رسالة..."/><button disabled={!text.trim()||busy}>{busy?'...':'إرسال'}</button></form>}
   </section>
  </div>
 </div>
}

createRoot(document.getElementById('root')!).render(<React.StrictMode><App/></React.StrictMode>);
