# Phone audio on this PC: plays the phone's sound through the PC without mirroring the screen.
# Started by the patched vivo Office Kit; talks back with one JSON object per line on stdout, and takes
# "vol <0..1>" and "quit" lines on stdin.
#   VOK_BT_MODE=list                      -> {"devices":[{"id":...,"name":...}]}      (Bluetooth sources)
#   VOK_BT_MODE=connect VOK_BT_ID=<id>    Bluetooth: Windows' own receiver (AudioPlaybackConnection)
#   VOK_BT_MODE=wifi [VOK_PHONE_IP=<ip>] [VOK_AUDIO_DUP=1]
#                                         Wi-Fi: scrcpy by Genymobile (https://github.com/Genymobile/scrcpy,
#                                         Apache License 2.0) in audio-only mode, lossless FLAC. scrcpy is
#                                         downloaded once from its official release and checked before use.
#   VOK_BT_VOLUME=<0..1>  starting volume       VOK_BT_PARENT=<pid>  exit when that process is gone
# States: connecting, downloading, connected, volume, closed, error.
$ErrorActionPreference = 'Stop'
function Say($o) { [Console]::Out.WriteLine(($o | ConvertTo-Json -Compress -Depth 4)); [Console]::Out.Flush() }
$SCRCPY_VER = 'v5.0.1'
$SCRCPY_ZIP = "https://github.com/Genymobile/scrcpy/releases/download/$SCRCPY_VER/scrcpy-win64-$SCRCPY_VER.zip"
$SCRCPY_SHA = 'b12a2c4ee8be317422451fc7dcf8ee20a71b5ea7ef9ad73ddd825a25316227a5'
$ADB_PORT = '5137'   # our own adb server, so vivo Office Kit's adb (port 5037) is never disturbed
$scrcpy = $null
try {
    Add-Type -TypeDefinition @'
using System; using System.Collections.Generic; using System.Runtime.InteropServices;
namespace VokBt2 {
[ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)] interface IMMDeviceEnumerator {
  int EnumAudioEndpoints(int dataFlow, int stateMask, out IMMDeviceCollection devices); }
[ComImport, Guid("0BD7A1BE-7A1A-44DB-8397-CC5392387B5E"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)] interface IMMDeviceCollection {
  int GetCount(out int count); int Item(int index, out IMMDevice device); }
[ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)] interface IMMDevice {
  int Activate(ref Guid iid, int clsCtx, IntPtr p, [MarshalAs(UnmanagedType.IUnknown)] out object o); }
[ComImport, Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)] interface IAudioSessionManager2 {
  int GetAudioSessionControl(IntPtr g, int f, out IntPtr c); int GetSimpleAudioVolume(IntPtr g, int f, out IntPtr v);
  int GetSessionEnumerator(out IAudioSessionEnumerator e); }
