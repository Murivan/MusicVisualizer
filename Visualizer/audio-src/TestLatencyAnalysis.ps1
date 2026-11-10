$ErrorActionPreference = 'Stop'
$analyzer = Join-Path (Split-Path -Parent $PSScriptRoot) 'analyze-latency.ps1'
$path = Join-Path ([System.IO.Path]::GetTempPath()) ("latency-test-" + [guid]::NewGuid() + '.csv')
try {
  @('stimulusFrame,responseFrame') + @(1..20 | ForEach-Object { "$_,$($_ + 4)" }) |
    Set-Content -LiteralPath $path
  $result = & $analyzer -CsvPath $path -FramesPerSecond 240
  if (-not ($result -match 'p95 16[.,]667')) { throw "Incorrect p95: $result" }
  if (-not ($result -match 'p95 vs 25 ms: below')) { throw "Incorrect 25 ms classification: $result" }
  if (-not ($result -match 'p95 vs 50 ms: below')) { throw "Incorrect 50 ms classification: $result" }

  @('stimulusFrame,responseFrame') + @(1..20 | ForEach-Object { "$_,$($_ + 6)" }) |
    Set-Content -LiteralPath $path
  $result = & $analyzer -CsvPath $path -FramesPerSecond 240
  if (-not ($result -match 'p95 vs 25 ms: inconclusive')) { throw "Incorrect boundary classification: $result" }

  @('stimulusFrame,responseFrame') + @(1..19 | ForEach-Object { "$_,$($_ + 4)" }) + '20,40' |
    Set-Content -LiteralPath $path
  $result = & $analyzer -CsvPath $path -FramesPerSecond 240
  if (-not ($result -match 'p95 vs 50 ms: below')) { throw "Incorrect nearest-rank p95: $result" }
  if (-not ($result -match 'max vs 50 ms: at or above')) { throw "Incorrect max classification: $result" }

  @('stimulusFrame,responseFrame', '5,4') | Set-Content -LiteralPath $path
  $rejected = $false
  try { & $analyzer -CsvPath $path -FramesPerSecond 240 | Out-Null }
  catch { $rejected = $true }
  if (-not $rejected) { throw 'Negative frame difference was accepted' }
  Write-Host 'Latency analysis tests passed.'
} finally {
  if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
}
