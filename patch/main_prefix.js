;(function(){try{
/* English patch: the phone-mirroring and PC-mode helper apps only load English when config.json has
   isExport=true at the moment they start. The connection service reads the same flag, so it is switched
   on just while a helper launches and switched back off afterwards.
   It also adds a line under vivo's "update available" window saying whether an English translation exists
   for the new version (from latest.json in the patch's GitHub repository), adds a "Check for updates" button to
   the main window, and asks the background helper to check for a newer translation each time the app starts. */
var cp=require("child_process"),fs=require("fs"),path=require("path"),os=require("os"),https=require("https"),el=require("electron");
var upd=function(fn){try{var p=path.join(el.app.getPath("userData"),"config.json"),d=JSON.parse(fs.readFileSync(p,"utf8")),before=JSON.stringify(d);fn(d);if(JSON.stringify(d)!==before){var tmp=p+".tmp-en";fs.writeFileSync(tmp,JSON.stringify(d,null,"\t"),{mode:fs.statSync(p).mode&511});fs.renameSync(tmp,p)}}catch(e){}};
var off=function(){upd(function(d){if(d.isExport===true)d.isExport=false})};
var timer=null,spawn=cp.spawn;
var english=function(){upd(function(d){if(d.isExport===true&&!timer)d.isExport=false;d.currentLanguage="en_US";d.isRtl=false})};
english();[2000,8000,20000,60000].forEach(function(ms){setTimeout(english,ms)});
cp.spawn=function(cmd){try{if(typeof cmd==="string"&&/\/(vivoScreen|vScreen|PCMode)$/.test(cmd)){upd(function(d){d.isExport=true;d.currentLanguage="en_US";d.isRtl=false});clearTimeout(timer);timer=setTimeout(function(){timer=null;off()},12000)}}catch(e){}return spawn.apply(this,arguments)};
el.app.on("before-quit",function(){clearTimeout(timer);timer=null;off()});

var STATUS_URL="https://raw.githubusercontent.com/JacksonJones2003/vivo-office-kit-english-mac/main/latest.json";
var RELEASES_URL="https://github.com/JacksonJones2003/vivo-office-kit-english-mac/releases/latest";
var WATCHER=path.join(os.homedir(),"Library/LaunchAgents/io.github.jacksonjones2003.vivo-english-watcher.plist");
var WDIR=path.join(os.homedir(),"Library/Application Support/vivo-office-kit-english-watcher");
var REPO_URL="https://github.com/JacksonJones2003/vivo-office-kit-english-mac";
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
    var BASE="position:fixed;right:14px;bottom:10px;z-index:2147483000;display:flex;align-items:center;justify-content:center;font:11px/1.3 -apple-system,BlinkMacSystemFont,sans-serif;color:#8a8f99;background:rgba(127,127,127,.12);border:1px solid rgba(127,127,127,.18);-webkit-user-select:none;user-select:none;backdrop-filter:blur(6px);box-sizing:border-box;";
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
        box.style.cssText="margin:0 auto 18px;max-width:440px;padding:12px 16px;border-radius:10px;border:1px solid rgba(127,127,127,.25);background:rgba(127,127,127,.08);font:12px/1.5 -apple-system,BlinkMacSystemFont,sans-serif;text-align:left;";
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
    var render=function(){pending=false;pill();settings();var i=window.__vokInfo;if(!i||!i.full_versions)return;
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
   appears right away (or open the download page if automatic re-patching is not set up). */
var wake=function(file){try{if(!fs.existsSync(WATCHER)||!fs.existsSync(WDIR))return false;fs.writeFileSync(path.join(WDIR,file),String(Date.now()));
  var c=spawn.call(cp,"/bin/launchctl",["kickstart","gui/"+process.getuid()+"/io.github.jacksonjones2003.vivo-english-watcher"],{stdio:"ignore",detached:true});c.on("error",function(){});c.unref();return true}catch(e){return false}};
var manualCheck=function(wc){fetchInfo(function(ok){
  if(!ok)return pill(wc,"Couldn't reach GitHub. Try again later.","err");
  if(!info.latest||!newer(info.latest,PATCH))return pill(wc,"English patch is up to date"+(PATCH?" (v"+PATCH+")":"")+".","ok");
  if(wake("manual-request"))return pill(wc,"Update v"+info.latest+" available. Follow the popup to install it.","warn");
  try{el.shell.openExternal(RELEASES_URL)}catch(e){}
  pill(wc,"Update v"+info.latest+" available. Opened the download page.","warn")})};
el.app.on("web-contents-created",function(e,wc){wc.on("dom-ready",function(){inject(wc)});wc.on("console-message",function(ev,level,msg){if(!mine(wc))return;
  if(msg==="__VOK_CHECK_UPDATES__")manualCheck(wc);else if(msg==="__VOK_OPEN_GITHUB__"){try{el.shell.openExternal(REPO_URL)}catch(e){}}})});
/* Ask the background helper (if installed) to look for a newer translation now that the app has started. */
var nudge=function(){wake("launch-request")};
el.app.whenReady().then(function(){fetchInfo();setInterval(fetchInfo,6*3600*1000);setTimeout(nudge,15000)}).catch(function(){});
}catch(e){}})();
