@echo off
setlocal
cd /d "%~dp0"
title Music Visualizer - Image Analyzer

set "IMAGE_ANALYZER_OUTPUT=%~dp0output"
set "PYTHONNOUSERSITE=1"
set "PORT=8866"

rem Pick the first free port starting at 8866
:findport
netstat -an | findstr /r /c:":%PORT% .*LISTENING" >nul
if %errorlevel%==0 (
    set /a PORT+=1
    goto findport
)

echo Starting the Image Analyzer. Your browser will open in a moment.
echo Keep this window open while you work. Close it to quit the application.
echo.
"%~dp0python\python.exe" -m voila ImageAnalyzer_App.ipynb --port=%PORT% --Voila.ip=127.0.0.1
if errorlevel 1 (
    echo.
    echo The application stopped unexpectedly. See the messages above.
    pause
)