[ComImport, Guid("E2F5BB11-0570-40CA-ACDD-3AA01277DEE8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)] interface IAudioSessionEnumerator {
  int GetCount(out int count); int GetSession(int index, out IAudioSessionControl2 session); }
[ComImport, Guid("bfb7ff88-7239-4fc9-8fa2-07c950be9c6d"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)] interface IAudioSessionControl2 {
  int GetState(out int state); int GetDisplayName([MarshalAs(UnmanagedType.LPWStr)] out string name); int SetDisplayName(string n, ref Guid g);
  int GetIconPath([MarshalAs(UnmanagedType.LPWStr)] out string p); int SetIconPath(string p, ref Guid g); int GetGroupingParam(out Guid g); int SetGroupingParam(ref Guid g, ref Guid c);
  int RegisterAudioSessionNotification(IntPtr n); int UnregisterAudioSessionNotification(IntPtr n);
  int GetSessionIdentifier([MarshalAs(UnmanagedType.LPWStr)] out string id); int GetSessionInstanceIdentifier([MarshalAs(UnmanagedType.LPWStr)] out string id);
  int GetProcessId(out uint pid); }
[ComImport, Guid("1C158861-B533-4B30-B1CF-E853E51C59B8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)] interface IChannelAudioVolume {
  int GetChannelCount(out uint count); int SetChannelVolume(uint index, float level, ref Guid ctx); int GetChannelVolume(uint index, out float level); }
[ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class MMDeviceEnumerator {}
public static class Vol {
  // The phone's audio sessions: scrcpy's process (Wi-Fi), or the session named "... A2DP SNK" (Bluetooth).
  static List<IAudioSessionControl2> Find(List<string> ids, uint pid) {
    var found = new List<IAudioSessionControl2>();
    try {
      var en = (IMMDeviceEnumerator)new MMDeviceEnumerator(); IMMDeviceCollection col; en.EnumAudioEndpoints(0, 1, out col); int n; col.GetCount(out n);
      for (int i = 0; i < n; i++) { IMMDevice d; col.Item(i, out d); var iid = typeof(IAudioSessionManager2).GUID; object o; d.Activate(ref iid, 23, IntPtr.Zero, out o);
        IAudioSessionEnumerator se; ((IAudioSessionManager2)o).GetSessionEnumerator(out se); int sc; se.GetCount(out sc);
        for (int j = 0; j < sc; j++) { IAudioSessionControl2 s; se.GetSession(j, out s); bool match;
          if (pid > 0) { uint p; s.GetProcessId(out p); match = p == pid; }
          else { string dn; s.GetDisplayName(out dn); match = dn != null && dn.IndexOf("A2DP SNK", StringComparison.OrdinalIgnoreCase) >= 0; }
          if (match) { found.Add(s); if (ids != null) { string id; s.GetSessionInstanceIdentifier(out id); ids.Add(id); } } } }
    } catch {}
    return found; }
  public static string Ids(uint pid) { var ids = new List<string>(); Find(ids, pid); ids.Sort(); return string.Join("|", ids); }
  public static int Set(float level, uint pid) { int done = 0; Guid ctx = Guid.Empty;
    foreach (var s in Find(null, pid)) { try { var v = (IChannelAudioVolume)s; uint c; v.GetChannelCount(out c); for (uint k = 0; k < c; k++) v.SetChannelVolume(k, level, ref ctx); done++; } catch {} }
    return done; }
  public static float Get(uint pid) { foreach (var s in Find(null, pid)) { try { var v = (IChannelAudioVolume)s; float l; v.GetChannelVolume(0, out l); return l; } catch {} } return -1; } } }
'@
    $mode = $env:VOK_BT_MODE
    $parent = $null; if ($env:VOK_BT_PARENT) { try { $parent = Get-Process -Id ([int]$env:VOK_BT_PARENT) -ErrorAction Stop } catch { exit 0 } }

    # Runs a program with a time limit; returns its combined output ('' if it timed out).
    function Run([string]$exe, [string[]]$a, [int]$ms) {
        $psi = New-Object Diagnostics.ProcessStartInfo; $psi.FileName = $exe; $psi.Arguments = ($a | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '
        $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
        $psi.EnvironmentVariables['ANDROID_ADB_SERVER_PORT'] = $ADB_PORT
        $p = [Diagnostics.Process]::Start($psi); $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
        if (-not $p.WaitForExit($ms)) { try { $p.Kill() } catch {}; return '' }
        return ($o.Result + $e.Result) }

    if ($mode -eq 'list') {
        Add-Type -AssemblyName System.Runtime.WindowsRuntime
        $null = [Windows.Media.Audio.AudioPlaybackConnection, Windows.Media.Audio, ContentType = WindowsRuntime]
        $null = [Windows.Devices.Enumeration.DeviceInformation, Windows.Devices.Enumeration, ContentType = WindowsRuntime]
        $asOp = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' } | Select-Object -First 1
        $sel = [Windows.Media.Audio.AudioPlaybackConnection]::GetDeviceSelector()
        $task = $asOp.MakeGenericMethod([Windows.Devices.Enumeration.DeviceInformationCollection]).Invoke($null, @([Windows.Devices.Enumeration.DeviceInformation]::FindAllAsync($sel))); [void]$task.Wait(-1)
        Say @{ devices = @($task.Result | ForEach-Object { @{ id = $_.Id; name = $_.Name } }) }
        exit 0
    }

    $conn = $null; $pidFilter = [uint32]0
    if ($mode -eq 'connect' -and $env:VOK_BT_ID) {
        # ---------------- Bluetooth
        Add-Type -AssemblyName System.Runtime.WindowsRuntime
        $null = [Windows.Media.Audio.AudioPlaybackConnection, Windows.Media.Audio, ContentType = WindowsRuntime]
        $ext = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 }
        $asOp = $ext | Where-Object { $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' } | Select-Object -First 1
        $asAction = $ext | Where-Object { $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncAction' } | Select-Object -First 1
        Say @{ state = 'connecting' }
        $conn = [Windows.Media.Audio.AudioPlaybackConnection]::TryCreateFromId($env:VOK_BT_ID)
        if (-not $conn) { Say @{ state = 'error'; error = 'This device cannot send audio to the PC.' }; exit 1 }
        $t = $asAction.Invoke($null, @($conn.StartAsync())); [void]$t.Wait(-1)
        $t = $asOp.MakeGenericMethod([Windows.Media.Audio.AudioPlaybackConnectionOpenResult]).Invoke($null, @($conn.OpenAsync())); [void]$t.Wait(-1)
        if ("$($t.Result.Status)" -ne 'Success') { Say @{ state = 'error'; error = "Could not connect ($($t.Result.Status)). Make sure Bluetooth is on and the phone is nearby." }; exit 1 }
    } elseif ($mode -eq 'wifi') {
        # ---------------- Wi-Fi (scrcpy, audio only)
        $W = Join-Path $env:LOCALAPPDATA 'vivo-office-kit-english-watcher'
        $dir = Join-Path $W "scrcpy\scrcpy-win64-$SCRCPY_VER"; $exe = Join-Path $dir 'scrcpy.exe'; $adb = Join-Path $dir 'adb.exe'
        if (-not (Test-Path -LiteralPath $exe)) {
            Say @{ state = 'downloading' }
            try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}
            $tmp = Join-Path $env:TEMP ('vok-scrcpy-' + [guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Path $tmp | Out-Null
            try {
                $zip = Join-Path $tmp 's.zip'
                try { Invoke-WebRequest -Uri $SCRCPY_ZIP -OutFile $zip -UseBasicParsing -TimeoutSec 300 } catch { Say @{ state = 'error'; error = 'Could not download the Wi-Fi audio component (scrcpy). Check the internet connection and try again.' }; exit 1 }
                if ((Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash -ne $SCRCPY_SHA.ToUpperInvariant()) { Say @{ state = 'error'; error = 'The downloaded Wi-Fi audio component did not pass its check and was not used.' }; exit 1 }
                $dest = Join-Path $W 'scrcpy'; New-Item -ItemType Directory -Force -Path $dest | Out-Null
                Expand-Archive -LiteralPath $zip -DestinationPath $dest -Force
            } finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
            if (-not (Test-Path -LiteralPath $exe)) { Say @{ state = 'error'; error = 'The Wi-Fi audio component could not be installed.' }; exit 1 }
        }
        Say @{ state = 'connecting' }
        # The phone's address on the network: from vivo Office Kit, or from its own logs.
        $ip = $env:VOK_PHONE_IP
        if (-not $ip) {
            foreach ($log in @("$env:APPDATA\pcsuite\log\relay_log\relay.log", "$env:APPDATA\pcsuite\log\relay_log\relay.log.1")) {
                if ($ip -or -not (Test-Path -LiteralPath $log)) { continue }
                try { $fs = [IO.File]::Open($log, 'Open', 'Read', 'ReadWrite'); $fs.Position = [Math]::Max(0, $fs.Length - 400000); $txt = (New-Object IO.StreamReader($fs)).ReadToEnd(); $fs.Close()
                    $m = [regex]::Matches($txt, 'mobileDeviceIp\\?":\\?"(\d{1,3}(?:\.\d{1,3}){3})'); if ($m.Count) { $ip = $m[$m.Count - 1].Groups[1].Value } } catch {}
            }
        }
        if (-not $ip) { Say @{ state = 'error'; error = "Couldn't find your phone on the network. Connect it in vivo Office Kit first, then try again." }; exit 1 }
        $serial = "${ip}:5555"
        $out = Run $adb @('connect', $serial) 15000
        $dev = Run $adb @('devices') 8000
        if ($dev -notmatch [regex]::Escape($serial) + '\s+device') {
            # Not listening on Wi-Fi (for example after the phone restarted). If it is plugged in by USB, switch its
            # debugging to Wi-Fi (port 5555) and try again.
            $usb = ($dev -split "`r?`n" | Where-Object { $_ -match '^(\S+)\s+device$' -and $_ -notmatch ':\d+\s' } | Select-Object -First 1)
            if ($usb -match '^(\S+)\s+device$') {
                [void](Run $adb @('-s', $Matches[1], 'tcpip', '5555') 10000); Start-Sleep -Seconds 3
                $out = Run $adb @('connect', $serial) 15000; $dev = Run $adb @('devices') 8000
            }
        }
        if ($dev -match [regex]::Escape($serial) + '\s+unauthorized' -or $out -match 'failed to authenticate') { Say @{ state = 'error'; error = 'Your phone is asking to allow debugging from this computer. Tap Allow (and Always allow), then try again.' }; exit 1 }
        if ($dev -notmatch [regex]::Escape($serial) + '\s+device') { Say @{ state = 'error'; error = "Your phone isn't accepting Wi-Fi audio from this computer right now. Connect it to this PC with a USB cable once, then try again, or switch to Bluetooth." }; exit 1 }
        $a = @('-s', $serial, '--no-window', '--audio-codec=flac', '--audio-buffer=200', '--no-clipboard-autosync')
        if ($env:VOK_AUDIO_DUP -eq '1') { $a += '--audio-dup' }
        $psi = New-Object Diagnostics.ProcessStartInfo; $psi.FileName = $exe; $psi.Arguments = $a -join ' '; $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.EnvironmentVariables['ANDROID_ADB_SERVER_PORT'] = $ADB_PORT; $psi.EnvironmentVariables['ADB'] = $adb
        $scrcpy = [Diagnostics.Process]::Start($psi)
        $sout = $scrcpy.StandardOutput.ReadToEndAsync(); $serr = $scrcpy.StandardError.ReadToEndAsync()   # drained continuously
        if ($scrcpy.WaitForExit(6000)) {
            [void]$sout.Wait(2000); [void]$serr.Wait(2000)
            $msg = (($serr.Result + "`n" + $sout.Result) -split "`r?`n" | Where-Object { $_ -match 'ERROR' } | Select-Object -Last 1)
            Say @{ state = 'error'; error = "Wi-Fi audio stopped right away. $msg".Trim() }; exit 1
        }
        $pidFilter = [uint32]$scrcpy.Id
    } else { Say @{ state = 'error'; error = 'bad arguments' }; exit 1 }

    Say @{ state = 'connected' }
    # Volume: applied to the phone's audio session only (other apps are not affected). vivo Office Kit sends
    # "vol <0..1>" lines on stdin, and "quit" to stop.
    $want = $null; if ($env:VOK_BT_VOLUME) { $want = [double]$env:VOK_BT_VOLUME }
    $seen = ''
    $stdin = New-Object IO.StreamReader([Console]::OpenStandardInput()); $read = $stdin.ReadLineAsync()
    while ($true) {
        if ($read -and $read.Wait(500)) {
            $line = $read.Result; if ($null -eq $line) { $read = $null } else { $read = $stdin.ReadLineAsync() }
            if ($line -match '^vol\s+([0-9.]+)$') { $want = [Math]::Max([double]0.0, [Math]::Min([double]1.0, [double]$Matches[1])); $seen = '' }
            elseif ($line -eq 'quit') { break }
        } elseif (-not $read) { Start-Sleep -Milliseconds 500 }
        if ($parent -and $parent.HasExited) { break }
        if ($conn -and "$($conn.State)" -eq 'Closed') { Say @{ state = 'closed' }; break }
        if ($scrcpy -and $scrcpy.HasExited) { Say @{ state = 'closed' }; break }
        # Apply the wanted level once per session (Windows makes a new session when the phone starts streaming).
        $ids = [VokBt2.Vol]::Ids($pidFilter)
        if ($ids -and $ids -ne $seen) {
            if ($null -ne $want) { [void][VokBt2.Vol]::Set([float]$want, $pidFilter) }
            $seen = $ids; Say @{ state = 'volume'; volume = [Math]::Round([double]([VokBt2.Vol]::Get($pidFilter)), 3) }
        }
    }
} catch { Say @{ state = 'error'; error = $_.Exception.Message } }
finally {
    if ($scrcpy -and -not $scrcpy.HasExited) { try { $scrcpy.Kill() } catch {} }
    if ($conn) { try { $conn.Dispose() } catch {} }
}
