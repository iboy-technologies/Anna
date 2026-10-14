(function(){
  'use strict';
  // simple cookie helpers
  function setCookie(name,val,days){
    var maxage = days*24*60*60;
    document.cookie = name+'='+val+';path=/;max-age='+maxage+';SameSite=Lax';
  }
  function getCookie(name){
    var pairs = document.cookie.split('; ');
    for(var i=0;i<pairs.length;i++){
      var p = pairs[i].split('='); if(p[0]===name) return p[1];
    }
    return null;
  }

  // inject Google AdSense script (with your publisher id)
  function injectAdsenseScript(){
    if(window.adsbygoogle) return; // already added
    var s = document.createElement('script');
    s.src = 'https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client=ca-pub-5520788108565807';
    s.async = true; s.crossOrigin = 'anonymous';
    document.head.appendChild(s);
  }

  // render all ad slots by pushing to adsbygoogle
  function renderAdSlots(){
    var slots = document.querySelectorAll('.ad-slot');
    slots.forEach(function(slot){
      // guard: only push once per slot
      if(slot.dataset.rendered==='1') return;
      try{ (adsbygoogle = window.adsbygoogle || []).push({}); slot.dataset.rendered='1'; }catch(e){ /* ignore until script loads */ }
    });
  }

  // lazy-load slots when they are near viewport
  var io = new IntersectionObserver(function(entries, obs){
    entries.forEach(function(e){
      if(e.isIntersecting){
        if(getCookie('ads_consent')==='1'){
          // ensure script is present
          injectAdsenseScript();
          renderAdSlots();
        }
        obs.unobserve(e.target);
      }
    });
  },{rootMargin:'300px'});

  document.addEventListener('DOMContentLoaded', function(){
    var slots = document.querySelectorAll('.ad-slot');
    slots.forEach(function(s){ io.observe(s); });

    // if already consented, inject script immediately and render any slots that are in view
    var consent = getCookie('ads_consent');
    if(consent==='1'){
      injectAdsenseScript();
      // small timeout to wait for script to load
      setTimeout(renderAdSlots, 600);
      return;
    }
    if(consent==='0'){
      return; // do not show banner or load ads
    }

    // show consent banner
    var banner = document.createElement('div');
    banner.id = 'ads-consent-banner';
    banner.setAttribute('role','region');
    banner.setAttribute('aria-label','Ads consent');
    banner.innerHTML = '<div class="consent-text">We use advertising to support this site. By accepting, you agree to allow ads to be shown on this site. You can change your choice at any time.</div>'+
                       '<div class="consent-actions"> <button id="ads-accept" class="btn">Accept</button> <button id="ads-decline" class="btn secondary">Decline</button></div>';
    document.body.appendChild(banner);

    document.getElementById('ads-accept').addEventListener('click', function(){
      setCookie('ads_consent','1',365);
      injectAdsenseScript();
      renderAdSlots();
      banner.remove();
    });
    document.getElementById('ads-decline').addEventListener('click', function(){
      setCookie('ads_consent','0',365);
      banner.remove();
    });
  });
})();
