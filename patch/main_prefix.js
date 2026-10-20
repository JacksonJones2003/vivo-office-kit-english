;(function(){try{
/* English patch: the phone-mirroring and PC-mode helper apps only load English when config.json has
   isExport=true at the moment they start. The connection service reads the same flag, so it is switched
   on just while a helper launches and switched back off afterwards.
   It also adds a line under vivo's "update available" window saying whether an English translation exists
   for the new version (from latest.json in the patch's GitHub repository), and asks the background helper
   to check for a newer translation each time the app starts. */
var cp=require("child_process"),fs=require("fs"),path=require("path"),os=require("os"),https=require("https"),el=require("electron");
var upd=function(fn){try{var p=path.join(el.app.getPath("userData"),"config.json"),d=JSON.parse(fs.readFileSync(p,"utf8")),before=JSON.stringify(d);fn(d);if(JSON.stringify(d)!==before){var tmp=p+".tmp-en";fs.writeFileSync(tmp,JSON.stringify(d,null,"\t"),{mode:fs.statSync(p).mode&511});fs.renameSync(tmp,p)}}catch(e){}};
var off=function(){upd(function(d){if(d.isExport===true)d.isExport=false})};
var timer=null,spawn=cp.spawn;
var english=function(){upd(function(d){if(d.isExport===true&&!timer)d.isExport=false;d.currentLanguage="en_US";d.isRtl=false})};
english();[2000,8000,20000,60000].forEach(function(ms){setTimeout(english,ms)});
cp.spawn=function(cmd){try{if(typeof cmd==="string"&&/\/(vivoScreen|vScreen|PCMode)$/.test(cmd)){upd(function(d){d.isExport=true;d.currentLanguage="en_US";d.isRtl=false});clearTimeout(timer);timer=setTimeout(function(){timer=null;off()},12000)}}catch(e){}return spawn.apply(this,arguments)};
el.app.on("before-quit",function(){clearTimeout(timer);timer=null;off()});

var info=null;
var STATUS_URL="https://raw.githubusercontent.com/JacksonJones2003/vivo-office-kit-english-mac/main/latest.json";
var WATCHER=path.join(os.homedir(),"Library/LaunchAgents/io.github.jacksonjones2003.vivo-english-watcher.plist");
/* Runs inside vivo's own windows: finds the update window's version label and adds the status line under it. */
var PAGE=function(info){
  window.__vokInfo=info;
  if(window.__vokRender){window.__vokRender();return}
  var pending=false;
  var render=function(){pending=false;var i=window.__vokInfo;if(!i)return;
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
  render();
};
var inject=function(wc){try{if(info&&!wc.isDestroyed()&&/^file:/.test(wc.getURL()))wc.executeJavaScript("("+PAGE.toString()+")("+JSON.stringify(info)+")",true).catch(function(){})}catch(e){}};
var fetchInfo=function(){try{https.get(STATUS_URL,{timeout:15000},function(r){if(r.statusCode!==200){r.resume();return}var b="";r.setEncoding("utf8");r.on("data",function(c){if(b.length<65536)b+=c});r.on("end",function(){try{var m=JSON.parse(b);if(!Array.isArray(m.full_versions))return;
  info={full_versions:m.full_versions.filter(function(v){return typeof v==="string"&&/^[\d.]+$/.test(v)}).slice(0,500),watcher:fs.existsSync(WATCHER)};
  el.webContents.getAllWebContents().forEach(inject)}catch(e){}})}).on("timeout",function(){this.destroy()}).on("error",function(){})}catch(e){}};
el.app.on("web-contents-created",function(e,wc){wc.on("dom-ready",function(){inject(wc)})});
/* Ask the background helper (if installed) to look for a newer translation now that the app has started. */
var nudge=function(){try{if(!fs.existsSync(WATCHER))return;var d=path.join(os.homedir(),"Library/Application Support/vivo-office-kit-english-watcher");if(!fs.existsSync(d))return;fs.writeFileSync(path.join(d,"launch-request"),String(Date.now()));
  var c=spawn.call(cp,"/bin/launchctl",["kickstart","gui/"+process.getuid()+"/io.github.jacksonjones2003.vivo-english-watcher"],{stdio:"ignore",detached:true});c.on("error",function(){});c.unref()}catch(e){}};
el.app.whenReady().then(function(){fetchInfo();setInterval(fetchInfo,6*3600*1000);setTimeout(nudge,15000)}).catch(function(){});
}catch(e){}})();
