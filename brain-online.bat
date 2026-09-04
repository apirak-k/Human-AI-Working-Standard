@echo off
setlocal EnableDelayedExpansion
title HAWS Second Brain Cloud Connector

echo ================================================================
echo        HAWS Second Brain Symmetrical Cloud Connector
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
    echo Please install Git for Windows or add Git to your PATH.
    pause
    exit /b 1
)

REM Check current secondbrain status via haws.sh
"%BASH_CMD%" haws.sh user status
echo.

REM Read git remote origin of secondbrain
set "REMOTE_URL="
for /f "delims=" %%i in ('git -C secondbrain remote get-url origin 2^>nul') do set "REMOTE_URL=%%i"

if "%REMOTE_URL%"=="" (
    echo [STATUS] Second Brain is currently in LOCAL-ONLY mode.
    echo.
    set "REPO_INPUT="
    set "REPO_CLEAN="
    if not "%~1"=="" (
        set "REPO_INPUT=%~1"
    ) else (
        echo To connect to your private cloud repository:
        set /p "REPO_INPUT=Enter your Private GitHub Repo URL (e.g. git@github.com:username/my-haws-brain.git): "
    )
    if defined REPO_INPUT (
        for /f "tokens=* delims= " %%a in ("!REPO_INPUT!") do set "REPO_CLEAN=%%a"
    )
    if /i "!REPO_CLEAN!"=="ECHO is on." set "REPO_CLEAN="
    if /i "!REPO_CLEAN!"=="ECHO is off." set "REPO_CLEAN="
    if defined REPO_CLEAN (
        echo.
        echo Connecting to !REPO_CLEAN!...
        "%BASH_CMD%" haws.sh user connect "!REPO_CLEAN!"
    ) else (
        echo [INFO] No URL entered. Second Brain remains in Local-Only mode.
    )
) else (
    echo ================================================================
    echo  [GUARD] WARNING: Second Brain is currently CONNECTED to:
    echo  !REMOTE_URL!
    echo ================================================================
    echo Disconnecting will return this machine to Local-Only mode.
    echo Your remote GitHub repository will NOT be deleted.
    echo.
    set "CONFIRM="
    if not "%~1"=="" (
        set "CONFIRM=%~1"
    ) else (
        set /p "CONFIRM=Do you want to disconnect? (y/N): "
    )
    if /i "!CONFIRM!"=="y" (
        echo.
        "%BASH_CMD%" haws.sh user disconnect --yes
    ) else (
        echo [INFO] Connection preserved.
    )
)

echo.
if "%HAWS_NO_PAUSE%"=="" pause