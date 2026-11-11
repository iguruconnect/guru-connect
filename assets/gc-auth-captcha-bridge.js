(function(){
'use strict';
if(window.__GC_AUTH_CAPTCHA_BRIDGE__)return;
window.__GC_AUTH_CAPTCHA_BRIDGE__=true;
const SITEKEY='0x4AAAAAAFy99xtMvTDkv10E';
let apiReady=null,widgetId=null,activeResolve=null,overlay=null,container=null,status=null,token='';
function ensureUI(){
 if(overlay)return;
 overlay=document.createElement('div');
 overlay.id='gc-auth-captcha-overlay';
 overlay.style.cssText='position:fixed;inset:0;z-index:2147483647;background:rgba(10,20,45,.68);display:none;align-items:center;justify-content:center;padding:18px;font-family:Roboto,Arial,sans-serif';
 const card=document.createElement('div');
 card.style.cssText='width:min(420px,100%);background:#fff;border-radius:18px;padding:22px;box-shadow:0 20px 70px #0005;text-align:center;color:#172554';
 card.innerHTML='<div style="font-weight:900;font-size:19px">GURU CONNECT</div><p style="font-weight:700;margin:8px 0">Security verification required</p><p style="font-size:13px;color:#64748b;margin:0 0 12px">Please complete the Cloudflare check to securely sign in.</p><div id="gc-auth-captcha-widget" style="display:flex;justify-content:center;min-height:66px"></div><div id="gc-auth-captcha-status" role="status" style="font-size:12px;color:#64748b;margin-top:8px">Loading security check…</div><button id="gc-auth-captcha-cancel" type="button" style="margin-top:14px;padding:10px 18px;border:0;border-radius:10px;background:#e2e8f0;color:#1e293b;font-weight:800;cursor:pointer">CANCEL</button>';
 overlay.appendChild(card);document.body.appendChild(overlay);
 container=card.querySelector('#gc-auth-captcha-widget');status=card.querySelector('#gc-auth-captcha-status');
 card.querySelector('#gc-auth-captcha-cancel').onclick=function(){finish(null,new Error('Security verification cancelled.'))};
}
function finish(value,error){
 if(!activeResolve)return;
 const resolve=activeResolve;activeResolve=null;
 if(overlay)overlay.style.display='none';
 resolve({value,error});
}
function loadTurnstile(){
 if(window.turnstile)return Promise.resolve(window.turnstile);
 if(apiReady)return apiReady;
 apiReady=new Promise((resolve,reject)=>{
  const prior=window.gcAuthTurnstileOnload;
  window.gcAuthTurnstileOnload=function(){try{if(typeof prior==='function')prior();resolve(window.turnstile)}catch(e){resolve(window.turnstile)}};
  const script=document.createElement('script');
  script.src='https://challenges.cloudflare.com/turnstile/v0/api.js?onload=gcAuthTurnstileOnload&render=explicit';
  script.async=true;script.defer=true;script.onerror=()=>reject(new Error('Cloudflare security check could not load. Please allow challenges.cloudflare.com and refresh.'));
  document.head.appendChild(script);
  setTimeout(()=>{if(!window.turnstile)reject(new Error('Cloudflare security check timed out. Please refresh and try again.'))},15000);
 });
 return apiReady;
}
async function requestToken(){
 ensureUI();overlay.style.display='flex';status.textContent='Loading security check…';
 try{
  const ts=await loadTurnstile();
  if(widgetId!==null){try{ts.remove(widgetId)}catch(_){}widgetId=null}
  container.innerHTML='';
  widgetId=ts.render(container,{sitekey:SITEKEY,theme:'light',size:'normal',callback:t=>finish(t,null),'expired-callback':()=>{status.textContent='Verification expired. Please complete it again.'},'error-callback':()=>{status.textContent='Verification could not load. Please refresh and try again.'}});
  status.textContent='Complete the Cloudflare check to continue.';
 }catch(e){finish(null,e)}
 return new Promise(resolve=>{activeResolve=resolve});
}
function patch(api){
 if(!api||typeof api.createClient!=='function'||api.__gcCaptchaPatched)return;
 const create=api.createClient.bind(api);
 api.createClient=function(){
  const client=create.apply(null,arguments);
  if(client&&client.auth&&!client.auth.__gcCaptchaPatched){
   const signIn=client.auth.signInWithPassword.bind(client.auth);
   client.auth.signInWithPassword=async function(credentials){
    const args=arguments;
    if(credentials&&credentials.options&&credentials.options.captchaToken)return signIn.apply(client.auth,args);
    const result=await requestToken();
    if(result.error)throw result.error;
    try{return await signIn({...credentials,options:{...(credentials&&credentials.options||{}),captchaToken:result.value}})}
    finally{token='';if(widgetId!==null&&window.turnstile){try{window.turnstile.reset(widgetId)}catch(_){}}}
   };
   client.auth.__gcCaptchaPatched=true;
  }
  return client;
 };
 api.__gcCaptchaPatched=true;
}
let current;
try{
 current=window.supabase;
 Object.defineProperty(window,'supabase',{configurable:true,enumerable:true,get:function(){return current},set:function(v){current=v;patch(v)}});
 if(current)patch(current);
}catch(e){if(window.supabase)patch(window.supabase)}
})();