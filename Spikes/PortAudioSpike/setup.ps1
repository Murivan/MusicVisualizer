# Prepares the sketch: PortAudio DLLs go to data/ (exported with the application), and code/portaudio-backend.jar
# holds the JNA facade. JNA itself must NOT be in code/: Processing maps the packages of every jar in code/ to
# imports, and com.sun.jna then clashes with the installed libraries that bundle it (video, ...). So JNA lives in
# jna-lib/ (found through the jar's Class-Path when running from the IDE) and export.ps1 copies it into the
# exported application's lib/ folder.
# PortAudio binaries come from the `sounddevice` wheel, which ships WASAPI/WDM-KS/MME/DirectSound
# builds, plus ASIO-enabled builds (ASIO licensing must be resolved before any redistribution).
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$code = Join-Path $here 'code'
$data = Join-Path $here 'data'
$jnaDir = Join-Path $here 'jna-lib'
New-Item -ItemType Directory -Force $code, $data, $jnaDir | Out-Null

$jna = Get-ChildItem 'C:\Program Files\Processing\app\resources\modes\java\mode' -Filter 'jna-5*.jar' | Select-Object -First 1
Copy-Item $jna.FullName (Join-Path $jnaDir 'jna.jar') -Force

$tmp = Join-Path $env:TEMP 'pa_spike_dl'
New-Item -ItemType Directory -Force $tmp | Out-Null
py -3.12 -m pip download sounddevice --no-deps -d $tmp | Out-Null
$whl = Get-ChildItem $tmp -Filter '*.whl' | Select-Object -First 1
$zip = Join-Path $tmp 'sd.zip'
Copy-Item $whl.FullName $zip -Force
Expand-Archive $zip (Join-Path $tmp 'x') -Force
$bin = Join-Path $tmp 'x\_sounddevice_data\portaudio-binaries'
Copy-Item (Join-Path $bin 'libportaudio64bit.dll') $data -Force
Copy-Item (Join-Path $bin 'libportaudio64bit-asio.dll') $data -Force
Copy-Item (Join-Path $bin 'libportaudio.dylib') $data -Force
Remove-Item $tmp -Recurse -Force

$jdk = 'C:\Program Files\Processing\app\resources\jdk\bin'
$classes = Join-Path $here 'backend-classes'
New-Item -ItemType Directory -Force $classes | Out-Null
& "$jdk\javac.exe" -cp (Join-Path $jnaDir 'jna.jar') -d $classes (Join-Path $here 'backend-src\PortAudioBackend.java')
if ($LASTEXITCODE -ne 0) { throw 'javac failed' }
& "$jdk\jar.exe" cfm (Join-Path $code 'portaudio-backend.jar') (Join-Path $here 'backend-src\manifest.txt') -C $classes .
if ($LASTEXITCODE -ne 0) { throw 'jar failed (is the sketch running or open in Processing?)' }
Remove-Item $classes -Recurse -Force
Write-Host "code/, data/ and jna-lib/ populated."
