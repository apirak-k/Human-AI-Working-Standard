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

REM Detect First-Time Installation vs Routine Sync
set "IS_FIRST_RUN="
if not exist "%USERPROFILE%\.haws_manifest" set "IS_FIRST_RUN=1"
where git >nul 2>&1
if not errorlevel 1 (
    git config core.hooksPath >nul 2>&1
    if errorlevel 1 set "IS_FIRST_RUN=1"
)

if defined IS_FIRST_RUN goto :DO_SETUP

echo [*] Running HAWS Universal Sync: Second Brain, Skills, Environments...
echo.
"%BASH_CMD%" haws.sh sync %*
if errorlevel 1 goto :FAIL

echo.
echo [*] Verifying System Health: 11-Axis Diagnostics...
echo.
"%BASH_CMD%" haws.sh doctor
if errorlevel 1 goto :FAIL
goto :SUCCESS

:DO_SETUP
echo [*] First-time setup detected. Starting HAWS Interactive Setup...
echo.
"%BASH_CMD%" haws.sh setup %*
if errorlevel 1 goto :FAIL

:SUCCESS

echo.
echo ================================================================
echo   [PASS] 100%% Green - HAWS is fully updated, synced, and ready!
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
