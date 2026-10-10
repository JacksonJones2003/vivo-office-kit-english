;(function(){try{
/* English patch: the phone-mirroring and PC-mode helper apps only load English when config.json has
   isExport=true at the moment they start. The connection service reads the same flag, so it is switched
   on just while a helper launches and switched back off afterwards. */
var cp=require("child_process"),fs=require("fs"),path=require("path"),el=require("electron");
var upd=function(fn){try{var p=path.join(el.app.getPath("userData"),"config.json"),d=JSON.parse(fs.readFileSync(p,"utf8")),before=JSON.stringify(d);fn(d);if(JSON.stringify(d)!==before){var tmp=p+".tmp-en";fs.writeFileSync(tmp,JSON.stringify(d,null,"\t"),{mode:fs.statSync(p).mode&511});fs.renameSync(tmp,p)}}catch(e){}};
var off=function(){upd(function(d){if(d.isExport===true)d.isExport=false})};
var timer=null,spawn=cp.spawn;
var english=function(){upd(function(d){if(d.isExport===true&&!timer)d.isExport=false;d.currentLanguage="en_US";d.isRtl=false})};
english();[2000,8000,20000,60000].forEach(function(ms){setTimeout(english,ms)});
cp.spawn=function(cmd){try{if(typeof cmd==="string"&&/\/(vivoScreen|vScreen|PCMode)$/.test(cmd)){upd(function(d){d.isExport=true;d.currentLanguage="en_US";d.isRtl=false});clearTimeout(timer);timer=setTimeout(function(){timer=null;off()},12000)}}catch(e){}return spawn.apply(this,arguments)};
el.app.on("before-quit",function(){clearTimeout(timer);timer=null;off()});
}catch(e){}})();
