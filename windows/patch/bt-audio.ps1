# Phone audio on this PC: lets a paired phone play its sound through the PC, like a Bluetooth speaker.
# Uses Windows' own Bluetooth audio receiver (Windows.Media.Audio.AudioPlaybackConnection, Windows 10 2004+).
# Started by the patched vivo Office Kit; talks back with one JSON object per line on stdout.
#   VOK_BT_MODE=list                      -> {"devices":[{"id":...,"name":...}]}
#   VOK_BT_MODE=connect VOK_BT_ID=<id>    -> {"state":"connecting"} then {"state":"connected"} ... {"state":"closed"}
#   VOK_BT_PARENT=<pid>                   exit when that process (vivo Office Kit) is gone
$ErrorActionPreference = 'Stop'
function Say($o) { [Console]::Out.WriteLine(($o | ConvertTo-Json -Compress -Depth 4)); [Console]::Out.Flush() }
try {
    Add-Type -AssemblyName System.Runtime.WindowsRuntime
    $null = [Windows.Media.Audio.AudioPlaybackConnection, Windows.Media.Audio, ContentType = WindowsRuntime]
    $null = [Windows.Devices.Enumeration.DeviceInformation, Windows.Devices.Enumeration, ContentType = WindowsRuntime]
    $ext = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 }
    $asOp = $ext | Where-Object { $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' } | Select-Object -First 1
    $asAction = $ext | Where-Object { $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncAction' } | Select-Object -First 1
    function Await($op, [Type]$t) { $task = $asOp.MakeGenericMethod($t).Invoke($null, @($op)); [void]$task.Wait(-1); $task.Result }
    function AwaitAction($op) { $task = $asAction.Invoke($null, @($op)); [void]$task.Wait(-1) }
    Add-Type -TypeDefinition @'
using System; using System.Collections.Generic; using System.Runtime.InteropServices;
namespace VokBt {
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
  int GetSessionIdentifier([MarshalAs(UnmanagedType.LPWStr)] out string id); int GetSessionInstanceIdentifier([MarshalAs(UnmanagedType.LPWStr)] out string id); }
[ComImport, Guid("1C158861-B533-4B30-B1CF-E853E51C59B8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)] interface IChannelAudioVolume {
  int GetChannelCount(out uint count); int SetChannelVolume(uint index, float level, ref Guid ctx); int GetChannelVolume(uint index, out float level); }
[ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class MMDeviceEnumerator {}
public static class Vol {
  // Sessions of the phone's Bluetooth stream ("... A2DP SNK") on every active playback device.
  static List<IAudioSessionControl2> Find(List<string> ids) {
    var found = new List<IAudioSessionControl2>();
    try {
      var en = (IMMDeviceEnumerator)new MMDeviceEnumerator(); IMMDeviceCollection col; en.EnumAudioEndpoints(0, 1, out col); int n; col.GetCount(out n);
      for (int i = 0; i < n; i++) { IMMDevice d; col.Item(i, out d); var iid = typeof(IAudioSessionManager2).GUID; object o; d.Activate(ref iid, 23, IntPtr.Zero, out o);
        IAudioSessionEnumerator se; ((IAudioSessionManager2)o).GetSessionEnumerator(out se); int sc; se.GetCount(out sc);
        for (int j = 0; j < sc; j++) { IAudioSessionControl2 s; se.GetSession(j, out s); string dn; s.GetDisplayName(out dn);
          if (dn != null && dn.IndexOf("A2DP SNK", StringComparison.OrdinalIgnoreCase) >= 0) { found.Add(s); if (ids != null) { string id; s.GetSessionInstanceIdentifier(out id); ids.Add(id); } } } }
    } catch {}
    return found; }
  public static string Ids() { var ids = new List<string>(); Find(ids); ids.Sort(); return string.Join("|", ids); }
  public static int Set(float level) { int done = 0; Guid ctx = Guid.Empty;
    foreach (var s in Find(null)) { try { var v = (IChannelAudioVolume)s; uint c; v.GetChannelCount(out c); for (uint k = 0; k < c; k++) v.SetChannelVolume(k, level, ref ctx); done++; } catch {} }
    return done; }
  public static float Get() { foreach (var s in Find(null)) { try { var v = (IChannelAudioVolume)s; float l; v.GetChannelVolume(0, out l); return l; } catch {} } return -1; } } }
'@
    $mode = $env:VOK_BT_MODE
    if ($mode -eq 'list') {
        $sel = [Windows.Media.Audio.AudioPlaybackConnection]::GetDeviceSelector()
        $all = Await ([Windows.Devices.Enumeration.DeviceInformation]::FindAllAsync($sel)) ([Windows.Devices.Enumeration.DeviceInformationCollection])
        Say @{ devices = @($all | ForEach-Object { @{ id = $_.Id; name = $_.Name } }) }
        exit 0
    }
    if ($mode -ne 'connect' -or -not $env:VOK_BT_ID) { Say @{ state = 'error'; error = 'bad arguments' }; exit 1 }
    $parent = $null; if ($env:VOK_BT_PARENT) { try { $parent = Get-Process -Id ([int]$env:VOK_BT_PARENT) -ErrorAction Stop } catch { exit 0 } }
    Say @{ state = 'connecting' }
    $c = [Windows.Media.Audio.AudioPlaybackConnection]::TryCreateFromId($env:VOK_BT_ID)
    if (-not $c) { Say @{ state = 'error'; error = 'This device cannot send audio to the PC.' }; exit 1 }
    AwaitAction ($c.StartAsync())
    $r = Await ($c.OpenAsync()) ([Windows.Media.Audio.AudioPlaybackConnectionOpenResult])
    if ("$($r.Status)" -ne 'Success') { Say @{ state = 'error'; error = "Could not connect ($($r.Status)). Make sure Bluetooth is on and the phone is nearby." }; exit 1 }
    Say @{ state = 'connected' }
    # Volume: the phone's stream plays in a Windows audio session named "... A2DP SNK". vivo Office Kit sends
    # "vol <0..1>" lines on stdin; the level is applied to that session only (other apps are not affected).
    $want = $null; if ($env:VOK_BT_VOLUME) { $want = [double]$env:VOK_BT_VOLUME }
    $seen = ''
    $stdin = New-Object IO.StreamReader([Console]::OpenStandardInput()); $read = $stdin.ReadLineAsync()
    while ($true) {
        if ($read.Wait(500)) {
            $line = $read.Result; if ($null -eq $line) { $read = $null } else { $read = $stdin.ReadLineAsync() }
            if ($line -match '^vol\s+([0-9.]+)$') { $want = [Math]::Max([double]0.0, [Math]::Min([double]1.0, [double]$Matches[1])); $seen = '' }
        }
        if ($null -eq $read) { Start-Sleep -Milliseconds 500 }
        if ($parent -and $parent.HasExited) { break }
        if ("$($c.State)" -eq 'Closed') { Say @{ state = 'closed' }; break }
        # Apply the wanted level once per session (Windows makes a new session when the phone starts streaming).
        $ids = [VokBt.Vol]::Ids()
        if ($ids -and $ids -ne $seen) {
            if ($null -ne $want) { [void][VokBt.Vol]::Set([float]$want) }
            $seen = $ids; Say @{ state = 'volume'; volume = [Math]::Round([double]([VokBt.Vol]::Get()), 3) }
        }
    }
    $c.Dispose()
} catch { Say @{ state = 'error'; error = $_.Exception.Message } ; exit 1 }
