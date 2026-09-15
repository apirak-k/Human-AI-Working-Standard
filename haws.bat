@echo off
rem ============================================================================
rem HAWS (Human-AI Working Standard) - Windows launcher
rem Locates Bash and delegates to the shared haws.sh command engine.
rem ============================================================================
setlocal
title HAWS — Human-AI Working Standard

set "HAWS_DIR=%~dp0"
set "HAWS_SCRIPT=%HAWS_DIR%haws.sh"
set "HAWS_BARE=0"
set "HAWS_PAUSE=0"
if "%~1"=="" set "HAWS_BARE=1"
rem Keep a double-click window open so launcher errors and completion status are visible.
if "%HAWS_BARE%"=="1" set "HAWS_PAUSE=1"
if /i "%~1"=="sync" set "HAWS_PAUSE=1"

if not exist "%HAWS_SCRIPT%" (
    echo [ERROR] haws.sh was not found at "%HAWS_SCRIPT%".
    echo Please make sure haws.bat is inside the HAWS repository root.
    call :maybe_pause
    exit /b 1
)

set "BASH_CMD="
if not defined BASH_CMD if exist "%ProgramFiles%\Git\bin\bash.exe" set "BASH_CMD=%ProgramFiles%\Git\bin\bash.exe"
if not defined BASH_CMD if exist "%ProgramFiles(x86)%\Git\bin\bash.exe" set "BASH_CMD=%ProgramFiles(x86)%\Git\bin\bash.exe"
if not defined BASH_CMD if exist "%ProgramFiles%\Git\usr\bin\bash.exe" set "BASH_CMD=%ProgramFiles%\Git\usr\bin\bash.exe"
if not defined BASH_CMD if exist "%LocalAppData%\Programs\Git\bin\bash.exe" set "BASH_CMD=%LocalAppData%\Programs\Git\bin\bash.exe"
if not defined BASH_CMD if exist "%USERPROFILE%\scoop\apps\git\current\bin\bash.exe" set "BASH_CMD=%USERPROFILE%\scoop\apps\git\current\bin\bash.exe"
if not defined BASH_CMD if exist "%ProgramData%\chocolatey\bin\bash.exe" set "BASH_CMD=%ProgramData%\chocolatey\bin\bash.exe"
if not defined BASH_CMD where bash >nul 2>&1 && bash -c "command -v cygpath >/dev/null 2>&1" >nul 2>&1 && set "BASH_CMD=bash"

if not defined BASH_CMD (
    echo [ERROR] Git Bash was not found in PATH or standard installation locations.
    echo HAWS requires Git Bash or another compatible Bash runtime.
    echo Please install Git for Windows from: https://git-scm.com/
    call :maybe_pause
    exit /b 1
)

cd /d "%HAWS_DIR%"
if "%~1"=="" (
    set "HAWS_BARE_LAUNCH=1"
    "%BASH_CMD%" -c "export PATH=/usr/bin:/bin:$PATH; exec bash \"$0\" \"$@\"" "%HAWS_SCRIPT%" menu
) else (
    "%BASH_CMD%" -c "export PATH=/usr/bin:/bin:$PATH; exec bash \"$0\" \"$@\"" "%HAWS_SCRIPT%" %*
)
set "HAWS_EXIT=%ERRORLEVEL%"
call :maybe_pause
exit /b %HAWS_EXIT%

:maybe_pause
if "%HAWS_PAUSE%"=="1" if not "%HAWS_NO_PAUSE%"=="1" pause >nul
goto :eof
