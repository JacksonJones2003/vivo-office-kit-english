# Turns the automatic re-patching on or off.
#   setup-watcher.ps1 install   copy the patch to a fixed place, create the watcher task and start it
#   setup-watcher.ps1 remove    stop and delete the watcher
#   setup-watcher.ps1 status    print "on" or "off"
# -ForUser DOMAIN\name and -UserData <that user's LOCALAPPDATA> are passed by the installer, which may run elevated.
param([Parameter(Position = 0)][string]$Command, [string]$ForUser, [string]$UserData)
$ErrorActionPreference = 'Stop'
$SRC = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
if (-not $UserData) { $UserData = $env:LOCALAPPDATA }
if (-not $ForUser) { $ForUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name }
$W = Join-Path $UserData 'vivo-office-kit-english-watcher'
$TASK = 'vivo English Watcher'
$ON = Join-Path $W 'watcher-on'   # also read by the patched app to know automatic re-patching is on

function Stop-Monitor {   # ends a running helper (the task, and any copy started by hand)
    try { Stop-ScheduledTask -TaskName $TASK -ErrorAction SilentlyContinue } catch {}
    try {
        Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -and $_.CommandLine -like "*$W\watcher.ps1*" -and $_.ProcessId -ne $PID } |
            ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } catch {} }
    } catch {}
}

switch ($Command) {
'status' {
    $t = Get-ScheduledTask -TaskName $TASK -ErrorAction SilentlyContinue
    if ($t -and (Test-Path -LiteralPath $ON)) { 'on' } else { 'off' }
}
'remove' {
    Stop-Monitor
    try { Unregister-ScheduledTask -TaskName $TASK -Confirm:$false -ErrorAction SilentlyContinue } catch {}
    Remove-Item -LiteralPath $ON -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
    if (Test-Path -LiteralPath $W) { Get-ChildItem -LiteralPath $W -Force | Where-Object { $_.Name -ne 'vivo-office-kit-english.log' } | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue }
    'Automatic re-patching is off.'
}
'install' {
    try {
        New-Item -ItemType Directory -Force -Path $W | Out-Null
        # Fresh copy of the patch itself, swapped in whole.
        $new = Join-Path $W 'kit.new'; $kit = Join-Path $W 'kit'
        if (Test-Path -LiteralPath $new) { Remove-Item -LiteralPath $new -Recurse -Force }
        New-Item -ItemType Directory -Force -Path $new | Out-Null
        Copy-Item -LiteralPath (Join-Path $SRC 'patcher.ps1') -Destination $new
        Copy-Item -LiteralPath (Join-Path $SRC 'patch') -Destination $new -Recurse
        Stop-Monitor
        if (Test-Path -LiteralPath $kit) { Remove-Item -LiteralPath $kit -Recurse -Force }
        Rename-Item -LiteralPath $new -NewName 'kit'
        foreach ($f in 'watcher.ps1', 'ui.ps1') { Copy-Item -LiteralPath (Join-Path $SRC "watcher\$f") -Destination $W -Force }
        Get-ChildItem -LiteralPath $W -Recurse -File | Unblock-File -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath (Join-Path $W 'no-reminders'), (Join-Path $W 'snoozed-copy') -Force -ErrorAction SilentlyContinue   # running the installer turns reminder popups back on
        Set-Content -LiteralPath $ON -Value (Get-Date -Format s) -Encoding ASCII
    } catch { [Console]::Error.WriteLine("Could not copy the patch files: $($_.Exception.Message)"); exit 1 }

    # One task, started at sign-in, that keeps the helper running. With "highest privileges" it can update the app in
    # Program Files after vivo updates without asking each time (like allowing it once under App Management on a Mac).
    $ps = Join-Path $PSHOME 'powershell.exe'
    $action = New-ScheduledTaskAction -Execute $ps -Argument ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + (Join-Path $W 'watcher.ps1') + '" monitor')
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $ForUser
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew -RestartCount 5 -RestartInterval (New-TimeSpan -Minutes 1) -StartWhenAvailable
    $desc = 'Reapplies the unofficial vivo Office Kit English patch after vivo updates the app. Remove it by running the patch installer and choosing Restore Chinese.'
    $elevated = $true
    if ($env:VOK_TASK_DRYRUN) {   # test hook: build the task definition without registering it
        $principal = New-ScheduledTaskPrincipal -UserId $ForUser -LogonType Interactive -RunLevel Highest
        $t = New-ScheduledTask -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description $desc
        "(test) task: $($t.Actions[0].Execute) $($t.Actions[0].Arguments) | logon trigger for $($t.Triggers[0].UserId) | run level $($t.Principal.RunLevel)"; exit 0
    }
    try {
        $principal = New-ScheduledTaskPrincipal -UserId $ForUser -LogonType Interactive -RunLevel Highest
        Register-ScheduledTask -TaskName $TASK -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description $desc -Force | Out-Null
    } catch {
        # Not an administrator: the helper still works, but asks for permission each time it needs to patch.
        $elevated = $false
        try {
            $principal = New-ScheduledTaskPrincipal -UserId $ForUser -LogonType Interactive -RunLevel Limited
            Register-ScheduledTask -TaskName $TASK -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description $desc -Force | Out-Null
        } catch { [Console]::Error.WriteLine("Could not create the watcher task: $($_.Exception.Message)"); exit 1 }
    }
    if ($env:VOK_NO_TASKSTART) { '(test) watcher files and task created, not started'; exit 0 }
    try { Start-ScheduledTask -TaskName $TASK } catch { [Console]::Error.WriteLine("Could not start the watcher. It will start the next time you sign in."); exit 1 }
    if ($elevated) { 'Automatic re-patching is on.' } else { 'Automatic re-patching is on. Windows will ask for permission each time the patch needs to be reapplied.' }
}
default { [Console]::Error.WriteLine('usage: setup-watcher.ps1 install|remove|status'); exit 1 }
}
exit 0
