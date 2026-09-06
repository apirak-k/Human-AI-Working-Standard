@echo off
setlocal EnableDelayedExpansion
title HAWS 1-Click Clean Uninstaller

echo ================================================================
echo             HAWS 1-Click Clean Uninstaller
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

echo [*] Generating Dry-Run Inspection Preview...
echo.
"%BASH_CMD%" haws.sh uninstall --dry-run
echo.

echo ================================================================
echo  [SAFETY GUARD] Uninstallation will detach global AI pointers,
echo  linked skills, subagents, and Git hooks.
echo.
echo  Your project code and Second Brain will NOT be deleted.
echo ================================================================
echo.

set "CONFIRM="
set "CONFIRM_CLEAN="
if not "%~1"=="" (
    set "CONFIRM=%~1"
) else (
    set /p "CONFIRM=Do you really want to proceed with uninstallation? (y/N): "
)
if defined CONFIRM (
    for /f "tokens=* delims= " %%a in ("!CONFIRM!") do set "CONFIRM_CLEAN=%%a"
)
if /i "!CONFIRM_CLEAN!"=="ECHO is on." set "CONFIRM_CLEAN="
if /i "!CONFIRM_CLEAN!"=="ECHO is off." set "CONFIRM_CLEAN="

if /i "!CONFIRM_CLEAN!"=="y" (
    echo.
    echo [*] Executing Clean Uninstallation...
    echo.
    "%BASH_CMD%" haws.sh uninstall --yes
    if errorlevel 1 (
        echo.
        echo ================================================================
        echo  [ERROR] Uninstallation failed or encountered errors.
        echo ================================================================
        echo.
        if "%HAWS_NO_PAUSE%"=="" pause
        exit /b 1
    )
    echo.
    echo ================================================================
    echo   Uninstallation complete. Machine restored to pre-HAWS state.
    echo   To re-enable HAWS at any time, run 1-CLICK-SYNC.bat.
    echo ================================================================
) else (
    echo.
    echo [INFO] Uninstallation cancelled. No changes were made.
)

echo.
if "%HAWS_NO_PAUSE%"=="" pause
exit /b 0
