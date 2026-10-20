# Shared helpers for the installer and the background helper: dialogs, notifications, running the patcher,
# and finding / quitting / starting vivo Office Kit. Dot-source this file.
#   VOK_AUTO=1   no dialogs: Ask returns the default button (used for testing)
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
try { Add-Type -Namespace VokUi -Name Dpi -MemberDefinition '[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();' -ErrorAction Stop; [void][VokUi.Dpi]::SetProcessDPIAware() } catch {}
[System.Windows.Forms.Application]::EnableVisualStyles()
$script:VokTitle = 'vivo Office Kit English Patch'

# Show-Ask "message" "default button" @("button", ...) [-Check "checkbox text"] [-TimeoutSec n]
#   -> @{ button = clicked button ('' if closed or timed out); checked = checkbox state }
function Show-Ask([string]$Message, [string]$Default, [string[]]$Buttons, [string]$Check = '', [int]$TimeoutSec = 0) {
    if ($env:VOK_AUTO) { return @{ button = $Default; checked = $false } }
    $form = New-Object Windows.Forms.Form
    $form.Text = $script:VokTitle; $form.FormBorderStyle = 'FixedDialog'; $form.MaximizeBox = $false; $form.MinimizeBox = $false
    $form.StartPosition = 'CenterScreen'; $form.TopMost = $true; $form.ShowInTaskbar = $true; $form.AutoSize = $true; $form.AutoSizeMode = 'GrowAndShrink'
    $form.Font = New-Object Drawing.Font('Segoe UI', 9.5); $form.AutoScaleMode = 'Dpi'; $form.Padding = New-Object Windows.Forms.Padding(14)
    try { $form.Icon = [Drawing.Icon]::ExtractAssociatedIcon((Join-Path $PSHOME 'powershell.exe')) } catch {}
    $grid = New-Object Windows.Forms.TableLayoutPanel; $grid.AutoSize = $true; $grid.ColumnCount = 2; $grid.RowCount = 3; $grid.Dock = 'Fill'
    $pic = New-Object Windows.Forms.PictureBox; $pic.Image = [Drawing.SystemIcons]::Information.ToBitmap(); $pic.SizeMode = 'AutoSize'; $pic.Margin = New-Object Windows.Forms.Padding(0, 2, 12, 0)
    $lbl = New-Object Windows.Forms.Label; $lbl.Text = $Message; $lbl.AutoSize = $true; $lbl.MaximumSize = New-Object Drawing.Size(460, 0); $lbl.Margin = New-Object Windows.Forms.Padding(0, 0, 0, 12)
    $grid.Controls.Add($pic, 0, 0); $grid.Controls.Add($lbl, 1, 0)
    $cb = $null
    if ($Check) { $cb = New-Object Windows.Forms.CheckBox; $cb.Text = $Check; $cb.AutoSize = $true; $cb.Margin = New-Object Windows.Forms.Padding(0, 0, 0, 10); $grid.Controls.Add($cb, 1, 1) }
    $flow = New-Object Windows.Forms.FlowLayoutPanel; $flow.AutoSize = $true; $flow.FlowDirection = 'LeftToRight'; $flow.Anchor = 'Right'; $flow.WrapContents = $false
    $script:VokClicked = ''
    foreach ($b in $Buttons) {
        $btn = New-Object Windows.Forms.Button; $btn.Text = $b; $btn.AutoSize = $true; $btn.MinimumSize = New-Object Drawing.Size(90, 30); $btn.Padding = New-Object Windows.Forms.Padding(8, 0, 8, 0)
        $btn.Add_Click({ $script:VokClicked = $this.Text; $this.FindForm().Close() })
        $flow.Controls.Add($btn)
        if ($b -eq $Default) { $form.AcceptButton = $btn; $form.Add_Shown({ $this.AcceptButton.Focus() }) }
    }
    $grid.Controls.Add($flow, 0, 2); $grid.SetColumnSpan($flow, 2)
    $form.Controls.Add($grid)
    if ($TimeoutSec -gt 0) { $t = New-Object Windows.Forms.Timer; $t.Interval = $TimeoutSec * 1000; $t.Add_Tick({ $this.Stop(); $form.Close() }); $t.Start() }
    $form.Add_Shown({ $this.Activate() })
    if ($env:VOK_SNAPSHOT) {   # test hook: save a picture of the dialog and close it
        $form.Add_Shown({ [Windows.Forms.Application]::DoEvents(); $bmp = New-Object Drawing.Bitmap($this.Width, $this.Height); $this.DrawToBitmap($bmp, (New-Object Drawing.Rectangle(0, 0, $this.Width, $this.Height))); $bmp.Save($env:VOK_SNAPSHOT); $bmp.Dispose(); $this.Close() })
    }
    [void]$form.ShowDialog()
    $r = @{ button = $script:VokClicked; checked = [bool]($cb -and $cb.Checked) }
    $form.Dispose()
    return $r
}
function Ask([string]$Message, [string]$Default, [string[]]$Buttons, [int]$TimeoutSec = 0) { (Show-Ask $Message $Default $Buttons -TimeoutSec $TimeoutSec).button }
function Say([string]$Message) { if ($env:VOK_AUTO) { Write-Output $Message } else { [void](Ask $Message 'OK' @('OK')) } }

