param(
  [Parameter(Mandatory = $true)][string]$OutputPath,
  [string]$ProcessingExe = 'C:\Program Files\Processing\Processing.exe'
)
$ErrorActionPreference = 'Stop'
$sketch = $PSScriptRoot
$output = [System.IO.Path]::GetFullPath($OutputPath)

if (Test-Path -LiteralPath $output) {
  throw "Output path already exists; choose a new path: $output"
}
if (-not (Test-Path -LiteralPath (Split-Path -Parent $output) -PathType Container)) {
  throw "Output parent directory does not exist: $(Split-Path -Parent $output)"
}
if (-not (Test-Path -LiteralPath $ProcessingExe -PathType Leaf)) {
  throw "Processing executable not found: $ProcessingExe"
}

$data = Join-Path $sketch 'data'
$optional = @('wasapi\wasapi-backend.jar', 'wasapi\jna.jar', 'wasapi\portaudio.dll')
$present = @($optional | Where-Object { Test-Path -LiteralPath (Join-Path $data $_) -PathType Leaf })
$parameters = Get-Content -LiteralPath (Join-Path $data 'parameters.txt')
$wasapiSelected = $parameters -match '^\s*liveInputBackend\s*=\s*wasapi\s*(?:[#!].*)?$'
if (($present.Count -gt 0 -or $wasapiSelected) -and $present.Count -ne $optional.Count) {
  throw 'WASAPI dependencies are incomplete. Run setup-wasapi.ps1 before exporting.'
}

try {
  # Windows PowerShell wraps native stderr as ErrorRecord, including Processing's benign warnings.
  $ErrorActionPreference = 'Continue'
  & $ProcessingExe cli "--sketch=$sketch" "--output=$output" --variant=windows-amd64 --export 2>&1 |
    ForEach-Object { Write-Host $_ }
  $exportExitCode = $LASTEXITCODE
} finally {
  $ErrorActionPreference = 'Stop'
}
if ($exportExitCode -ne 0) { throw "Processing export failed with exit code $exportExitCode. Partial output remains at $output." }

foreach ($required in @('Visualizer.exe', 'lib\Visualizer.jar', 'java\bin\java.exe', 'data\parameters.txt')) {
  if (-not (Test-Path -LiteralPath (Join-Path $output $required) -PathType Leaf)) {
    throw "Export is incomplete: missing $required. Partial output remains at $output."
  }
}

foreach ($source in Get-ChildItem -LiteralPath $data -File -Recurse) {
  $relative = $source.FullName.Substring($data.Length).TrimStart('\')
  $destination = Join-Path (Join-Path $output 'data') $relative
  if (-not (Test-Path -LiteralPath $destination -PathType Leaf)) {
    throw "Export is incomplete: missing data\$relative"
  }
  if ((Get-FileHash -LiteralPath $source.FullName -Algorithm SHA256).Hash -ne
      (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash) {
    throw "Exported data does not match the source: data\$relative"
  }
}

$dependencies = foreach ($relative in $present) {
  [ordered]@{
    path = "data\$relative"
    sha256 = (Get-FileHash -LiteralPath (Join-Path $data $relative) -Algorithm SHA256).Hash
  }
}
$manifest = [ordered]@{
  description = 'SHA-256 hashes of optional WASAPI dependencies copied into this export'
  dependencies = @($dependencies)
}
$manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $output 'wasapi-dependencies.json') -Encoding UTF8
Write-Host "Verified Windows export: $output"
Write-Host 'The application still requires interactive and clean-machine testing.'
