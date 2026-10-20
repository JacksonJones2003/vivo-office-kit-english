# One-line installer for the vivo Office Kit English patch (Windows). In PowerShell:
#   irm https://raw.githubusercontent.com/JacksonJones2003/vivo-office-kit-english/main/windows/quick-install.ps1 | iex
# Downloads the latest release from this project's GitHub page, checks it against the checksum in latest.json,
# and opens the installer.
& {
    $ErrorActionPreference = 'Stop'
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}
    $repo = 'https://github.com/JacksonJones2003/vivo-office-kit-english'
    $raw = (Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/JacksonJones2003/vivo-office-kit-english/main/windows/latest.json' -UseBasicParsing).Content; if ($raw -is [byte[]]) { $raw = [Text.Encoding]::UTF8.GetString($raw) }; $m = $raw | ConvertFrom-Json
    if (-not ([string]$m.zip_url).StartsWith("$repo/releases/download/windows-v") -or ([string]$m.zip_sha256).Length -ne 64) { throw 'The release information on GitHub looks wrong; nothing was downloaded.' }
    $dir = Join-Path $env:TEMP ('vivo-english-patch-' + [guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Path $dir | Out-Null
    $zip = Join-Path $dir 'patch.zip'
    Write-Host "Downloading the English patch $($m.version)..."
    Invoke-WebRequest -Uri $m.zip_url -OutFile $zip -UseBasicParsing
    if ((Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash -ne ([string]$m.zip_sha256).ToUpperInvariant()) { throw 'The download did not pass its checksum test and was not used.' }
    Expand-Archive -LiteralPath $zip -DestinationPath (Join-Path $dir 'x')
    $root = Join-Path $dir 'x'; if (-not (Test-Path (Join-Path $root 'install.ps1'))) { $root = (Get-ChildItem -LiteralPath $root -Directory | Select-Object -First 1).FullName }
    Get-ChildItem -LiteralPath $root -Recurse -File | Unblock-File
    Write-Host 'Opening the installer...'
    Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', ('"' + (Join-Path $root 'install.ps1') + '"'))
}
