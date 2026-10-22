;(function(){try{
/* English patch: the phone-mirroring and PC-mode helper apps (vivoScreen.exe, PCMode.exe) only load English when
   config.json has isExport=true at the moment they start. The connection service reads the same flag, so it is
   switched on just while a helper launches (by this app, or by the other helper when switching between phone
   mirroring and desktop mode) and switched back off afterwards.
   It also adds a line under vivo's "update available" window saying whether an English translation exists
   for the new version (from latest.json in the patch's GitHub repository), adds a "Check for updates" button to
   the main window, and asks the background helper to check for a newer translation each time the app starts. */
var cp=require("child_process"),fs=require("fs"),path=require("path"),os=require("os"),https=require("https"),el=require("electron");
var upd=function(fn){try{var p=path.join(el.app.getPath("userData"),"config.json"),d=JSON.parse(fs.readFileSync(p,"utf8")),before=JSON.stringify(d);fn(d);if(JSON.stringify(d)!==before){var tmp=p+".tmp-en";fs.writeFileSync(tmp,JSON.stringify(d,null,"\t"));fs.renameSync(tmp,p)}}catch(e){}};
var off=function(){upd(function(d){if(d.isExport===true)d.isExport=false})};
var timer=null,spawn=cp.spawn;
var english=function(){upd(function(d){if(d.isExport===true&&!timer)d.isExport=false;d.currentLanguage="en_US";d.isRtl=false})};
english();[2000,8000,20000,60000].forEach(function(ms){setTimeout(english,ms)});
var helperStarting=function(){upd(function(d){d.isExport=true;d.currentLanguage="en_US";d.isRtl=false});clearTimeout(timer);timer=setTimeout(function(){timer=null;off()},12000)};
cp.spawn=function(cmd){try{if(typeof cmd==="string"&&/[\\\/](vivoScreen|vScreen|PCMode)(\.exe)?$/i.test(cmd))helperStarting()}catch(e){}return spawn.apply(this,arguments)};
/* Switching between phone mirroring and desktop mode from inside those windows starts the other helper directly,
   not through this app. The app is told with a "switch_app_action" message, which it logs before acting on it,
   a moment before the new helper reads its language: switch English on at that point too. */
var hookLog=function(){try{var L=global.__log;if(!L||typeof L.info!=="function"||L.info.__vok)return;var info=L.info;
  L.info=function(m){try{if(typeof m==="string"&&m.indexOf("switch_app_action")>=0)helperStarting()}catch(e){}return info.apply(this,arguments)};L.info.__vok=true}catch(e){}};
setInterval(hookLog,500);
el.app.on("before-quit",function(){clearTimeout(timer);timer=null;off()});

var STATUS_URL="https://raw.githubusercontent.com/JacksonJones2003/vivo-office-kit-english/main/windows/latest.json";
var RELEASES_URL="https://github.com/JacksonJones2003/vivo-office-kit-english/releases?q=windows&expanded=true";
var WDIR=path.join(process.env.LOCALAPPDATA||path.join(os.homedir(),"AppData","Local"),"vivo-office-kit-english-watcher");
var WATCHER=path.join(WDIR,"watcher-on");
var REPO_URL="https://github.com/JacksonJones2003/vivo-office-kit-english/tree/main/windows";
var MARK=(function(){try{return fs.readFileSync(path.join(process.resourcesPath,"app.asar.english-patch"),"utf8")}catch(e){return ""}})();
var mk=function(k){var m=MARK.match(new RegExp("^"+k+"=(.*)$","m"));return m?m[1].trim():""};
var PATCH=/^[\d.]+$/.test(mk("patch"))?mk("patch"):"";
var info={patch:PATCH,mode:mk("mode"),detail:mk("detail"),app:(function(){try{return el.app.getVersion()}catch(e){return ""}})(),watcher:fs.existsSync(WATCHER),full_versions:null,latest:null};
var newer=function(a,b){a=String(a||"").split(".");b=String(b||"").split(".");for(var i=0;i<3;i++){var d=(+a[i]||0)-(+b[i]||0);if(d)return d>0}return false};
/* Runs inside vivo's own windows: (1) a status line under vivo's update window, (2) in the main window, a small
   "English patch - Check for updates" button in the bottom-right corner (minimizes to a small "EN" badge). */
var PAGE=function(info){
  window.__vokInfo=info;
  if(!window.__vokInit){window.__vokInit=true;
    var pending=false,busy=false,KEY="vokPatchPillMinimized";
    var isMin=function(){try{return localStorage.getItem(KEY)==="1"}catch(e){return false}};
    var label=function(){var i=window.__vokInfo||{};return "English patch"+(i.patch?" v"+i.patch:"")+" · Check for updates"};
    var COLORS={ok:"#1a8f3c",warn:"#c27c0e",err:"#c0392b"};
    window.__vokPill=function(text,tone){var s=document.getElementById("vok-settings-status");if(s){s.textContent=text;s.style.color=COLORS[tone]||"";s.style.opacity=tone==="busy"?".75":"1"}
      if(tone!=="busy"){var b=document.getElementById("vok-settings-check");if(b){b.disabled=false;b.style.opacity="1"}}
      var p=document.getElementById("vok-patch-pill");if(!p||isMin())return;var l=p.firstChild;busy=(tone==="busy");l.textContent=text;
      l.style.color=tone==="ok"?"#1a8f3c":tone==="warn"?"#c27c0e":tone==="err"?"#c0392b":"";
      if(tone&&tone!=="busy"){clearTimeout(window.__vokPillT);window.__vokPillT=setTimeout(function(){var q=document.getElementById("vok-patch-pill");if(q&&!isMin()){q.firstChild.textContent=label();q.firstChild.style.color=""}},15000)}};
    var BASE="position:fixed;right:14px;bottom:10px;z-index:2147483000;display:flex;align-items:center;justify-content:center;font:11px/1.3 \"Segoe UI\",-apple-system,BlinkMacSystemFont,sans-serif;color:#8a8f99;background:rgba(127,127,127,.12);border:1px solid rgba(127,127,127,.18);-webkit-user-select:none;user-select:none;backdrop-filter:blur(6px);box-sizing:border-box;";
    /* Draw the button: full ("English patch vX - Check for updates  -") or minimized (a small "EN" badge). */
    var draw=function(p){var min=isMin();if(p.getAttribute("data-min")===String(min)&&p.firstChild)return;p.setAttribute("data-min",String(min));
      while(p.firstChild)p.removeChild(p.firstChild);
      if(min){p.style.cssText=BASE+"width:24px;height:24px;border-radius:12px;padding:0;cursor:pointer;font-weight:600;font-size:9.5px;letter-spacing:.2px";
        p.textContent="EN";p.title=label().replace(" · "," – ")+" (click to expand)";p.onclick=function(){try{localStorage.setItem(KEY,"0")}catch(e){}draw(p)};return}
      p.style.cssText=BASE+"gap:6px;border-radius:11px;padding:3px 6px 3px 10px";p.title="";p.onclick=null;
      var l=document.createElement("span");l.textContent=label();l.title="Check GitHub for a newer English translation";l.style.cssText="cursor:pointer;max-width:60vw;white-space:nowrap;overflow:hidden;text-overflow:ellipsis";
      l.onclick=function(){if(busy)return;window.__vokPill("Checking for updates…","busy");console.log("__VOK_CHECK_UPDATES__")};
      var m=document.createElement("span");m.textContent="–";m.title="Minimize";m.style.cssText="cursor:pointer;font-size:13px;line-height:1;opacity:.7;padding:0 3px";
      m.onclick=function(ev){ev.stopPropagation();busy=false;try{localStorage.setItem(KEY,"1")}catch(e){}draw(p)};
      p.appendChild(l);p.appendChild(m)};
    var pill=function(){if(!/\/index\.html$/.test(location.pathname)||!document.body)return;var p=document.getElementById("vok-patch-pill");
      if(!p){p=document.createElement("div");p.id="vok-patch-pill";document.body.appendChild(p)}draw(p)};
    /* Settings > Version info: an "English patch" section above vivo's own Check for updates button. */
    var settings=function(){var c=document.getElementById("copy-btn");if(!c||!c.parentElement||!c.parentElement.parentElement)return;
      var root=c.parentElement.parentElement.parentElement;if(!root||root.children.length<2)return;var bottom=root.children[1].firstElementChild||root.children[1];
      var i=window.__vokInfo||{},box=document.getElementById("vok-settings");
      if(!box){box=document.createElement("div");box.id="vok-settings";
        box.style.cssText="margin:0 auto 18px;max-width:440px;padding:12px 16px;border-radius:10px;border:1px solid rgba(127,127,127,.25);background:rgba(127,127,127,.08);font:12px/1.5 \"Segoe UI\",-apple-system,BlinkMacSystemFont,sans-serif;text-align:left;";
        var h=document.createElement("div");h.id="vok-settings-title";h.style.cssText="font-weight:600;font-size:13px;margin-bottom:4px";box.appendChild(h);
        var d=document.createElement("div");d.id="vok-settings-detail";d.style.cssText="opacity:.8";box.appendChild(d);
        var row=document.createElement("div");row.style.cssText="display:flex;align-items:center;gap:10px;margin-top:10px;flex-wrap:wrap";
        var b=document.createElement("button");b.id="vok-settings-check";b.textContent="Check for patch updates";
        b.style.cssText="font:inherit;font-size:12px;color:inherit;background:rgba(127,127,127,.2);border:0;border-radius:7px;padding:5px 12px;cursor:pointer";
        b.onclick=function(){b.disabled=true;b.style.opacity=".6";window.__vokPill("Checking for updates…","busy");console.log("__VOK_CHECK_UPDATES__")};
        var a=document.createElement("a");a.textContent="GitHub page ↗";a.href="#";a.style.cssText="color:#3a7afe;text-decoration:none;cursor:pointer";
        a.onclick=function(ev){ev.preventDefault();console.log("__VOK_OPEN_GITHUB__")};
        row.appendChild(b);row.appendChild(a);box.appendChild(row);
        var s=document.createElement("div");s.id="vok-settings-status";s.style.cssText="margin-top:6px;min-height:18px";box.appendChild(s);
        var n=document.createElement("div");n.style.cssText="margin-top:4px;font-size:11px;opacity:.6";n.textContent="Unofficial patch, made entirely by Claude (AI). Not affiliated with vivo.";box.appendChild(n);
        bottom.insertBefore(box,bottom.firstChild)}
      var title="English patch"+(i.patch?" v"+i.patch:"")+(i.mode==="full"?" · full English":i.mode==="basic"?" · basic mode":"");
      var det=(i.mode==="basic"?"This vivo Office Kit version has no full translation yet, so parts of the app stay in Chinese. ":"")+
        (i.full_versions&&i.full_versions.length?"Full translations available for vivo Office Kit "+i.full_versions.join(", ")+".":"")+
        (i.latest&&i.patch&&i.latest!==i.patch?" Latest patch: v"+i.latest+".":"")+
        (i.watcher?" Reapplied automatically after vivo updates.":" Automatic re-patching is off.");
      var T=document.getElementById("vok-settings-title"),D=document.getElementById("vok-settings-detail");
      if(T.textContent!==title)T.textContent=title;if(D.textContent!==det.trim())D.textContent=det.trim()};
    /* "Phone audio": a compact speaker button in the phone card, next to "Transfer history" and "Handoff
       connectivity". It is a copy of vivo's own button (same classes and the card's scoped-style attribute), so vivo's
       stylesheet styles it like the others. Off: click to play the phone's sound on this PC over Bluetooth, without
       mirroring the screen. On (green): click for a panel with a volume slider for the phone's sound and Turn off.
       Clicks go to the main process as console messages; it answers through window.__vokAudio(state). */
    var audioPill=function(){try{var rows=document.querySelectorAll(".buttom-btns-left");
      var a=window.__vokAudioState||{state:"off"},send=function(c){console.log("__VOK_AUDIO__"+c)};
      var key=JSON.stringify({s:a.state,n:a.name,e:a.error,d:a.devices});
      for(var r=0;r<rows.length;r++){var row=rows[r],b=row.querySelector(".vok-audio-btn");
        if(!b){var ref=row.querySelector(".buttom-btn"),refText=ref&&ref.querySelector(".buttom-btn-text");if(!ref||!refText)continue;
          var scoped=[].slice.call(ref.attributes).filter(function(x){return x.name.indexOf("data-v-")===0});
          b=ref.cloneNode(false);b.classList.add("vok-audio-btn");b.removeAttribute("id");b.style.cssText+=";flex:none;width:28px;min-width:28px;padding:0";
          var ns="http://www.w3.org/2000/svg",svg=document.createElementNS(ns,"svg");scoped.forEach(function(x){svg.setAttribute(x.name,x.value)});
          svg.setAttribute("class","svg-icon");svg.setAttribute("viewBox","0 0 24 24");svg.setAttribute("fill","none");svg.setAttribute("stroke","currentColor");
          svg.setAttribute("stroke-width","1.8");svg.setAttribute("stroke-linecap","round");svg.setAttribute("stroke-linejoin","round");svg.style.cssText="display:block;width:16px;height:16px;min-width:16px";
          ["M4 9.5h3.5L12 5.5v13l-4.5-4H4z","M15.5 9a4 4 0 0 1 0 6","M18 6.5a7.5 7.5 0 0 1 0 11"].forEach(function(d){var pth=document.createElementNS(ns,"path");pth.setAttribute("d",d);svg.appendChild(pth)});
          b.appendChild(svg);var t0=refText.cloneNode(false);t0.style.display="none";t0.textContent="Phone audio";b.appendChild(t0);
          b.onclick=function(ev){ev.stopPropagation();var s=(window.__vokAudioState||{}).state;if(s==="searching"||s==="connecting")return;
            if(s==="on"){if(document.querySelector(".vok-audio-panel"))return closePanel();return openPanel(this)}send("toggle")};
          row.appendChild(b)}
        var on=a.state==="on",busy=a.state==="searching"||a.state==="connecting";
        var pct=typeof a.volume==="number"&&a.volume>=0?Math.round(a.volume*100):null;
        b.title=a.state==="searching"?"Phone audio: looking for your phone…":a.state==="connecting"?"Phone audio: connecting to "+a.name+"…":
          on?"Phone audio is on: "+a.name+" plays through this PC"+(pct!==null?" at "+pct+"%":"")+". Click for volume or to turn it off.":
          a.state==="error"?"Phone audio: "+a.error+" Click to try again.":"Phone audio: play your phone's sound through this PC over Bluetooth, without mirroring the screen";
        if(b.getAttribute("data-k")===key)continue;b.setAttribute("data-k",key);
        var col=on?"#1a8f3c":a.state==="error"?"#c0392b":"";b.querySelector("svg").style.color=col;b.style.opacity=busy?".5":"";
        b.style.borderColor=on?"rgba(26,143,60,.45)":"";b.style.cursor=busy?"default":"";
        if(!on)closePanel();
        var old=document.querySelector(".vok-audio-menu");if(old)old.parentNode.removeChild(old);
        if(a.state==="choose"&&a.devices){var m=floating(b,"vok-audio-menu");m.style.padding="6px 0";
          var item=function(label,fn,dim){var d=document.createElement("div");d.textContent=label;d.style.cssText="padding:6px 14px;cursor:pointer;white-space:nowrap"+(dim?";opacity:.6":"");d.onmouseenter=function(){d.style.background="rgba(127,127,127,.12)"};d.onmouseleave=function(){d.style.background=""};d.onclick=function(ev){ev.stopPropagation();fn()};m.appendChild(d)};
          var head=document.createElement("div");head.textContent="Play audio from:";head.style.cssText="padding:4px 14px 6px;opacity:.6";m.appendChild(head);
          a.devices.forEach(function(dv,i){item(dv.name,function(){send("pick:"+i)})});item("Cancel",function(){send("stop")},!0)}}
      var vs=document.querySelector(".vok-audio-panel input[type=range]");
      if(vs&&!vs.__drag&&typeof a.volume==="number"&&a.volume>=0){vs.value=Math.round(a.volume*100);vs.oninput&&vs.__label&&(vs.__label.textContent=vs.value+"%")}}catch(e){}};
    /* A small panel anchored under the button (fixed position, so the card's layout is untouched). */
    var floating=function(btn,cls){var q=btn.getBoundingClientRect(),m=document.createElement("div");m.className=cls;
      m.style.cssText="position:fixed;top:"+Math.round(q.bottom+6)+"px;left:"+Math.round(Math.max(8,q.right-220))+"px;width:220px;box-sizing:border-box;z-index:3000;border-radius:10px;"+
        "background:var(--color-bg-1,#fff);color:var(--connection-device-detail-buttom-btn-color,#222);box-shadow:0 6px 24px rgba(0,0,0,.18);border:1px solid rgba(127,127,127,.18);"+
        "font:12px/1.4 \"Segoe UI\",sans-serif;text-align:left";m.onclick=function(ev){ev.stopPropagation()};document.body.appendChild(m);return m};
    var closePanel=function(){var p=document.querySelector(".vok-audio-panel");if(p)p.parentNode.removeChild(p);document.removeEventListener("mousedown",outside,true)};
    var outside=function(ev){var p=document.querySelector(".vok-audio-panel");if(p&&!p.contains(ev.target)&&!(ev.target.closest&&ev.target.closest(".vok-audio-btn")))closePanel()};
    var openPanel=function(btn){closePanel();var a=window.__vokAudioState||{},send=function(c){console.log("__VOK_AUDIO__"+c)};
      var p=floating(btn,"vok-audio-panel");p.style.padding="12px 14px";
      var h=document.createElement("div");h.textContent=(a.name||"Phone")+" audio";h.style.cssText="font-weight:600;margin-bottom:8px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis";p.appendChild(h);
      var row=document.createElement("div");row.style.cssText="display:flex;align-items:center;gap:8px";
      var lo=document.createElementNS("http://www.w3.org/2000/svg","svg");lo.setAttribute("viewBox","0 0 24 24");lo.setAttribute("fill","none");lo.setAttribute("stroke","currentColor");lo.setAttribute("stroke-width","1.8");lo.setAttribute("stroke-linejoin","round");lo.style.cssText="width:14px;height:14px;flex:none;opacity:.7";
      var lp=document.createElementNS("http://www.w3.org/2000/svg","path");lp.setAttribute("d","M4 9.5h3.5L12 5.5v13l-4.5-4H4z");lo.appendChild(lp);row.appendChild(lo);
      var s=document.createElement("input");s.type="range";s.min="0";s.max="100";s.step="1";s.style.cssText="flex:1;min-width:0;accent-color:#3a7afe;cursor:pointer";
      s.value=typeof a.volume==="number"&&a.volume>=0?Math.round(a.volume*100):100;
      var lab=document.createElement("span");lab.style.cssText="width:34px;text-align:right;font-variant-numeric:tabular-nums;opacity:.8";lab.textContent=s.value+"%";s.__label=lab;
      var last=0,pendingV=null,flush=function(){if(pendingV!==null){send("vol:"+(pendingV/100));pendingV=null;last=Date.now()}};
      s.oninput=function(){lab.textContent=s.value+"%";pendingV=+s.value;if(Date.now()-last>60)flush();else setTimeout(flush,70)};
      s.onpointerdown=function(){s.__drag=true};s.onpointerup=s.onchange=function(){s.__drag=false;flush()};
      row.appendChild(s);row.appendChild(lab);p.appendChild(row);
      var note=document.createElement("div");note.textContent="Controls only your phone's sound on this PC.";note.style.cssText="margin-top:6px;font-size:11px;opacity:.55";p.appendChild(note);
      var off=document.createElement("div");off.textContent="Turn off phone audio";off.style.cssText="margin-top:10px;padding-top:8px;border-top:1px solid rgba(127,127,127,.18);color:#c0392b;cursor:pointer";
      off.onclick=function(){closePanel();send("toggle")};p.appendChild(off);
      document.addEventListener("mousedown",outside,true)};
    window.__vokAudio=function(s){window.__vokAudioState=s;audioPill()};
    var render=function(){pending=false;pill();settings();audioPill();var i=window.__vokInfo;if(!i||!i.full_versions)return;
      var eds=document.querySelectorAll(".edition");
      for(var k=0;k<eds.length;k++){var ed=eds[k],m=(ed.textContent||"").match(/\d+(?:\.\d+){1,3}/);if(!m||!ed.parentNode)continue;var ver=m[0];
        var box=ed.parentNode,line=box.querySelector(".vok-en-status");
        if(!line){line=document.createElement("div");line.className="vok-en-status";line.style.cssText="margin-top:8px;font-size:12px;line-height:1.45;white-space:normal;";box.appendChild(line)}
        var ok=i.full_versions.indexOf(ver)>=0,txt;
        if(ok)txt="✓ English translation ready for "+ver+(i.watcher?". The English patch will be reapplied after you update.":". After updating, run the English patch installer again.");
        else txt="⚠ No English translation for "+ver+" yet. If you update now, parts of the app will be in Chinese until one is published"+(i.watcher?" (you will get a popup when it is).":".");
        if(line.textContent!==txt){line.textContent=txt;line.style.color=ok?"#1a8f3c":"#c0392b"}}};
    window.__vokRender=render;
    new MutationObserver(function(){if(!pending){pending=true;setTimeout(render,250)}}).observe(document.documentElement,{childList:true,subtree:true,characterData:true});
  }
  var p=document.getElementById("vok-patch-pill");if(p){p.removeAttribute("data-min")}
  window.__vokRender();
};
var mine=function(wc){try{return !wc.isDestroyed()&&/^file:/.test(wc.getURL())}catch(e){return false}};
var inject=function(wc){try{if(mine(wc))wc.executeJavaScript("("+PAGE.toString()+")("+JSON.stringify(info)+")",true).catch(function(){})}catch(e){}};
var pill=function(wc,text,tone){try{if(mine(wc))wc.executeJavaScript("window.__vokPill&&window.__vokPill("+JSON.stringify(text)+","+JSON.stringify(tone)+")",true).catch(function(){})}catch(e){}};
var fetchInfo=function(cb){var done=function(ok){if(cb){var c=cb;cb=null;c(ok)}};try{https.get(STATUS_URL,{timeout:15000,headers:{"Cache-Control":"no-cache"}},function(r){if(r.statusCode!==200){r.resume();return done(false)}var b="";r.setEncoding("utf8");r.on("data",function(c){if(b.length<65536)b+=c});r.on("end",function(){try{var m=JSON.parse(b);if(!Array.isArray(m.full_versions))return done(false);
  info.full_versions=m.full_versions.filter(function(v){return typeof v==="string"&&/^[\d.]+$/.test(v)}).slice(0,500);info.latest=/^[\d.]+$/.test(m.version)?m.version:null;info.watcher=fs.existsSync(WATCHER);
  el.webContents.getAllWebContents().forEach(inject);done(true)}catch(e){done(false)}})}).on("timeout",function(){this.destroy()}).on("error",function(){done(false)})}catch(e){done(false)}};
/* The "Check for updates" button: check GitHub now; if there is a newer patch, wake the helper so its install popup
   appears right away (or open the download page if automatic re-patching is not set up). The helper watches its
   folder for these request files. */
var wake=function(file){try{if(!fs.existsSync(WATCHER))return false;fs.writeFileSync(path.join(WDIR,file),String(Date.now()));return true}catch(e){return false}};
var manualCheck=function(wc){fetchInfo(function(ok){
  if(!ok)return pill(wc,"Couldn't reach GitHub. Try again later.","err");
  if(!info.latest||!newer(info.latest,PATCH))return pill(wc,"English patch is up to date"+(PATCH?" (v"+PATCH+")":"")+".","ok");
  if(wake("manual-request"))return pill(wc,"Update v"+info.latest+" available. Follow the popup to install it.","warn");
  try{el.shell.openExternal(info.latest?"https://github.com/JacksonJones2003/vivo-office-kit-english/releases/tag/windows-v"+info.latest:RELEASES_URL)}catch(e){}
  pill(wc,"Update v"+info.latest+" available. Opened the download page.","warn")})};
/* "Phone audio on PC": the PC becomes a Bluetooth speaker for the phone, using Windows' own receiver through a small
   PowerShell helper (resources\english-patch-bt-audio.ps1, installed by the patch). The helper keeps the connection
   open and reports its state as JSON lines; it ends when vivo Office Kit quits. */
var VOLF=path.join(el.app.getPath("userData"),"english-patch-audio.json");
var savedVol=function(){try{var v=JSON.parse(fs.readFileSync(VOLF,"utf8")).volume;return typeof v==="number"&&v>=0&&v<=1?v:null}catch(e){return null}};
var audio={state:"off",name:"",error:"",devices:null,volume:savedVol()},aproc=null;
var BT_PS=path.join(process.resourcesPath,"english-patch-bt-audio.ps1");
var PS_EXE=path.join(process.env.SystemRoot||"C:\\Windows","System32","WindowsPowerShell","v1.0","powershell.exe");
var runBt=function(env){return spawn.call(cp,PS_EXE,["-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass","-WindowStyle","Hidden","-File",BT_PS],{env:Object.assign({},process.env,env),windowsHide:true,stdio:["pipe","pipe","ignore"]})};
var pushAudio=function(wcs){(wcs||el.webContents.getAllWebContents()).forEach(function(wc){try{if(mine(wc))wc.executeJavaScript("window.__vokAudio&&window.__vokAudio("+JSON.stringify(audio)+")",true).catch(function(){})}catch(e){}})};
var setAudio=function(s){for(var k in s)audio[k]=s[k];pushAudio()};
var readLines=function(p,cb){var buf="";p.stdout.setEncoding("utf8");p.stdout.on("data",function(d){buf+=d;var i;while((i=buf.indexOf("\n"))>=0){var l=buf.slice(0,i).trim();buf=buf.slice(i+1);if(l){try{cb(JSON.parse(l))}catch(e){}}}})};
var audioStop=function(quiet){if(aproc){var p=aproc;aproc=null;try{p.kill()}catch(e){}}if(!quiet)setAudio({state:"off",devices:null,error:""})};
var audioConnect=function(dev){audioStop(true);setAudio({state:"connecting",name:dev.name,error:"",devices:null});
  var env={VOK_BT_MODE:"connect",VOK_BT_ID:dev.id,VOK_BT_PARENT:String(process.pid)};if(typeof audio.volume==="number")env.VOK_BT_VOLUME=String(audio.volume);
  var p=aproc=runBt(env);
  readLines(p,function(m){if(aproc!==p)return;if(m.state==="connected")setAudio({state:"on"});else if(m.state==="closed")setAudio({state:"off"});else if(m.state==="volume"&&typeof m.volume==="number"&&m.volume>=0)setAudio({volume:m.volume});else if(m.state==="error")setAudio({state:"error",error:m.error||"Could not connect."})});
  p.on("exit",function(){if(aproc===p){aproc=null;if(audio.state==="on"||audio.state==="connecting")setAudio({state:"off"})}});
  p.on("error",function(){if(aproc===p){aproc=null;setAudio({state:"error",error:"Could not start the audio helper."})}})};
var audioToggle=function(){if(audio.state==="on"||audio.state==="connecting")return audioStop();
  if(!fs.existsSync(BT_PS))return setAudio({state:"error",error:"Run the English patch installer again to add phone audio."});
  setAudio({state:"searching",error:"",devices:null});var p=runBt({VOK_BT_MODE:"list"}),got=false;
  readLines(p,function(m){got=true;var d=(m&&m.devices)||[];
    if(!d.length)return setAudio({state:"error",error:"No paired phone found. Pair your phone with this PC in Windows Bluetooth settings first."});
    if(d.length===1)return audioConnect(d[0]);setAudio({state:"choose",devices:d})});
  p.on("exit",function(){if(!got&&audio.state==="searching")setAudio({state:"error",error:"Could not check Bluetooth. Is Bluetooth on?"})});
  p.on("error",function(){setAudio({state:"error",error:"Could not start the audio helper."})})};
var audioVolume=function(v){v=Math.max(0,Math.min(1,+v));if(isNaN(v))return;audio.volume=v;try{fs.writeFileSync(VOLF,JSON.stringify({volume:v}))}catch(e){}
  if(aproc&&aproc.stdin&&!aproc.stdin.destroyed){try{aproc.stdin.write("vol "+v.toFixed(3)+"\n")}catch(e){}}};
var audioMsg=function(c){if(c==="toggle")audioToggle();else if(c.indexOf("vol:")===0)audioVolume(c.slice(4));else if(c==="stop")audioStop();else if(c.indexOf("pick:")===0){var d=audio.devices&&audio.devices[+c.slice(5)];if(d)audioConnect(d)}};
el.app.on("before-quit",function(){audioStop(true)});
el.app.on("web-contents-created",function(e,wc){wc.on("dom-ready",function(){inject(wc);pushAudio([wc])});wc.on("console-message",function(ev,level,msg){if(!mine(wc))return;
  if(typeof msg==="string"&&msg.indexOf("__VOK_AUDIO__")===0)audioMsg(msg.slice(13));else if(msg==="__VOK_CHECK_UPDATES__")manualCheck(wc);else if(msg==="__VOK_OPEN_GITHUB__"){try{el.shell.openExternal(REPO_URL)}catch(e){}}})});
/* Ask the background helper (if installed) to look for a newer translation now that the app has started. */
var nudge=function(){wake("launch-request")};
el.app.whenReady().then(function(){fetchInfo();setInterval(fetchInfo,6*3600*1000);setTimeout(nudge,15000)}).catch(function(){});
}catch(e){}})();
