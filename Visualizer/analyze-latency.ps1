param(
  [Parameter(Mandatory = $true)][string]$CsvPath,
  [Parameter(Mandatory = $true)][double]$FramesPerSecond
)
$ErrorActionPreference = 'Stop'
if ([double]::IsNaN($FramesPerSecond) -or [double]::IsInfinity($FramesPerSecond) -or $FramesPerSecond -le 0) {
  throw 'FramesPerSecond must be a finite positive number.'
}
$rows = @(Import-Csv -LiteralPath $CsvPath)
if ($rows.Count -eq 0) { throw 'The CSV must contain at least one measurement.' }
if (-not ($rows[0].PSObject.Properties.Name -contains 'stimulusFrame') -or
    -not ($rows[0].PSObject.Properties.Name -contains 'responseFrame')) {
  throw 'The CSV must have stimulusFrame and responseFrame columns.'
}
$measurements = @(
  for ($i = 0; $i -lt $rows.Count; $i++) {
    [long]$stimulus = 0
    [long]$response = 0
    if (-not [long]::TryParse($rows[$i].stimulusFrame, [ref]$stimulus) -or
        -not [long]::TryParse($rows[$i].responseFrame, [ref]$response) -or
        $stimulus -lt 0 -or $response -lt $stimulus) {
      throw "Invalid frame numbers in CSV row $($i + 2): use nonnegative integers with responseFrame >= stimulusFrame."
    }
    ($response - $stimulus) * 1000.0 / $FramesPerSecond
  }
)
$sorted = @($measurements | Sort-Object)
$mean = ($measurements | Measure-Object -Average).Average
$p95 = $sorted[[int][Math]::Ceiling($sorted.Count * 0.95) - 1]
$resolution = 1000.0 / $FramesPerSecond
Write-Output ("Trials: {0}; camera frame rate: {1:F3} fps; frame interval: {2:F3} ms" -f $sorted.Count, $FramesPerSecond, $resolution)
Write-Output ("Latency ms: min {0:F3}; mean {1:F3}; p95 {2:F3}; max {3:F3}" -f $sorted[0], $mean, $p95, $sorted[-1])
Write-Output 'p95 uses the nearest-rank method. Frame quantization alone is approximately +/- one frame interval.'
Write-Output 'Measurements include the physical stimulus and display path; other timing errors are not quantified.'
foreach ($metric in @(@('p95', $p95), @('max', $sorted[-1]))) {
  foreach ($threshold in @(25, 50)) {
    $value = [double]$metric[1]
    $classification = if ($value + $resolution -lt $threshold) {
      'below, allowing for one frame of quantization only'
    } elseif ($value - $resolution -ge $threshold) {
      'at or above, allowing for one frame of quantization only'
    } else {
      'inconclusive at this frame rate'
    }
    Write-Output ("{0} vs {1} ms: {2}" -f $metric[0], $threshold, $classification)
  }
}
if ($sorted.Count -lt 20) {
  Write-Warning 'Fewer than 20 trials: p95 is not a reliable stability measure.'
}
