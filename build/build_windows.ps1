# Builds dist\ImageAnalyzer-windows-x64.zip. Run from anywhere:  powershell -File build\build_windows.ps1
$ErrorActionPreference = 'Stop'
$env:PYTHONNOUSERSITE = '1'   # never let packages from the build machine leak into the bundle
$PbsTag = '20261026'
$PyVersion = '3.12.16'
$Asset = "cpython-$PyVersion+$PbsTag-x86_64-pc-windows-msvc-install_only_stripped.tar.gz"
$Url = "https://github.com/astral-sh/python-build-standalone/releases/download/$PbsTag/$([uri]::EscapeDataString($Asset))"

$Root = Split-Path -Parent $PSScriptRoot
$Dist = Join-Path $Root 'dist'
$Cache = Join-Path $Dist '.cache'
$Out = Join-Path $Dist 'ImageAnalyzer'
$Zip = Join-Path $Dist 'ImageAnalyzer-windows-x64.zip'

New-Item -ItemType Directory -Force $Cache | Out-Null
if (Test-Path $Out) { Remove-Item -Recurse -Force $Out }
New-Item -ItemType Directory -Force $Out | Out-Null

$Archive = Join-Path $Cache $Asset
if (-not (Test-Path $Archive)) {
    Write-Host "Downloading $Asset ..."
    Invoke-WebRequest $Url -OutFile $Archive
}

Write-Host 'Extracting Python runtime ...'
tar -xzf $Archive -C $Out          # produces $Out\python
if ($LASTEXITCODE -ne 0) { throw 'Extracting the Python runtime failed.' }
$Python = Join-Path $Out 'python\python.exe'

Write-Host 'Installing packages ...'
& $Python -m pip install --no-warn-script-location --disable-pip-version-check -r (Join-Path $Root 'bundle\requirements.txt')
if ($LASTEXITCODE -ne 0) { throw 'pip install failed.' }

Copy-Item (Join-Path $Root 'ImageAnalyzer_App.ipynb') $Out
Copy-Item (Join-Path $Root 'voila.json') $Out
Copy-Item (Join-Path $Root 'bundle\Start.bat') $Out
Copy-Item (Join-Path $Root 'bundle\README_USER.txt') $Out

Write-Host 'Smoke test ...'
& $Python -c "import cv2, numpy, ipywidgets, voila, ipykernel, tkinter; print('imports ok')"
if ($LASTEXITCODE -ne 0) { throw 'Smoke test failed: a required module cannot be imported.' }

$Port = 8899
$env:PYTHONNOUSERSITE = '1'
$Server = Start-Process -PassThru -WindowStyle Hidden -WorkingDirectory $Out -FilePath $Python `
    -ArgumentList '-m', 'voila', 'ImageAnalyzer_App.ipynb', '--no-browser', "--port=$Port", '--Voila.ip=127.0.0.1'
try {
    $ok = $false
    for ($i = 0; $i -lt 30 -and -not $ok; $i++) {
        Start-Sleep 2
        try { $ok = (Invoke-WebRequest "http://127.0.0.1:$Port/" -UseBasicParsing -TimeoutSec 60).StatusCode -eq 200 } catch { }
    }
    if (-not $ok) { throw 'Smoke test failed: Voila did not serve the notebook.' }
} finally {
    Stop-Process -Id $Server.Id -Force -ErrorAction SilentlyContinue
}

# Drop bytecode caches created by the smoke test
Get-ChildItem $Out -Recurse -Directory -Filter '__pycache__' | Remove-Item -Recurse -Force

if (Test-Path $Zip) { Remove-Item $Zip }
Write-Host 'Creating zip ...'
Compress-Archive -Path $Out -DestinationPath $Zip -CompressionLevel Optimal
Write-Host ("Done: {0} ({1:N0} MB)" -f $Zip, ((Get-Item $Zip).Length / 1MB))
