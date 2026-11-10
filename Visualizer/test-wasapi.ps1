param(
  [Parameter(Mandatory = $true)][string]$DeviceName,
  [ValidateRange(1, 3600)][int]$DurationSeconds = 30,
  [ValidateRange(32, 8192)][int]$CaptureFrames = 256,
  [ValidateSet('shared', 'exclusive', 'exclusive-polling')][string]$Mode = 'shared',
  [string]$JdkBin = 'C:\Program Files\Processing\app\resources\jdk\bin'
)
$ErrorActionPreference = 'Stop'
$directory = Join-Path $PSScriptRoot 'data\wasapi'
foreach ($file in @('wasapi-backend.jar', 'jna.jar', 'portaudio.dll')) {
  if (-not (Test-Path -LiteralPath (Join-Path $directory $file) -PathType Leaf)) {
    throw "Missing $file. Run setup-wasapi.ps1 first."
  }
}
$temporary = Join-Path ([System.IO.Path]::GetTempPath()) ("wasapi-test-" + [guid]::NewGuid())
try {
  New-Item -ItemType Directory -Path $temporary | Out-Null
  $classpath = "$(Join-Path $directory 'wasapi-backend.jar');$(Join-Path $directory 'jna.jar')"
  & (Join-Path $JdkBin 'javac.exe') -cp $classpath -d $temporary (Join-Path $PSScriptRoot 'audio-src\WasapiSmokeTest.java')
  if ($LASTEXITCODE -ne 0) { throw 'WASAPI test compilation failed' }
  & (Join-Path $JdkBin 'java.exe') -cp "$temporary;$classpath" WasapiSmokeTest `
    (Join-Path $directory 'portaudio.dll') $DeviceName $DurationSeconds $CaptureFrames $Mode
  if ($LASTEXITCODE -ne 0) { throw "WASAPI capture test failed with exit code $LASTEXITCODE" }
} finally {
  if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Recurse -Force }
}
