@echo off
setlocal EnableDelayedExpansion
title HAWS 1-Click Universal Sync ^& System Update

echo ================================================================
echo           HAWS 1-Click Universal Sync ^& System Update
echo ================================================================
echo.
echo [*] Initializing HAWS One-Click Sync engine...
echo [*] Preparing runtime environment...
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

echo [*] Running HAWS Universal Sync: Second Brain, Skills, Environments...
echo.
"%BASH_CMD%" haws.sh sync %*
if errorlevel 1 goto :FAIL

REM Ensure Git hooks are active
"%BASH_CMD%" haws.sh hook install >nul 2>&1

echo.
echo [*] Verifying System Health: 11-Axis Diagnostics (40-Point Integrity Check)...
echo.
"%BASH_CMD%" haws.sh doctor
if errorlevel 1 goto :FAIL
goto :SUCCESS

:SUCCESS

echo.
echo ================================================================
echo   [PASS] System Fully Verified ^& Ready!
echo ================================================================
echo.
if "%HAWS_NO_PAUSE%"=="" pause
exit /b 0

:FAIL
echo.
echo ================================================================
echo   [FAIL] HAWS process encountered an error!
echo   Please review the diagnostic logs or output above.
echo ================================================================
echo.
if "%HAWS_NO_PAUSE%"=="" pause
exit /b 1