# A notification in the corner of the screen (Windows shows it as a toast).
function Notify([string]$Message) {
    if ($env:VOK_AUTO) { return }
    try {
        $n = New-Object Windows.Forms.NotifyIcon
        $n.Icon = [Drawing.SystemIcons]::Information; $n.Text = 'vivo English Patch'; $n.Visible = $true
        $n.ShowBalloonTip(8000, $script:VokTitle, $Message, [Windows.Forms.ToolTipIcon]::Info)
        for ($i = 0; $i -lt 40; $i++) { [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 200 }
        $n.Visible = $false; $n.Dispose()
    } catch {}
}

# Runs a PowerShell script in a child process; returns @{ rc; out } with stdout and stderr together.
function Invoke-Script([string]$Script, [string[]]$Arguments) {
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = Join-Path $PSHOME 'powershell.exe'
    $quoted = $Arguments | ForEach-Object { if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ } }
    $psi.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $Script + '" ' + ($quoted -join ' ')
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [Text.Encoding]::UTF8; $psi.StandardErrorEncoding = [Text.Encoding]::UTF8
    $p = [Diagnostics.Process]::Start($psi)
    $errTask = $p.StandardError.ReadToEndAsync(); $o = $p.StandardOutput.ReadToEnd(); $p.WaitForExit()
    $text = ($o + $errTask.Result).Trim()
    return @{ rc = $p.ExitCode; out = $text }
}
# Same, but elevated through the Windows permission (UAC) prompt. rc -128 if the prompt was cancelled.
function Invoke-ScriptElevated([string]$Script, [string[]]$Arguments) {
    $log = Join-Path $env:TEMP ("vok-elevated-" + [guid]::NewGuid().ToString('N') + '.txt')
    $quoted = ($Arguments | ForEach-Object { "'" + ($_ -replace "'", "''") + "'" }) -join ' '
    $cmd = "& '" + ($Script -replace "'", "''") + "' $quoted *> '" + $log + "'; exit `$LASTEXITCODE"
    try { $p = Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-Command', $cmd) -Verb RunAs -WindowStyle Hidden -PassThru -Wait }
    catch { return @{ rc = -128; out = 'The permission prompt was cancelled.' } }
    $out = ''; try { $out = (Get-Content -LiteralPath $log -Raw -Encoding UTF8).Trim(); Remove-Item -LiteralPath $log -Force } catch {}
    return @{ rc = $p.ExitCode; out = $out }
}
function Test-Admin { ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) }

# vivo Office Kit's own processes (main window and its Electron helpers).
function Get-VivoProcesses([string]$App) {
    $exe = Join-Path $App 'pcsuite.exe'
    @(Get-Process -Name pcsuite -ErrorAction SilentlyContinue | Where-Object { try { $_.Path -eq $exe } catch { $false } })
}
function Get-VivoLaunchId([string]$App) {   # changes every time the app is started; '' when it is not running
    $p = Get-VivoProcesses $App | Sort-Object { try { $_.StartTime } catch { [datetime]::MaxValue } } | Select-Object -First 1
    if ($p) { try { return "$($p.Id)@$($p.StartTime.Ticks)" } catch { return "$($p.Id)" } }
    return ''
}
function Stop-Vivo([string]$App) {   # politely first, then firmly; returns $true when it is gone
    foreach ($p in Get-VivoProcesses $App) { try { [void]$p.CloseMainWindow() } catch {} }
    for ($i = 0; $i -lt 6 -and (Get-VivoProcesses $App).Count; $i++) { Start-Sleep -Milliseconds 500 }
    # vivo Office Kit keeps running in the tray when its window is closed, so end it.
    foreach ($p in Get-VivoProcesses $App) { try { $p.Kill() } catch {} }
    for ($i = 0; $i -lt 20 -and (Get-VivoProcesses $App).Count; $i++) { Start-Sleep -Milliseconds 500 }
    return -not (Get-VivoProcesses $App).Count
}
# Starts the app as the signed-in user, not elevated, even when this script runs as administrator.
function Start-Vivo([string]$App) { try { Start-Process -FilePath (Join-Path $env:WINDIR 'explorer.exe') -ArgumentList ('"' + (Join-Path $App 'pcsuite.exe') + '"') } catch {} }
function Get-VivoVersion([string]$App) { try { $v = (Get-Item -LiteralPath (Join-Path $App 'pcsuite.exe') -ErrorAction Stop).VersionInfo.FileVersion; if ($v) { return ($v -replace '^(\d+\.\d+\.\d+).*$', '$1') } } catch {}; return 'unknown' }
