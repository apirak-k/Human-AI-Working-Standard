@echo off
setlocal EnableDelayedExpansion
title HAWS 1-Click Universal Sync ^& System Update

echo ================================================================
echo           HAWS 1-Click Universal Sync ^& System Update
echo ================================================================
echo.

cd /d "%~dp0"

REM Detect bash executable
set "BASH_CMD="
where bash >nul 2>&1 && set "BASH_CMD=bash"
if not defined BASH_CMD (
    if exist "%ProgramFiles%\Git\bin\bash.exe" set "BASH_CMD=%ProgramFiles%\Git\bin\bash.exe"
)
if not defined BASH_CMD (
    if exist "%ProgramFiles(x86)%\Git\bin\bash.exe" set "BASH_CMD=%ProgramFiles(x86)%\Git\bin\bash.exe"
)
if not defined BASH_CMD (
    if exist "%ProgramFiles%\Git\usr\bin\bash.exe" set "BASH_CMD=%ProgramFiles%\Git\usr\bin\bash.exe"
)
if not defined BASH_CMD (
    if exist "%LocalAppData%\Programs\Git\bin\bash.exe" set "BASH_CMD=%LocalAppData%\Programs\Git\bin\bash.exe"
)
if not defined BASH_CMD (
    if exist "%USERPROFILE%\scoop\apps\git\current\bin\bash.exe" set "BASH_CMD=%USERPROFILE%\scoop\apps\git\current\bin\bash.exe"
)
if not defined BASH_CMD (
    if exist "%ProgramData%\chocolatey\bin\bash.exe" set "BASH_CMD=%ProgramData%\chocolatey\bin\bash.exe"
)
if not defined BASH_CMD (
    echo [ERROR] Git Bash was not found in your PATH or standard installation locations.
    echo Please install Git for Windows.
    pause
    exit /b 1
)

REM Run HAWS Universal Sync
echo [*] Running HAWS Universal Sync (Second Brain + Skills + Environments)...
echo.
"%BASH_CMD%" haws.sh sync %*
echo.

REM Run HAWS System Doctor
echo [*] Verifying System Health (10-Axis Diagnostics)...
echo.
"%BASH_CMD%" haws.sh doctor
echo.

echo ================================================================
echo   [PASS] 100%% Green - HAWS is fully updated, synced, and ready!
echo ================================================================
echo.
if "%HAWS_NO_PAUSE%"=="" pause
