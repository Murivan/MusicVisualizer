# Exports the sketch as a Windows application into .\windows-amd64 and adds the JNA jar the Processing exporter omits.
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$out = Join-Path $here 'windows-amd64'
Remove-Item $out -Recurse -Force -ErrorAction SilentlyContinue
& 'C:\Program Files\Processing\Processing.exe' cli --sketch="$here" --output="$out" --force --variant=windows-amd64 --export | Out-Host
# Processing.exe can return before the exporter has finished writing, so wait for the launcher.
$deadline = (Get-Date).AddSeconds(120)
while (-not (Test-Path (Join-Path $out 'PortAudioSpike.exe')) -and (Get-Date) -lt $deadline) { Start-Sleep 2 }
if (-not (Test-Path (Join-Path $out 'PortAudioSpike.exe'))) { throw 'Export failed' }
Copy-Item (Join-Path $here 'jna-lib\jna.jar') (Join-Path $out 'lib\jna.jar') -Force
Write-Host "Exported to $out"
