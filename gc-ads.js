/* GURU CONNECT — Cloud Advertisement Renderer
   Reads active advertisements from Supabase and places them in LRR, Student and Tutor grids.
*/
(function(){
  'use strict';
  const SUPABASE_URL='https://hzqqswrnawrfgufbxgay.supabase.co';
  const SUPABASE_KEY='sb_publishable_Oc5HvqDpisv76XrdsyFhiw_IpostIDu';
  const BUCKET='gc-advertisements';
  const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  function installCss(){
    if(document.getElementById('gc-ads-renderer-css'))return;
    const st=document.createElement('style');st.id='gc-ads-renderer-css';st.textContent=`
.gc-ad-card{position:relative;overflow:hidden;background:#fff;border:1px solid rgba(37,99,235,.22);box-shadow:0 10px 28px rgba(25,55,110,.12);border-radius:18px;box-sizing:border-box}
.gc-ad-card .gc-ad-link{display:block;width:100%;height:100%;color:inherit;text-decoration:none;position:relative}
.gc-ad-card{position:relative;overflow:hidden;background:#fff;border:1px solid #dbe4f0;box-shadow:0 12px 30px rgba(25,55,110,.12);border-radius:18px;box-sizing:border-box;aspect-ratio:16/9;width:100%;align-self:stretch}.gc-ad-card .gc-ad-link{display:flex;flex-direction:column;width:100%;height:100%;color:inherit;text-decoration:none;position:relative}.gc-ad-media{position:relative;width:100%;height:calc(100% - 54px);background:#fff}.gc-ad-media img{width:100%;height:100%;object-fit:contain;display:block;background:#fff}.gc-ad-overlay{position:relative;left:auto;right:auto;bottom:auto;min-height:54px;height:54px;padding:7px 9px 7px 12px;background:#fff;border-top:1px solid #e2e8f0;color:#10204f;display:flex;align-items:center;justify-content:space-between;gap:8px}.gc-ad-overlay span{order:2;display:inline-flex;align-items:center;justify-content:center;min-width:88px;height:34px;border-radius:9px;background:linear-gradient(135deg,#079447,#0bbf68);color:#fff;font-size:11px;font-weight:950;letter-spacing:.03em}.gc-ad-overlay b{order:1;min-width:0;font-size:12px;color:#102a72;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.gc-ad-profile,.gc-ad-lrr{min-height:0;padding:0!important;overflow:hidden}.gc-ad-profile .gc-ad-media,.gc-ad-lrr .gc-ad-media{position:relative;inset:auto}@media(max-width:640px){.gc-ad-card{border-radius:15px}.gc-ad-overlay{min-height:50px;height:50px;padding:6px 8px 6px 10px}.gc-ad-media{height:calc(100% - 50px)}.gc-ad-overlay b{font-size:11px}.gc-ad-overlay span{min-width:82px;height:32px;font-size:10px}}
`;
    document.head.appendChild(st);
  }
  function safeUrl(v){
    const s=String(v||'').trim(); if(!s) return '';
    try{ const u=new URL(s,location.href); return /^https?:$/.test(u.protocol)?u.href:''; }catch(_){ return ''; }
  }
  async function fetchAds(){
    const now=new Date().toISOString();
    const url=SUPABASE_URL+'/rest/v1/gc_advertisements?select=id,title,advertiser_name,image_url,click_url,whatsapp_url,placement,start_at,end_at,priority&active=eq.true&order=priority.desc,created_at.desc';
    const r=await fetch(url,{headers:{apikey:SUPABASE_KEY,Authorization:'Bearer '+SUPABASE_KEY,Accept:'application/json'},cache:'no-store'});
    if(!r.ok) throw new Error(await r.text()||('HTTP '+r.status));
    const rows=await r.json();
    return (Array.isArray(rows)?rows:[]).filter(a=>{
      const s=a.start_at?new Date(a.start_at):null,e=a.end_at?new Date(a.end_at):null,n=new Date(now);
      return (!s||s<=n)&&(!e||e>=n);
    });
  }
  function matches(a,place){return a.placement==='all'||a.placement===place;}
  function card(a,kind){
    const href=safeUrl(a.click_url)||safeUrl(a.whatsapp_url);
    const label=a.advertiser_name||a.title||'Advertisement';
    const tag=kind==='lrr'?'ADVERTISEMENT':kind==='student'?'SPONSORED':'ADVERTISEMENT';
    const body='<div class="gc-ad-media"><img src="'+esc(a.image_url)+'" alt="'+esc(label)+' advertisement" loading="lazy"></div>'+
      '<div class="gc-ad-overlay"><span>📢 '+tag+'</span><b>'+esc(label)+'</b></div>';
    const inner=href?'<a class="gc-ad-link" href="'+esc(href)+'" target="_blank" rel="noopener noreferrer sponsored">'+body+'</a>':body;
    return '<article class="gc-ad-card gc-ad-'+kind+'">'+inner+'</article>';
  }
  function injectGrid(id,ads,kind){
    const grid=document.getElementById(id); if(!grid)return;
    grid.querySelectorAll('.gc-ad-card').forEach(x=>x.remove());
    const list=ads.filter(a=>matches(a,kind)); if(!list.length)return;
    // One active creative is enough for each card slot; multiple creatives rotate by slot.
    const children=[...grid.children];
    const cards=[];
    for(let i=0;i<list.length;i++) cards.push({el:document.createRange().createContextualFragment(card(list[i],kind)).firstElementChild, index:Math.min((i+1)*2,children.length)});
    let offset=0;
    for(const item of cards){
      const target=grid.children[item.index+offset];
      if(target) grid.insertBefore(item.el,target); else grid.appendChild(item.el);
      offset++;
    }
  }
  let rendering=false;
  async function render(){
    if(rendering)return; rendering=true;
    try{
      const ads=await fetchAds();
      injectGrid('tutorGrid',ads,'tutor');
      injectGrid('studentGridContainer',ads,'student');
      injectGrid('grid',ads,'lrr');
      window.__gcActiveAds=ads;
    }catch(e){console.warn('GURU CONNECT advertisements unavailable:',e)}
    finally{rendering=false}
  }
  function boot(){
    if(window.__gcAdsBooted)return; installCss(); window.__gcAdsBooted=true;
    render();
    setInterval(render,60000);
    // Existing directory/LRR renderers replace grid HTML. Re-inject after they finish.
    const ids=['tutorGrid','studentGridContainer','grid'];
    ids.forEach(id=>{const el=document.getElementById(id);if(el){let t;new MutationObserver(()=>{clearTimeout(t);t=setTimeout(()=>render(),120)}).observe(el,{childList:true});}});
  }
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});else boot();
  window.GC_ADS={refresh:render,fetch:fetchAds};
})();
