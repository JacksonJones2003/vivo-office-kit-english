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
var PATCH=(function(){try{var m=fs.readFileSync(path.join(process.resourcesPath,"app.asar.english-patch"),"utf8").match(/^patch=([\d.]+)/m);return m?m[1]:""}catch(e){return ""}})();
var info={patch:PATCH,watcher:fs.existsSync(WATCHER),full_versions:null,latest:null};
var newer=function(a,b){a=String(a||"").split(".");b=String(b||"").split(".");for(var i=0;i<3;i++){var d=(+a[i]||0)-(+b[i]||0);if(d)return d>0}return false};
/* Runs inside vivo's own windows: (1) a status line under vivo's update window, (2) in the main window, a small
   "English patch - Check for updates" button in the bottom-right corner. */
var PAGE=function(info){
  window.__vokInfo=info;
  if(!window.__vokInit){window.__vokInit=true;
    var pending=false,hidden=false,busy=false;
    window.__vokPill=function(text,tone){var p=document.getElementById("vok-patch-pill");if(!p)return;var l=p.firstChild;busy=(tone==="busy");l.textContent=text;
      l.style.color=tone==="ok"?"#1a8f3c":tone==="warn"?"#c27c0e":tone==="err"?"#c0392b":"";
      if(tone&&tone!=="busy"){clearTimeout(window.__vokPillT);window.__vokPillT=setTimeout(function(){l.textContent=label();l.style.color=""},15000)}};
    var label=function(){var i=window.__vokInfo||{};return "English patch"+(i.patch?" v"+i.patch:"")+" · Check for updates"};
    var pill=function(){if(hidden||!/\/index\.html$/.test(location.pathname)||!document.body||document.getElementById("vok-patch-pill"))return;
      var p=document.createElement("div");p.id="vok-patch-pill";
      p.style.cssText="position:fixed;right:14px;bottom:10px;z-index:2147483000;display:flex;align-items:center;gap:6px;font:11px/1.3 -apple-system,BlinkMacSystemFont,sans-serif;color:#8a8f99;background:rgba(127,127,127,.12);border:1px solid rgba(127,127,127,.18);border-radius:11px;padding:3px 6px 3px 10px;-webkit-user-select:none;user-select:none;backdrop-filter:blur(6px)";
      var l=document.createElement("span");l.textContent=label();l.title="Check GitHub for a newer English translation";l.style.cssText="cursor:pointer;max-width:60vw;white-space:nowrap;overflow:hidden;text-overflow:ellipsis";
      l.onclick=function(){if(busy)return;window.__vokPill("Checking for updates…","busy");console.log("__VOK_CHECK_UPDATES__")};
      var x=document.createElement("span");x.textContent="×";x.title="Hide until vivo Office Kit is opened again";x.style.cssText="cursor:pointer;font-size:13px;opacity:.7;padding:0 2px";
      x.onclick=function(){hidden=true;p.remove()};
      p.appendChild(l);p.appendChild(x);document.body.appendChild(p)};
    var render=function(){pending=false;pill();var i=window.__vokInfo;if(!i||!i.full_versions)return;
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
  var p=document.getElementById("vok-patch-pill");if(p&&p.firstChild&&/Check for updates$/.test(p.firstChild.textContent))p.firstChild.textContent="English patch"+(info.patch?" v"+info.patch:"")+" · Check for updates";
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
el.app.on("web-contents-created",function(e,wc){wc.on("dom-ready",function(){inject(wc)});wc.on("console-message",function(ev,level,msg){if(msg==="__VOK_CHECK_UPDATES__"&&mine(wc))manualCheck(wc)})});
/* Ask the background helper (if installed) to look for a newer translation now that the app has started. */
var nudge=function(){wake("launch-request")};
el.app.whenReady().then(function(){fetchInfo();setInterval(fetchInfo,6*3600*1000);setTimeout(nudge,15000)}).catch(function(){});
}catch(e){}})();
