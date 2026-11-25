(()=>{function apply(){const p=location.pathname.toLowerCase();let root=null,old=null;
if(p.startsWith('/about')){root=document.querySelector('main');old=document.querySelector('body>.top')}
else if(p.startsWith('/join-us')){root=document.querySelector('main.wrap')}
else if(p.startsWith('/guidelines')){root=document.querySelector('main.wrap');old=document.querySelector('body>header')}
else if(p.startsWith('/write-to-us')){root=document.querySelector('main.page');old=root&&root.querySelector(':scope>.brand')}
else if(p.startsWith('/contactus')){root=document.querySelector('main.wrap');old=document.querySelector('body>header')}
if(!root)return;document.body.classList.add('gc-content-document');root.classList.add('gc-content-sheet');if(old)old.style.display='none';
if(!root.querySelector('.gc-doc-brand')){const h=document.createElement('header');h.className='gc-doc-brand';h.innerHTML='<img src="/Best%20NB%20New%20age.png" alt="GURU CONNECT logo"><div class="gc-doc-brand-copy"><div class="gc-doc-brand-name">GURU CONNECT</div><div class="gc-doc-brand-tag">Connecting Mind - Creating Future · Learn • Connect • Grow</div></div><a class="gc-doc-home" href="/">HOME</a>';root.insertBefore(h,root.firstChild);}
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',apply,{once:true});else apply();})();