param(
  [Parameter(Mandatory = $true)][string]$JnaJar,
  [Parameter(Mandatory = $true)][string]$PortAudioDll,
  [string]$JdkBin = 'C:\Program Files\Processing\app\resources\jdk\bin'
)
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$jna = (Resolve-Path -LiteralPath $JnaJar).Path
$dll = (Resolve-Path -LiteralPath $PortAudioDll).Path
$target = Join-Path $here 'data\wasapi'
$temporary = Join-Path ([System.IO.Path]::GetTempPath()) ("visualizer-wasapi-" + [guid]::NewGuid())
try {
  New-Item -ItemType Directory -Path $temporary | Out-Null
  & (Join-Path $JdkBin 'javac.exe') -cp $jna -d $temporary `
    (Join-Path $here 'audio-src\RollingAudioBuffer.java') `
    (Join-Path $here 'audio-src\WasapiInput.java') `
    (Join-Path $here 'audio-src\WasapiInputTest.java') `
    (Join-Path $here 'audio-src\RollingAudioBufferTest.java')
  if ($LASTEXITCODE -ne 0) { throw 'WASAPI compilation failed' }
  & (Join-Path $JdkBin 'java.exe') -cp $temporary RollingAudioBufferTest
  if ($LASTEXITCODE -ne 0) { throw 'Rolling buffer tests failed' }
  & (Join-Path $JdkBin 'java.exe') -cp "$temporary;$jna" WasapiInputTest
  if ($LASTEXITCODE -ne 0) { throw 'WASAPI tests failed' }
  Remove-Item -LiteralPath (Join-Path $temporary 'RollingAudioBufferTest.class')
  Remove-Item -LiteralPath (Join-Path $temporary 'WasapiInputTest.class')
  New-Item -ItemType Directory -Force -Path $target | Out-Null
  & (Join-Path $JdkBin 'jar.exe') cf (Join-Path $target 'wasapi-backend.jar') -C $temporary .
  if ($LASTEXITCODE -ne 0) { throw 'WASAPI jar creation failed' }
  Copy-Item -LiteralPath $jna -Destination (Join-Path $target 'jna.jar') -Force
  Copy-Item -LiteralPath $dll -Destination (Join-Path $target 'portaudio.dll') -Force
  Write-Host "WASAPI dependencies installed in $target"
} finally {
  if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Recurse -Force }
}
