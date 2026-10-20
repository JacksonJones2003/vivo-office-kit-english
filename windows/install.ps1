# Point-and-click installer for the vivo Office Kit English patch (Windows).
# Shows dialogs, asks for administrator permission (UAC) because vivo installs into Program Files, and can undo the patch.
# Usage: install.ps1 [-App "C:\Program Files (x86)\pcsuite"]
#   VOK_AUTO=install|restore  run without dialogs (used for testing)
param([string]$App, [string]$ForUser, [string]$UserData)
$ErrorActionPreference = 'Continue'
$DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $DIR 'watcher\ui.ps1')
$PATCHER = Join-Path $DIR 'patcher.ps1'
$WATCH = Join-Path $DIR 'watcher\setup-watcher.ps1'
$AUTO = $env:VOK_AUTO
if (-not $ForUser) { $ForUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name }
if (-not $UserData) { $UserData = $env:LOCALAPPDATA }

# vivo Office Kit lives in Program Files, which only administrators may change: ask for permission once, up front.
if (-not (Test-Admin) -and -not $AUTO) {
    $args2 = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', ('"' + $MyInvocation.MyCommand.Path + '"'), '-ForUser', ('"' + $ForUser + '"'), '-UserData', ('"' + $UserData + '"'))
    if ($App) { $args2 += @('-App', ('"' + $App + '"')) }
    try { Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList $args2 -Verb RunAs -WindowStyle Hidden }
    catch { Say "The English patch needs administrator permission to change vivo Office Kit, which is installed in Program Files.`n`nRun the installer again and click Yes when Windows asks." ; exit 4 }
    exit 0
}

$appArg = @(); if ($App) { $appArg = @('-App', $App) }
$r = Invoke-Script $PATCHER (@('status') + $appArg)
if ($r.rc -ne 0) { Say $r.out; exit $r.rc }
$lines = $r.out -split "`r?`n"
$STATE = $lines[0]; $APP = $lines[1]; $MODE = $lines[2]; $DETAIL = $lines[3]
$VER = Get-VivoVersion $APP
$NOTE = ''
if ($MODE -eq 'basic') { $NOTE = "`n`nNote: this is version $VER, not the 7.0.5 build the patch was made for. It will be installed in basic mode, which switches the app to vivo's own built-in English. It has not been tested on this version and some screens may stay in Chinese." }
if ($DETAIL -match 'changed by another tool') { $NOTE += "`n`nAnother tool has already changed this copy of vivo Office Kit. Its version is kept as app.asar.pre-english-patch, and vivo's own untouched copy is used instead." }

if ($AUTO) { $ACTION = $AUTO }
else {
    switch ($STATE) {
        'original' { $c = Ask "vivo Office Kit $VER was found and is currently in Chinese.`n`nInstall the English patch? The original is kept as a backup and can be restored at any time by running this again.$NOTE" 'Install English' @('Cancel', 'Install English') }
        'patched'  { $c = Ask "The English patch is already installed.`n`nYou can reinstall it (for example after updating this patch) or restore the original Chinese version.$NOTE" 'Reinstall English' @('Cancel', 'Restore Chinese', 'Reinstall English') }
        default    { [void](Ask "This copy of vivo Office Kit (version $VER) is too different from the one this patch was made for: $DETAIL.`n`nNothing will be changed." 'OK' @('OK')); exit 3 }
    }
    switch ($c) { 'Install English' { $ACTION = 'install' } 'Reinstall English' { $ACTION = 'install' } 'Restore Chinese' { $ACTION = 'restore' } default { exit 0 } }
}

if ((Get-VivoProcesses $APP).Count -and -not $AUTO) {
    $c = Ask "vivo Office Kit is running and needs to quit first." 'Quit and Continue' @('Cancel', 'Quit and Continue')
    if ($c -ne 'Quit and Continue') { exit 0 }
    if (-not (Stop-Vivo $APP)) { Say "vivo Office Kit is still running. Quit it from its tray icon (next to the clock), then run this installer again."; exit 1 }
}

$r = Invoke-Script $PATCHER @($ACTION, '-App', $APP)
$OUT = $r.out
if ($r.rc -eq 5 -and -not $AUTO) {
    # Something still holds the archive open (usually a vivo process that was slow to exit): try once more.
    [void](Stop-Vivo $APP); Start-Sleep -Seconds 2
    $r = Invoke-Script $PATCHER @($ACTION, '-App', $APP); $OUT = $r.out
}
if ($r.rc -eq 4 -and -not $AUTO) { Say "Windows did not allow the change to vivo Office Kit's folder:`n`n$OUT`n`nRun the installer again and click Yes when Windows asks for permission."; exit 4 }
if ($r.rc -ne 0) { Say "The patch could not be applied:`n`n$OUT"; exit $r.rc }

if ($ACTION -eq 'restore') {
    # Back to Chinese: stop the watcher too, or it would put English straight back after the next update.
    [void](Invoke-Script $WATCH @('remove', '-UserData', $UserData))
    if ($AUTO) { Write-Output $OUT; exit 0 }
    [void](Ask $OUT 'Done' @('Done')); exit 0
}
if ($AUTO) { Write-Output $OUT; exit 0 }

$ws = Invoke-Script $WATCH @('status', '-UserData', $UserData)
if ($ws.out -eq 'on') {
    $w = Invoke-Script $WATCH @('install', '-ForUser', $ForUser, '-UserData', $UserData)   # refresh the watcher's copy of the patch
    if ($w.rc -ne 0) { [void](Ask "The English patch was installed, but refreshing the automatic re-patching helper reported a problem:`n`n$($w.out)" 'OK' @('OK')) }
} else {
    $c = Ask "$OUT`n`nvivo Office Kit's own updates put it back into Chinese. Reapply the English patch automatically after each update?`n`nThis adds a small background helper (`"vivo English Watcher`") that starts when you sign in to Windows." 'Yes, Keep English' @('No', 'Yes, Keep English')
    if ($c -eq 'Yes, Keep English') {
        $w = Invoke-Script $WATCH @('install', '-ForUser', $ForUser, '-UserData', $UserData)
        if ($w.rc -ne 0) { [void](Ask "Automatic re-patching could not be turned on:`n`n$($w.out)" 'OK' @('OK')) }
    }
    $OUT = 'Done.'
}

$c = Ask "$OUT`n`nOpen vivo Office Kit now?" 'Open vivo Office Kit' @('Done', 'Open vivo Office Kit')
if ($c -eq 'Open vivo Office Kit') { Start-Vivo $APP }
exit 0
