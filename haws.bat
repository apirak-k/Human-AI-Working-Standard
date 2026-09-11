@echo off
@rem ==============================================================================
@rem HAWS (Human-AI Working Standard) - Windows Native Launcher
@rem Thin launcher: locates Bash runtime and delegates to haws.sh
@rem ==============================================================================
setlocal EnableDelayedExpansion

set "HAWS_DIR=%~dp0"
set "HAWS_SCRIPT=%HAWS_DIR%haws.sh"

if not exist "%HAWS_SCRIPT%" (
    echo [ERROR] haws.sh was not found at "%HAWS_SCRIPT%".
    echo Please make sure haws.bat is placed inside the HAWS repository root.
    exit /b 1
)

REM Locate Bash executable
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
    echo [ERROR] Git Bash was not found in PATH or standard installation locations.
    echo HAWS requires Git Bash or MSYS2 on Windows.
    echo Please install Git for Windows from: https://git-scm.com/
    exit /b 1
)

REM Forward all arguments directly to shared haws.sh core
cd /d "%HAWS_DIR%"
"%BASH_CMD%" "%HAWS_SCRIPT%" %*
set "HAWS_EXIT=%ERRORLEVEL%"

exit /b %HAWS_EXIT%
