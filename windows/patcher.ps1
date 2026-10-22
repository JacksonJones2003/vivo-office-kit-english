# vivo Office Kit (pcsuite) for Windows, China edition -> English.
# Rewrites resources\app.asar of the installed app. Uses only what ships with Windows PowerShell 5.1.
#
#   powershell -File patcher.ps1 status  [-App "C:\Program Files (x86)\pcsuite"]
#   powershell -File patcher.ps1 install [-App ...]
#   powershell -File patcher.ps1 restore [-App ...]
#   powershell -File patcher.ps1 version   (version of this patch)
#
# Each file inside the archive is handled on its own:
#   full  - the file is byte-for-byte one this patch was built from: the exact, checksum-verified edit list
#           for that file in patch\edits.dat is applied.
#   basic - the file differs (another version): the language lock is found by pattern and removed,
#           which switches the app to vivo's own built-in English. Untested on other versions.
#
# `status` prints four lines: state (original|patched|unsupported), app path, mode (full|basic|none), detail.
# Exit codes: 0 ok, 2 app not found, 3 unsupported build, 4 permission denied, 5 file in use, 1 other error.
param([Parameter(Position = 0)][string]$Command = 'status', [string]$App, [string]$Patch)
Set-StrictMode -Off
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Web.Extensions

$PATCH_VERSION = '1.8.2'
$BLOCK  = 4 * 1024 * 1024
$MARK   = ";(function(){try{`n/* English patch"   # start of patch\main_prefix.js
$DIST   = 'dist/electron'
$RENDER = @('renderer.js', 'child-window.js', 'module-share-preview.js')
$Lat    = [Text.Encoding]::GetEncoding(28591)       # bytes <-> chars 1:1, so offsets stay byte offsets
$Sha    = [Security.Cryptography.SHA256]::Create()
$Ser    = New-Object Web.Script.Serialization.JavaScriptSerializer
$Ser.MaxJsonLength = [int]::MaxValue; $Ser.RecursionLimit = 10000

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
if ($Command -eq 'version') { Write-Output $PATCH_VERSION; exit 0 }
if (-not $Patch) { $Patch = Join-Path $here 'patch' }

function Fail([int]$code, [string]$msg) { [Console]::Error.WriteLine($msg); exit $code }
function Err-Code($e) {
    $x = $e.Exception; while ($x.InnerException -and -not ($x -is [UnauthorizedAccessException]) -and -not ($x -is [IO.IOException])) { $x = $x.InnerException }
    if ($x -is [UnauthorizedAccessException]) { return 4 }
    if ($x -is [IO.IOException] -and (($x.HResult -band 0xFFFF) -in 32, 33)) { return 5 }   # sharing / lock violation
    return 1
}
function Hex([byte[]]$b) { -join ($Sha.ComputeHash($b) | ForEach-Object { $_.ToString('x2') }) }
function Sha-Str([string]$s) { Hex $Lat.GetBytes($s) }
function Slurp([string]$p) { try { $Lat.GetString([IO.File]::ReadAllBytes($p)) } catch { Fail 1 "Cannot read $p" } }

