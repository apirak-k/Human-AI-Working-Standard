@echo off
setlocal

set "HAWS_BASH=C:\Program Files\Git\bin\bash.exe"
set "HAWS_SCRIPT=%~dp0haws.sh"

echo [HAWS] Starting from %~dp0
if not exist "%HAWS_BASH%" (
  echo [HAWS] Blocked: Git for Windows was not found at:
  echo        %HAWS_BASH%
  echo [HAWS] Install Git for Windows, then run this file again.
  exit /b 1
)
if not exist "%HAWS_SCRIPT%" (
  echo [HAWS] Blocked: haws.sh was not found next to haws.bat.
  exit /b 1
)

echo [HAWS] Loading settings and skills catalog...
"%HAWS_BASH%" "%HAWS_SCRIPT%" %*
set "HAWS_EXIT=%ERRORLEVEL%"
if not "%HAWS_EXIT%"=="0" echo [HAWS] Stopped with exit code %HAWS_EXIT%.
exit /b %HAWS_EXIT%
