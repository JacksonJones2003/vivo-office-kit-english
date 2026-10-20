# Background helper for the vivo Office Kit English patch (Windows). Kept in %LOCALAPPDATA%\vivo-office-kit-english-watcher.
#   watcher.ps1 monitor   stay running (started at sign-in by the "vivo English Watcher" scheduled task). Every 10 seconds
#                         it looks at vivo Office Kit's app.asar (vivo updates replace it), whether vivo Office Kit was
#                         just opened, and requests from the patched app; every 6 hours it checks for a newer translation.
#   watcher.ps1 run       one normal run: if vivo's updater has put the original Chinese archive back, re-applies the
#                         English patch; offers newer translations from GitHub.
# Test hooks: VOK_APP=<install folder>  VOK_AUTO=1 (no dialogs)  VOK_MANIFEST_URL=... (update source)  VOK_REPO_URL=... (with VOK_AUTO)
#             VOK_CHOICE="<button>`t<0|1>" (answer for the reminder popup in test mode)  -Trigger launch
param([Parameter(Position = 0)][string]$Mode = 'run', [string]$Trigger = '')
$ErrorActionPreference = 'Continue'
$W = Split-Path -Parent $MyInvocation.MyCommand.Path
$SELF = $MyInvocation.MyCommand.Path
$KIT = Join-Path $W 'kit'
$PATCHER = Join-Path $KIT 'patcher.ps1'
. (Join-Path $W 'ui.ps1')
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}
$LOG = Join-Path $W 'vivo-office-kit-english.log'
function Log([string]$m) {
    try {
        if ((Test-Path -LiteralPath $LOG) -and (Get-Item -LiteralPath $LOG).Length -gt 1MB) { Move-Item -LiteralPath $LOG -Destination "$LOG.old" -Force }
        Add-Content -LiteralPath $LOG -Value ('{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m) -Encoding UTF8
    } catch {}
    if ($env:VOK_AUTO) { Write-Output $m }
}
$ON = Join-Path $W 'watcher-on'
$NOREMIND = Join-Path $W 'no-reminders'; $SNOOZE = Join-Path $W 'snoozed-copy'
$STAMPF = Join-Path $W 'last-update-check'; $DECLINED = Join-Path $W 'declined-version'
$REQ = Join-Path $W 'launch-request'      # written by the patched app when it starts
$MANUAL = Join-Path $W 'manual-request'   # written by the patched app's "Check for updates" button
$PENDING = Join-Path $W 'pending-reapply' # vivo was updated while running; reapply once it is closed
$REPO_URL = if ($env:VOK_AUTO -and $env:VOK_REPO_URL) { $env:VOK_REPO_URL } else { 'https://github.com/JacksonJones2003/vivo-office-kit-english' }
$MANIFEST_URL = if ($env:VOK_MANIFEST_URL) { $env:VOK_MANIFEST_URL } else { 'https://raw.githubusercontent.com/JacksonJones2003/vivo-office-kit-english/main/windows/latest.json' }

# ask_check "message" "main button" "other button" -> @{ button; checked } ("Don't remind me again")
function Ask-Check([string]$Message, [string]$Main, [string]$Other) {
    if ($env:VOK_AUTO) { $c = if ($env:VOK_CHOICE) { $env:VOK_CHOICE } else { "$Main`t0" }; $p = $c.Split("`t"); return @{ button = $p[0]; checked = ($p[1] -eq '1') } }
    return Show-Ask $Message $Main @($Other, $Main) -Check "Don't remind me again" -TimeoutSec 600
}
function Asar-Stamp([string]$App) { try { $i = Get-Item -LiteralPath (Join-Path $App 'resources\app.asar') -ErrorAction Stop; return "$($i.LastWriteTimeUtc.Ticks) $($i.Length)" } catch { return '' } }
function Resolve-App {
    if ($env:VOK_APP) { if (Test-Path -LiteralPath (Join-Path $env:VOK_APP 'resources\app.asar')) { return $env:VOK_APP } else { return $null } }
    $r = Invoke-Script $PATCHER @('status')
    if ($r.rc -eq 0) { return ($r.out -split "`r?`n")[1] }
    return $null
}
function Marker-Value([string]$App, [string]$Key) {
    try { foreach ($l in Get-Content -LiteralPath (Join-Path $App 'resources\app.asar.english-patch') -ErrorAction Stop) { if ($l -match "^$Key=(.*)$") { return $Matches[1].Trim() } } } catch {}
    return ''
}
function Is-Newer([string]$a, [string]$b) {
    $x = $a.Split('.'); $y = $b.Split('.')
    for ($i = 0; $i -lt 3; $i++) { $d = [int]($x[$i] -as [int]) - [int]($y[$i] -as [int]); if ($d) { return ($d -gt 0) } }
    return $false
}
function Kit-Version { $r = Invoke-Script $PATCHER @('version'); if ($r.rc -eq 0) { return $r.out.Trim() } else { return '' } }
function Now-Unix { [int64]([DateTimeOffset]::UtcNow.ToUnixTimeSeconds()) }
function Read-Json($content) { if ($content -is [byte[]]) { $content = [Text.Encoding]::UTF8.GetString($content) }; return ($content | ConvertFrom-Json) }

# Runs the patcher. If this helper may not write to vivo's folder (it was set up without administrator rights), shows
# the reminder popup and asks Windows for permission instead of failing. Sets $script:OUT, $script:RC, $script:SKIPPED.
# Reminders: the popup appears every time vivo Office Kit is opened while it is not in English. "Not Now" (or a popup
# that was missed) only skips this time; background checks then stay quiet for that copy. Ticking "Don't remind me
# again" stops the popups until the installer is run again.
function Do-Install([string]$App) {
    $r = Invoke-Script $PATCHER @('install', '-App', $App); $script:OUT = $r.out; $script:RC = $r.rc
    if ($script:RC -ne 4) { return }
    $stamp = Asar-Stamp $App
    if (Test-Path -LiteralPath $NOREMIND) { $script:RC = 0; $script:OUT = 'skipped (reminders turned off with "Don''t remind me again")'; $script:SKIPPED = $true; return }
    if ($script:Trigger -ne 'launch' -and (Test-Path -LiteralPath $SNOOZE) -and ((Get-Content -LiteralPath $SNOOZE -Raw).Trim() -eq $stamp)) { $script:RC = 0; $script:OUT = 'skipped (Not Now; will ask again when vivo Office Kit is opened)'; $script:SKIPPED = $true; return }
    Log 'showing the reminder popup (no permission to change vivo Office Kit, and it is not in English)'
    $a = Ask-Check "vivo Office Kit is not in English. It was installed, reinstalled or updated, and this helper is not allowed to change it on its own.`n`nApply the English patch now? Windows will ask for permission." 'Apply English' 'Not Now'
    if ($a.checked) { Set-Content -LiteralPath $NOREMIND -Value '' ; Log 'reminders turned off (Don''t remind me again)' }
    if ($a.button -ne 'Apply English') { Set-Content -LiteralPath $SNOOZE -Value $stamp; $script:RC = 0; $script:OUT = 'skipped (Not Now)'; $script:SKIPPED = $true; return }
    if ($env:VOK_AUTO) { return }
    Log 'asking Windows for administrator permission'
    $r = Invoke-ScriptElevated $PATCHER @('install', '-App', $App); $script:OUT = $r.out; $script:RC = $r.rc
    if ($script:RC -eq -128) { $script:RC = 0; $script:OUT = 'skipped (permission prompt cancelled)'; $script:SKIPPED = $true }
    if ($script:RC -eq 0) { Remove-Item -LiteralPath $SNOOZE -Force -ErrorAction SilentlyContinue }
}
# The archive is in use: vivo Office Kit is running (vivo's updater usually restarts it). Offer to restart it in English,
# or reapply as soon as it is closed.
function Handle-InUse([string]$App, [string]$Ver, [string]$What) {
    $c = Ask "$What`n`nTo switch vivo Office Kit to English, it needs to restart. Restart it now?" 'Restart in English' @('Later', 'Restart in English') -TimeoutSec 600
    if ($c -ne 'Restart in English') { Set-Content -LiteralPath $PENDING -Value (Asar-Stamp $App); Log 'app in use; will reapply when vivo Office Kit is closed'; $script:SKIPPED = $true; return }
    [void](Stop-Vivo $App)
    Do-Install $App
    Remove-Item -LiteralPath $PENDING -Force -ErrorAction SilentlyContinue
    Start-Vivo $App
    $script:RESTARTED = $true
}

# ---------------------------------------------------------------- new translations from GitHub
# Looks for a newer release of this patch and, only if you click Install, downloads and switches to it.
function Maybe-Update([bool]$Force, [string]$Ver) {
    $now = Now-Unix
    # Check at most every 12 hours, or every hour when you open vivo Office Kit, unless vivo just changed
    # or this version is not fully supported.
    $limit = 43200; if (Test-Path -LiteralPath $REQ) { $limit = 3600; Remove-Item -LiteralPath $REQ -Force -ErrorAction SilentlyContinue }; if ($script:Trigger -eq 'launch') { $limit = 3600 }
    $last = 0; try { $last = [int64](Get-Content -LiteralPath $STAMPF -Raw -ErrorAction Stop).Trim() } catch {}
    if (-not $Force -and $last -and ($now - $last) -lt $limit) { return }
    Set-Content -LiteralPath $STAMPF -Value $now
    try { $m = Read-Json (Invoke-WebRequest -Uri $MANIFEST_URL -UseBasicParsing -TimeoutSec 20 -Headers @{ 'Cache-Control' = 'no-cache' }).Content } catch { Log 'update check: could not reach GitHub'; return }
    $nv = [string]$m.version; $url = [string]$m.zip_url; $sha = [string]$m.zip_sha256; $sup = (@($m.full_versions) | Where-Object { $_ }) -join ', '
    if ($nv -notmatch '^\d+(\.\d+){0,3}$') { Log 'update check: unreadable manifest'; return }
    $cv = Kit-Version
    if (-not (Is-Newer $nv $cv)) { Log "update check: patch $cv is current"; return }
    if (-not $url.StartsWith("$REPO_URL/releases/download/windows-v")) { Log 'update check: refusing unexpected download address'; return }
    if ($sha.Length -ne 64) { Log 'update check: manifest has no checksum'; return }
    # Do not nag: after "Not Now", ask again only after 3 days or when vivo's version changes.
    if (-not $Force -and (Test-Path -LiteralPath $DECLINED)) { $d = @(Get-Content -LiteralPath $DECLINED); if ($d.Count -ge 2 -and $d[0] -eq $nv -and ($now - [int64]$d[1]) -lt 259200) { return } }
    $extra = ''; if ($sup) { $extra = "`n`nIt has the full translation for vivo Office Kit $sup." }
    if ($Ver -and ((", $sup, ") -like "*, $Ver, *")) { $extra += " Your version, $Ver, is included." }
    $c = Ask "A new English translation for vivo Office Kit is available (patch $nv; you have $cv).$extra`n`nDownload and install it now? It is downloaded from the project's GitHub page and checked before use." 'Install' @('Not Now', 'Install') -TimeoutSec 600
    if ($c -ne 'Install') { Set-Content -LiteralPath $DECLINED -Value @($nv, $now); Log "update $nv declined"; return }
    $tmp = Join-Path $env:TEMP ('vok-update-' + [guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    try {
        $zip = Join-Path $tmp 'p.zip'
        try { Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing -TimeoutSec 300 } catch { Log 'update: download failed'; Notify 'Downloading the new English translation failed. It will be offered again later.'; return }
        if ((Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash -ne $sha.ToUpperInvariant()) { Log 'update: checksum mismatch'; Notify 'The downloaded translation did not pass its check and was not used.'; return }
        $x = Join-Path $tmp 'x'; Expand-Archive -LiteralPath $zip -DestinationPath $x -Force
        $d = if (Test-Path -LiteralPath (Join-Path $x 'patcher.ps1')) { $x } else { (Get-ChildItem -LiteralPath $x -Directory | Select-Object -First 1).FullName }
        $okPkg = $d -and (Test-Path -LiteralPath (Join-Path $d 'patcher.ps1')) -and (Test-Path -LiteralPath (Join-Path $d 'patch\edits.dat'))
        if ($okPkg) { foreach ($s in @('patcher.ps1', 'watcher\watcher.ps1', 'watcher\ui.ps1')) { $f = Join-Path $d $s; if (Test-Path -LiteralPath $f) { $errs = $null; [void][Management.Automation.Language.Parser]::ParseFile($f, [ref]$null, [ref]$errs); if ($errs.Count) { $okPkg = $false } } } }
        if (-not $okPkg) { Log 'update: package incomplete'; return }
        Get-ChildItem -LiteralPath $d -Recurse -File | Unblock-File -ErrorAction SilentlyContinue
        $new = Join-Path $W 'kit.new'; if (Test-Path -LiteralPath $new) { Remove-Item -LiteralPath $new -Recurse -Force }
        New-Item -ItemType Directory -Force -Path $new | Out-Null
        Copy-Item -LiteralPath (Join-Path $d 'patcher.ps1') -Destination $new; Copy-Item -LiteralPath (Join-Path $d 'patch') -Destination $new -Recurse
        Remove-Item -LiteralPath $KIT -Recurse -Force; Rename-Item -LiteralPath $new -NewName 'kit'
        # A newer helper replaces this one; the running monitor notices and restarts itself.
        foreach ($s in 'ui.ps1', 'watcher.ps1') { $f = Join-Path $d "watcher\$s"; if (Test-Path -LiteralPath $f) { Copy-Item -LiteralPath $f -Destination (Join-Path $W "$s.new") -Force; Move-Item -LiteralPath (Join-Path $W "$s.new") -Destination (Join-Path $W $s) -Force } }
        Remove-Item -LiteralPath $DECLINED -Force -ErrorAction SilentlyContinue
        Log "updated the patch to $nv"
        $script:UPDATED = $nv
    } finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}

# ---------------------------------------------------------------- one normal run
function Run-Once([string]$Why) {
    $script:Trigger = $Why; $script:SKIPPED = $false; $script:UPDATED = ''; $script:RESTARTED = $false; $script:OUT = ''; $script:RC = 0
    $APP = Resolve-App
    if (-not $APP) { Log 'vivo Office Kit not installed; nothing to do'; return }
    # vivo's updater may still be writing: wait until the archive has stopped changing (up to 2 minutes).
    $prev = ''
    for ($i = 0; $i -lt 24; $i++) { $cur = Asar-Stamp $APP; if ($cur -and $cur -eq $prev) { break }; $prev = $cur; Start-Sleep -Seconds 5 }
    $VER = Get-VivoVersion $APP

    $s = Invoke-Script $PATCHER @('status', '-App', $APP); $sl = $s.out -split "`r?`n"
    if ($s.rc -ne 0) { Log "version ${VER}: could not check vivo Office Kit (rc=$($s.rc)): $($s.out)"; return }
    $STATE = $sl[0]; $MODE = $sl[2]
    $INST_MODE = Marker-Value $APP 'mode'   # mode the app is actually patched in
    $FORCE = ($STATE -eq 'original') -or ($MODE -ne 'full') -or ($INST_MODE -eq 'basic')
    # "Check for updates" clicked in the app: check now, even if this release was postponed with Not Now.
    if (Test-Path -LiteralPath $MANUAL) { Remove-Item -LiteralPath $MANUAL -Force -ErrorAction SilentlyContinue; $FORCE = $true; Log 'update check requested from the app' }
    Maybe-Update $FORCE $VER
    # Patched in basic mode earlier, but full English is now possible (new translation just downloaded, or already here): upgrade.
    if (-not $script:UPDATED -and $STATE -eq 'patched' -and $INST_MODE -eq 'basic' -and $MODE -eq 'full') { $script:UPDATED = Kit-Version; Log 'app was in basic mode; full translation available, upgrading' }
    # The helper already has a newer patch than the one installed in the app: bring the app up to the helper's version.
    $INST_PATCH = Marker-Value $APP 'patch'; $KIT_PATCH = Kit-Version
    if (-not $script:UPDATED -and $STATE -eq 'patched' -and $INST_PATCH -and $KIT_PATCH -and (Is-Newer $KIT_PATCH $INST_PATCH)) { $script:UPDATED = $KIT_PATCH; Log "app has patch $INST_PATCH, helper has ${KIT_PATCH}: updating the app" }

    if ($script:UPDATED) {
        if ($STATE -eq 'patched') {
            # Already English: rebuild it with the new translation (the patcher rebuilds from its backup of the original).
            Do-Install $APP; Log "reinstall with $($script:UPDATED) rc=$($script:RC): $($script:OUT)"
            if ($script:RC -eq 5) { Handle-InUse $APP $VER "The new English translation ($($script:UPDATED)) is ready." ; if ($script:SKIPPED) { return } }
            if ($script:SKIPPED) { return }
            if ($script:RC -ne 0) { Notify "Installing the new English translation failed: $($script:OUT)"; return }
            if ($script:RESTARTED) { Notify "The new English translation ($($script:UPDATED)) has been installed."; return }
            $STATE = 'reinstalled'
        } else {
            $s = Invoke-Script $PATCHER @('status', '-App', $APP); $sl = $s.out -split "`r?`n"; $STATE = $sl[0]; $MODE = $sl[2]
        }
    }
    if ($STATE -eq 'reinstalled') {
        if ((Get-VivoProcesses $APP).Count) {
            $c = Ask "The new English translation ($($script:UPDATED)) has been installed.`n`nRestart vivo Office Kit now to use it?" 'Restart Now' @('Later', 'Restart Now') -TimeoutSec 600
            if ($c -eq 'Restart Now') { [void](Stop-Vivo $APP); Start-Vivo $APP }
        } else { Notify "The new English translation ($($script:UPDATED)) has been installed." }
        return
    }
    if ($STATE -ne 'original') { Log "version ${VER}: state=$STATE, nothing to do"; Remove-Item -LiteralPath $PENDING -Force -ErrorAction SilentlyContinue; return }
    if ($MODE -eq 'none') {
        Log "version ${VER}: the patch does not support this version"
        Notify "vivo Office Kit $VER can't be patched by this version of the English patch. Run the installer again to check for an update."
        return
    }

    $running = [bool](Get-VivoProcesses $APP).Count
    Do-Install $APP
    Log "version ${VER}: install rc=$($script:RC): $($script:OUT)"
    if ($script:RC -eq 5) {
        if ($script:Trigger -eq 'pending') { return }
        Handle-InUse $APP $VER "vivo Office Kit was updated to $VER, which put it back into Chinese."
        if ($script:SKIPPED) { return }
        Log "after restart: rc=$($script:RC): $($script:OUT)"
    }
    if ($script:SKIPPED) { return }
    if ($script:RC -ne 0) { Notify "Reapplying the English patch failed: $($script:OUT)"; return }
    Remove-Item -LiteralPath $PENDING -Force -ErrorAction SilentlyContinue
    $EXTRA = ''
    if ($MODE -eq 'basic') { $EXTRA = "`n`nThis version ($VER) is newer than the patch's full translation, so basic mode was used and some screens may be in Chinese. Run the installer again later to check for full support." }
    if ($script:RESTARTED) { Notify "vivo Office Kit $VER is back in English."; return }
    if ($running -and (Get-VivoProcesses $APP).Count) {
        $c = Ask "vivo Office Kit was updated to $VER and the English patch has been reapplied.$EXTRA`n`nRestart vivo Office Kit now to see English?" 'Restart Now' @('Later', 'Restart Now') -TimeoutSec 600
        if ($c -eq 'Restart Now') { [void](Stop-Vivo $APP); Start-Vivo $APP }
    } else { Notify "vivo Office Kit ${VER}: the English patch has been (re)applied." }
}

# One run at a time, so two triggers can never show two popups.
function Run-Locked([string]$Why) {
    $mx = New-Object Threading.Mutex($false, 'Local\vivo-office-kit-english-run')
    $got = $false
    try { $got = $mx.WaitOne(0) } catch [Threading.AbandonedMutexException] { $got = $true }
    if (-not $got) { return }
    try { Run-Once $Why } catch { Log "run failed: $($_.Exception.Message)" } finally { $mx.ReleaseMutex(); $mx.Dispose() }
}

if ($Mode -eq 'run') { Run-Locked $Trigger; exit 0 }
if ($Mode -ne 'monitor') { [Console]::Error.WriteLine('usage: watcher.ps1 monitor|run'); exit 1 }

# ---------------------------------------------------------------- monitor
$single = New-Object Threading.Mutex($false, 'Local\vivo-office-kit-english-monitor')
try { if (-not $single.WaitOne(0)) { exit 0 } } catch [Threading.AbandonedMutexException] {}
Log 'helper started'
$selfStamp = (Get-Item -LiteralPath $SELF).LastWriteTimeUtc
$app = $null; $appAt = [datetime]::MinValue; $lastStamp = $null; $lastLaunch = ''; $pendingTried = $false; $nextTimer = (Get-Date).AddHours(6)
Run-Locked 'login'
while ($true) {
    if (-not (Test-Path -LiteralPath $ON)) { Log 'automatic re-patching was turned off; helper exiting'; break }
    try {
        if ((Get-Item -LiteralPath $SELF).LastWriteTimeUtc -ne $selfStamp) {
            Log 'helper was updated; restarting it'
            $single.ReleaseMutex(); $single.Dispose()
            Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', ('"' + $SELF + '"'), 'monitor') -WindowStyle Hidden
            exit 0
        }
        $why = $null
        if (-not $app -or ((Get-Date) - $appAt).TotalSeconds -ge 60) {
            $found = Resolve-App; $appAt = Get-Date
            if ($found -and -not $app -and $null -ne $lastStamp) { $why = 'install' }   # a fresh install appeared
            $app = $found
        }
        if ($app) {
            $st = Asar-Stamp $app
            if ($null -ne $lastStamp -and $st -ne $lastStamp) { $why = 'change' }
            $lastStamp = $st
            $lid = Get-VivoLaunchId $app
            if ($lid) { $pendingTried = $false; if ($lid -ne $lastLaunch) { $lastLaunch = $lid; if (-not $why) { $why = 'launch' } } }
            else { $lastLaunch = ''; if (-not $why -and -not $pendingTried -and (Test-Path -LiteralPath $PENDING)) { $why = 'pending'; $pendingTried = $true } }
        } elseif ($null -eq $lastStamp) { $lastStamp = '' }
        if (Test-Path -LiteralPath $MANUAL) { $why = 'manual' } elseif (-not $why -and (Test-Path -LiteralPath $REQ)) { $why = 'request' }
        if ((Get-Date) -ge $nextTimer) { $nextTimer = (Get-Date).AddHours(6); if (-not $why) { $why = 'timer' } }
        if ($why) {
            Run-Locked $why
            if ($app) { $lastStamp = Asar-Stamp $app; $lastLaunch = Get-VivoLaunchId $app }   # our own changes are not a vivo update
        }
    } catch { Log "monitor: $($_.Exception.Message)" }
    Start-Sleep -Seconds 10
}