function Find-App {
    $c = New-Object Collections.ArrayList
    foreach ($k in 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*') {
        foreach ($e in @(Get-ItemProperty $k -ErrorAction SilentlyContinue)) {
            $txt = "$($e.DisplayName) $($e.DisplayIcon) $($e.UninstallString)"
            if ($txt -notmatch 'pcsuite') { continue }
            if ($e.InstallLocation) { [void]$c.Add($e.InstallLocation.Trim('"')) }
            foreach ($v in $e.DisplayIcon, $e.UninstallString) { if ($v -and $v -match '^"?([^"]+\\)[^\\"]+\.exe') { [void]$c.Add($Matches[1]) } }
        }
    }
    foreach ($d in "${env:ProgramFiles(x86)}\pcsuite", "$env:ProgramFiles\pcsuite", "$env:LOCALAPPDATA\Programs\pcsuite") { [void]$c.Add($d) }
    foreach ($d in $c) { if ($d -and (Test-Path -LiteralPath (Join-Path $d 'resources\app.asar'))) { return (Resolve-Path -LiteralPath $d).ProviderPath.TrimEnd('\') } }
    return $null
}

if (-not $App) { $App = Find-App }
if (-not $App -or -not (Test-Path -LiteralPath (Join-Path $App 'resources'))) { Fail 2 "vivo Office Kit (pcsuite) was not found. Install it first." }
$App    = $App.TrimEnd('\')
$res    = Join-Path $App 'resources'
$asar   = Join-Path $res 'app.asar'
$backup = Join-Path $res 'app.asar.zh-backup'
$marker = Join-Path $res 'app.asar.english-patch'
$vivoOriginal = Join-Path $res 'app.asar.original'      # vivo's installer sometimes leaves its pristine copy here
$aside  = Join-Path $res 'app.asar.pre-english-patch'   # where a different, unrelated patch is kept if we replace it
if (-not (Test-Path -LiteralPath $asar)) { Fail 2 "app.asar not found in $res" }

# ---------------------------------------------------------------- archive helpers
function Read-Exact($fs, [byte[]]$buf, [int]$n) { $g = 0; while ($g -lt $n) { $r = $fs.Read($buf, $g, $n - $g); if ($r -le 0) { return $false }; $g += $r }; return $true }
function Read-Header([string]$path) {
    try { $fs = [IO.File]::Open($path, 'Open', 'Read', 'ReadWrite') } catch { return $null }
    try {
        $h = New-Object byte[] 16; if (-not (Read-Exact $fs $h 16)) { return $null }
        $four = [BitConverter]::ToUInt32($h, 0); $hsize = [BitConverter]::ToUInt32($h, 4); $jlen = [BitConverter]::ToUInt32($h, 12)
        if ($four -ne 4 -or $jlen -le 2 -or $jlen -gt 200MB) { return $null }
        $raw = New-Object byte[] $jlen; if (-not (Read-Exact $fs $raw $jlen)) { return $null }
        $tree = $Ser.DeserializeObject([Text.Encoding]::UTF8.GetString($raw))
        if (-not ($tree -is [Collections.IDictionary])) { return $null }
        return @{ raw = $Lat.GetString($raw); base = [int64]8 + $hsize; tree = $tree; path = $path; length = $fs.Length }
    } catch { return $null } finally { $fs.Close() }
}
function Node-Of($hdr, [string]$rel) {
    $n = $hdr.tree
    foreach ($part in $rel.Split('/')) {
        if (-not ($n -is [Collections.IDictionary]) -or -not ($n['files'] -is [Collections.IDictionary]) -or -not $n['files'].ContainsKey($part)) { return $null }
        $n = $n['files'][$part]
    }
    if (-not ($n -is [Collections.IDictionary]) -or $n.ContainsKey('files') -or -not $n.ContainsKey('offset') -or $n['unpacked']) { return $null }
    return $n
}
function Read-File($hdr, $node) {
    $fs = [IO.File]::Open($hdr.path, 'Open', 'Read', 'ReadWrite')
    try {
        $fs.Position = $hdr.base + [int64]$node['offset']; $size = [int]$node['size']; $b = New-Object byte[] $size
        if ($size -gt 0 -and -not (Read-Exact $fs $b $size)) { return $null }
        return $Lat.GetString($b)
    } finally { $fs.Close() }
}
function Is-Patched($hdr) {   # does this archive carry our marker code at the top of main.js?
    $n = Node-Of $hdr "$DIST/main.js"; if (-not $n) { return $false }
    if ([int]$n['size'] -lt $MARK.Length) { return $false }
    $fs = [IO.File]::Open($hdr.path, 'Open', 'Read', 'ReadWrite')
    try { $fs.Position = $hdr.base + [int64]$n['offset']; $b = New-Object byte[] $MARK.Length; [void](Read-Exact $fs $b $MARK.Length); return ($Lat.GetString($b) -ceq $MARK) } finally { $fs.Close() }
}
function Pkg-Version($hdr) {
    $n = Node-Of $hdr 'package.json'; if (-not $n) { return '' }
    try { return [string]($Ser.DeserializeObject([Text.Encoding]::UTF8.GetString($Lat.GetBytes((Read-File $hdr $n)))))['version'] } catch { return '' }
}

# ---------------------------------------------------------------- patch data
$script:EditsCache = $null
function Load-Edits {
    if ($script:EditsCache) { return $script:EditsCache }
    $by = @{}
    $path = Join-Path $Patch 'edits.dat'
    if (-not (Test-Path -LiteralPath $path)) { Fail 1 "Cannot read $path" }
    $first = $true; $cur = $null
    foreach ($line in [IO.File]::ReadLines($path)) {
        if ($first) { if ($line -notmatch "^V1`t") { Fail 1 'Unrecognised patch data file' }; $first = $false; continue }
        if (-not $line) { continue }
        $f = $line.Split("`t")
        if ($f[0] -eq 'F') {
            $cur = @{ osha = $f[4]; nsize = [int]$f[5]; nsha = $f[6]; edits = New-Object Collections.ArrayList }
            if (-not $by.ContainsKey($f[1])) { $by[$f[1]] = @{} }
            $by[$f[1]][$f[4]] = $cur
        } elseif ($f[0] -eq 'E') { [void]$cur.edits.Add(@([int]$f[1], [int]$f[2], $(if ($f.Length -gt 3) { $f[3] } else { '' }))) }
    }
    $script:EditsCache = $by; return $by
}

# ---------------------------------------------------------------- per-file patching
# The startup script baked into an edit list may be older than patch\main_prefix.js: always install the current one.
function Prefix-Text { $p = Slurp (Join-Path $Patch 'main_prefix.js'); return $p.TrimEnd("`r", "`n") }
function Refresh-Prefix([string]$c) {
    if (-not $c.StartsWith($MARK, [StringComparison]::Ordinal)) { return $c }
    $end = $c.IndexOf("`nmodule.exports=", [StringComparison]::Ordinal)
    if ($end -lt 0 -or $end -gt 50000) { return $c }
    return (Prefix-Text) + $c.Substring($end)
}
function Apply-Exact([string]$o, $e) {
    $sb = New-Object Text.StringBuilder ($o.Length + 65536); $pos = 0
    foreach ($ed in $e.edits) { [void]$sb.Append($o, $pos, $ed[0] - $pos); [void]$sb.Append($Lat.GetString([Convert]::FromBase64String($ed[2]))); $pos = $ed[0] + $ed[1] }
    [void]$sb.Append($o, $pos, $o.Length - $pos)
    $n = $sb.ToString()
    if ($n.Length -eq $e.nsize -and (Sha-Str $n) -eq $e.nsha) { return $n }
    return $null
}
$W = '[A-Za-z0-9_$]+'
function Sub([ref]$c, [string]$pat, [string]$rep) {   # global regex replace; returns the number of replacements
    $rx = New-Object Text.RegularExpressions.Regex($pat)
    $n = $rx.Matches($c.Value).Count
    if ($n) { $c.Value = $rx.Replace($c.Value, $rep) }
    return $n
}
# Pattern-based unlock for versions the edit list was not built from. Returns @(new content, rules applied, core ok).
function Apply-Basic([string]$name, [string]$c) {
    $n = 0; $core = $false
    if ($RENDER -contains $name) {
        $a = Sub ([ref]$c) "(function $W\(\)\{if\(!$W\)return`")zh_CN(`";const)" '${1}en_US${2}'
        $b = Sub ([ref]$c) "(=$W\?$W\(\):`")zh_CN(`",$W=new $W\.default\(\{locale:$W,fallbackLocale:)$W\?`"en_US`":`"zh_CN`"" '${1}en_US${2}"en_US"'
        $core = ($a -and $b); $n += $a + $b
        $n += Sub ([ref]$c) "lang:null!==\(($W)=$W\.default\.getItem\(`"currentLanguage`"\)\)&&void 0!==\1\?\1:`"zh_CN`"" 'lang:"en_US"'
        if ($name -eq 'renderer.js') { $n += Sub ([ref]$c) '&lang=\$\{this\.lang\}' '&lang=en_US' }
    }
    if ($name -eq 'main.js' -or $RENDER -contains $name) {
        $n += Sub ([ref]$c) "init\(\)\{(const $W=!($W)\.default\.getItem\(`"useLogin`"\),$W=!$W\.default\.getItem\(`"currentLanguage`"\);)" 'init(){if(1){this._currentLanguage="en_US";this._isRtl=!1;try{"en_US"!==${2}.default.getItem("currentLanguage")&&(${2}.default.setItem("currentLanguage","en_US"),${2}.default.setItem("vLang","vus"),${2}.default.setItem("isRtl",!1))}catch(e){}return}${1}'
    }
    if ($name -eq 'main.js') {
        $n += Sub ([ref]$c) "`"undefined`"!=typeof __buildConfig__&&__buildConfig__\.IS_EXPORT\?($W\.getLocalesJson\(`"framework`"\)):(?:\{\}|null)" '${1}'
        $n += Sub ([ref]$c) "(getLocalesJson=$W=>\{const $W=)$W\.default\.getItem\(`"currentLanguage`"\)\|\|`"en_US`"" '${1}"en_US"'
        if (-not $c.StartsWith($MARK, [StringComparison]::Ordinal) -and $c -match '\A\s*(?:module\.exports|\(function|!function|"use strict")') { $c = (Prefix-Text) + "`n" + $c; $n++; $core = $true }
    }
    if ($name -eq 'locales-en_US.js') {
        $anch = @{}; $keys = @{}
        $lf = Join-Path $Patch 'locale_extra.tsv'
        if (-not (Test-Path -LiteralPath $lf)) { return @($c, 0, $false) }
        foreach ($l in [IO.File]::ReadLines($lf)) {
            $f = $l.Split("`t")
            if ($f[0] -eq 'M') { $anch[$f[1]] = $f[2].Split(',') }
            elseif ($f[0] -eq 'K') { if (-not $keys.ContainsKey($f[1])) { $keys[$f[1]] = New-Object Collections.ArrayList }; [void]$keys[$f[1]].Add(@($f[2], $Lat.GetString([Convert]::FromBase64String($f[3])))) }
        }
        $lits = @(); foreach ($m in [regex]::Matches($c, "JSON\.parse\('([^'\\]*(?:\\.[^'\\]*)*)'\)", 'Singleline')) { $g = $m.Groups[1]; $lits += , @($g.Index, ($g.Index + $g.Length)) }
        $ins = New-Object Collections.ArrayList
        foreach ($mod in $keys.Keys) {
            $best = $null; $score = 1
            foreach ($lit in $lits) {
                $txt = $c.Substring($lit[0], $lit[1] - $lit[0]); $s = 0
                foreach ($a in @($anch[$mod])) { if ($a -and $txt.IndexOf("`"$($a)`":", [StringComparison]::Ordinal) -ge 0) { $s++ } }
                if ($s -gt $score) { $best = $lit; $score = $s }
            }
            if (-not $best) { continue }
            $txt = $c.Substring($best[0], $best[1] - $best[0])
            if (-not $txt.EndsWith('}') -or $txt.Length -le 2) { continue }
            $add = -join ($keys[$mod] | Where-Object { $txt.IndexOf("`"$($_[0])`":", [StringComparison]::Ordinal) -lt 0 } | ForEach-Object { ',' + $_[1] })
            if ($add) { [void]$ins.Add(@(($best[1] - 1), $add)) }
        }
        foreach ($i in ($ins | Sort-Object { $_[0] } -Descending)) { $c = $c.Insert($i[0], $i[1]); $n++ }
    }
    return @($c, $n, $core)
}

# Decide, for one source archive, what would be changed. Returns @{ mode; detail; files = @(@(rel, node, newdata)) }.
function Plan($hdr) {
    $edits = Load-Edits
    $targets = @{}; foreach ($k in $edits.Keys) { $targets[$k] = 1 }
    foreach ($x in ($RENDER + 'main.js', 'locales-en_US.js')) { $targets["$DIST/$x"] = 1 }
    $out = New-Object Collections.ArrayList; $full = 0; $basic = 0; $rules = 0; $coreR = $false; $coreM = $false
    foreach ($rel in ($targets.Keys | Sort-Object)) {
        $node = Node-Of $hdr $rel; if (-not $node) { continue }
        $o = Read-File $hdr $node; if ($null -eq $o) { continue }
        $name = $rel.Split('/')[-1]
        $e = $null; if ($edits.ContainsKey($rel)) { $e = $edits[$rel][(Sha-Str $o)] }   # edit list for this exact file version, if we have one
        $n = $null
        if ($e -and -not $env:VOK_FORCE_BASIC) { $n = Apply-Exact $o $e; if ($null -ne $n -and $name -eq 'main.js') { $n = Refresh-Prefix $n } }
        if ($null -ne $n) { $full++; if ($name -eq 'renderer.js') { $coreR = $true }; if ($name -eq 'main.js') { $coreM = $true } }
        else {
            $r = Apply-Basic $name $o
            if (-not $r[1]) { continue }
            $n = $r[0]; $basic++; $rules += $r[1]
            if ($name -eq 'renderer.js' -and $r[2]) { $coreR = $true }; if ($name -eq 'main.js' -and $r[2]) { $coreM = $true }
        }
        [void]$out.Add(@($rel, $node, $n))
    }
    $mode = if (-not $coreR) { 'none' } elseif ($basic) { 'basic' } else { 'full' }
    $detail = switch ($mode) { 'none' { 'the language lock was not found in this version' } 'full' { "$full files fully patched" } default { "$full files fully patched, $basic by pattern ($rules changes)" } }
    return @{ mode = $mode; detail = $detail; files = $out; main_ok = $coreM }
}

# ---------------------------------------------------------------- work out where we stand
$cur = Read-Header $asar
if (-not $cur) { Fail 3 "app.asar could not be read as an Electron archive. Nothing was changed." }
$curPatched = Is-Patched $cur
$bak = if (Test-Path -LiteralPath $backup) { Read-Header $backup } else { $null }
if ($bak -and (Is-Patched $bak)) { $bak = $null }
$source = if ($curPatched) { $bak } else { $cur }      # the pristine archive to build from ($null if we have none)
$foreign = $false
$plan = $null
if ($source) { $plan = Plan $source }
# The current archive was changed by some other tool (its language lock is gone, but it is not this patch):
# build from vivo's own untouched copy instead, if it is there and is the same version.
if (-not $curPatched -and $plan -and $plan.mode -eq 'none' -and (Test-Path -LiteralPath $vivoOriginal)) {
    $orig = Read-Header $vivoOriginal
    if ($orig -and -not (Is-Patched $orig) -and (Pkg-Version $orig) -eq (Pkg-Version $cur)) {
        $p2 = Plan $orig
        if ($p2.mode -ne 'none') { $source = $orig; $plan = $p2; $foreign = $true }
    }
}

if ($Command -eq 'status') {
    $p = if ($plan) { $plan } else { @{ mode = 'none'; detail = 'patched, but the original backup is missing' } }
    $state = if ($curPatched) { 'patched' } elseif ($p.mode -eq 'none') { 'unsupported' } else { 'original' }
    $detail = $p.detail; if ($foreign) { $detail += '; app.asar was changed by another tool, so vivo''s app.asar.original is used' }
    Write-Output "$state`n$App`n$($p.mode)`n$detail"; exit 0
}

if ($Command -eq 'restore') {
    if (-not $curPatched) { Fail 1 "The English patch is not installed, so there is nothing to restore." }
    if (-not $bak) { Fail 1 "The backup of the original archive is missing. Reinstall vivo Office Kit from vivo's installer to restore it." }
    try { [IO.File]::Replace($backup, $asar, [NullString]::Value) } catch { Fail (Err-Code $_) "Could not restore: $($_.Exception.Message)" }
    Remove-Item -LiteralPath $marker -Force -ErrorAction SilentlyContinue
    Write-Output "Restored the original Chinese version."; exit 0
}
if ($Command -ne 'install') { Fail 1 "Unknown command '$Command'" }
if (-not $source) { Fail 3 "The English patch is installed but its backup of the original is missing, so it cannot be rebuilt. Reinstall vivo Office Kit, then run this again." }
if ($plan.mode -eq 'none') { Fail 3 "This version of vivo Office Kit is too different for the patch (the language lock was not found). Nothing was changed." }

# ---------------------------------------------------------------- build the new archive index
$raw = $source.raw
[int64]$cursor = $source.length - $source.base
$surgery = -not $env:VOK_FORCE_REENCODE
$repl = New-Object Collections.ArrayList
foreach ($f in $plan.files) {
    $rel = $f[0]; $node = $f[1]; $n = $f[2]; $nb = $Lat.GetBytes($n)
    $blocks = New-Object Collections.ArrayList
    for ($i = 0; $i -lt $nb.Length; $i += $BLOCK) { [void]$blocks.Add((-join ($Sha.ComputeHash($nb, $i, [Math]::Min($BLOCK, $nb.Length - $i)) | ForEach-Object { $_.ToString('x2') }))) }
    if (-not $blocks.Count) { [void]$blocks.Add((Hex (New-Object byte[] 0))) }
    $hash = Hex $nb
    $oldhash = ''; if ($node['integrity'] -is [Collections.IDictionary] -and $node['integrity']['hash']) { $oldhash = [string]$node['integrity']['hash'] }
    $oldsize = $node['size']; $oldoff = [string]$node['offset']
    $node['size'] = $nb.Length; $node['offset'] = "$cursor"
    $node['integrity'] = @{ algorithm = 'SHA256'; hash = $hash; blockSize = $BLOCK; blocks = [object[]]$blocks }
    $entry = '{"size":' + $nb.Length + ',"integrity":{"algorithm":"SHA256","hash":"' + $hash + '","blockSize":' + $BLOCK + ',"blocks":[' + (($blocks | ForEach-Object { "`"$_`"" }) -join ',') + ']},"offset":"' + $cursor + '"}'
    $cursor += $nb.Length
    if (-not $surgery) { continue }
    # Keep the index byte-for-byte as vivo wrote it except for this entry, when the entry can be located unambiguously.
    $needle = "`"hash`":`"$oldhash`""; $at = if ($oldhash.Length -eq 64) { $raw.IndexOf($needle, [StringComparison]::Ordinal) } else { -1 }
    if ($at -lt 0 -or $raw.IndexOf($needle, $at + 1, [StringComparison]::Ordinal) -ge 0) { $surgery = $false; continue }
    $start = $raw.LastIndexOf('{"size":', $at, [StringComparison]::Ordinal); $tail = "`"offset`":`"$oldoff`"}"; $end = $raw.IndexOf($tail, $at, [StringComparison]::Ordinal)
    if ($start -lt 0 -or $end -lt 0 -or $end - $start -gt 200000 -or -not $raw.Substring($start, [Math]::Min(60, $raw.Length - $start)).StartsWith("{`"size`":$oldsize,`"integrity`":{", [StringComparison]::Ordinal)) { $surgery = $false; continue }
    [void]$repl.Add(@($start, ($end + $tail.Length - $start), $entry))
}
if ($surgery) {
    $sb = New-Object Text.StringBuilder $raw
    foreach ($r in ($repl | Sort-Object { $_[0] } -Descending)) { [void]$sb.Remove($r[0], $r[1]); [void]$sb.Insert($r[0], $r[2]) }
    $raw = $sb.ToString()
} else { $raw = $Lat.GetString([Text.Encoding]::UTF8.GetBytes($Ser.Serialize($source.tree))) }
try { $check = $Ser.DeserializeObject([Text.Encoding]::UTF8.GetString($Lat.GetBytes($raw))) } catch { $check = $null }
if (-not ($check -is [Collections.IDictionary])) { Fail 1 "Internal check failed for the archive index. Nothing was changed." }

# ---------------------------------------------------------------- write next to the old one, verify, then swap
$tmp = "$asar.tmp-english"
$rawB = $Lat.GetBytes($raw)
$pad = (4 - $rawB.Length % 4) % 4
$hbufLen = 8 + $rawB.Length + $pad
try {
    $out = [IO.File]::Open($tmp, 'Create', 'Write', 'None')
} catch { Fail (Err-Code $_) "Cannot write to ${res}: $($_.Exception.Message)" }
try {
    $bw = New-Object IO.BinaryWriter($out)
    $bw.Write([uint32]4); $bw.Write([uint32]$hbufLen); $bw.Write([uint32](4 + $rawB.Length + $pad)); $bw.Write([uint32]$rawB.Length)
    $bw.Write($rawB); if ($pad) { $bw.Write((New-Object byte[] $pad)) }
    $bw.Flush()
    $in = [IO.File]::Open($source.path, 'Open', 'Read', 'ReadWrite')
    try { $in.Position = $source.base; $in.CopyTo($out, 16MB) } finally { $in.Close() }
    foreach ($f in $plan.files) { $b = $Lat.GetBytes($f[2]); $out.Write($b, 0, $b.Length) }
    $out.Flush(); $out.Close()
} catch { try { $out.Close() } catch {}; Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue; Fail 1 "Write failed: $($_.Exception.Message)" }

$new = Read-Header $tmp
$ok = [bool]$new
if ($ok) { foreach ($f in $plan.files) { $nn = Node-Of $new $f[0]; $d = if ($nn) { Read-File $new $nn } else { $null }; if ($null -eq $d -or -not ($d -ceq $f[2])) { $ok = $false; break } } }
if ($ok) { $pk = Node-Of $new 'package.json'; try { if (-not ($Ser.DeserializeObject([Text.Encoding]::UTF8.GetString($Lat.GetBytes((Read-File $new $pk)))) -is [Collections.IDictionary])) { $ok = $false } } catch { $ok = $false } }
if (-not $ok) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue; Fail 1 "The rebuilt archive failed verification. Nothing was changed." }

try {
    if ($foreign) {
        # Keep the other tool's archive aside, and a copy of vivo's untouched one as our backup.
        if (Test-Path -LiteralPath $aside) { Remove-Item -LiteralPath $aside -Force }
        [IO.File]::Move($asar, $aside)
        [IO.File]::Copy($vivoOriginal, $backup, $true)
        [IO.File]::Move($tmp, $asar)
    } elseif (-not $curPatched) {
        if (Test-Path -LiteralPath $backup) { Remove-Item -LiteralPath $backup -Force }   # a stale, already-patched backup
        [IO.File]::Move($asar, $backup)
        try { [IO.File]::Move($tmp, $asar) } catch { [IO.File]::Move($backup, $asar); throw }
    } else {
        [IO.File]::Replace($tmp, $asar, [NullString]::Value)
    }
} catch {
    $code = Err-Code $_
    if ($foreign -and -not (Test-Path -LiteralPath $asar) -and (Test-Path -LiteralPath $aside)) { try { [IO.File]::Move($aside, $asar) } catch {} }
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    if ($code -eq 5) { Fail 5 "vivo Office Kit is still running, so its files are in use. Quit it (including its tray icon) and try again." }
    Fail $code "Could not install the patched archive: $($_.Exception.Message)"
}
try { [IO.File]::WriteAllText($marker, "patch=$PATCH_VERSION`nmode=$($plan.mode)`ndetail=$($plan.detail)`nplatform=windows`n", (New-Object Text.UTF8Encoding($false))) } catch {}

$note = if ($foreign) { ' Another tool had already changed app.asar; that version was kept as app.asar.pre-english-patch and vivo''s untouched copy was used.' } else { '' }
if ($plan.mode -eq 'full') { Write-Output "English patch installed ($($plan.detail)). The original is kept as a backup.$note" }
else { Write-Output "English patch installed in basic mode ($($plan.detail)). This version differs from the one the patch was built for, so some screens may stay in Chinese. The original is kept as a backup.$note" }
exit 0
