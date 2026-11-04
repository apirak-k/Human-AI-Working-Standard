@echo off
setlocal

set "HAWS_ARCH="
if /I "%PROCESSOR_ARCHITEW6432%"=="ARM64" set "HAWS_ARCH=arm64"
if not defined HAWS_ARCH if /I "%PROCESSOR_ARCHITECTURE%"=="ARM64" set "HAWS_ARCH=arm64"
if not defined HAWS_ARCH if /I "%PROCESSOR_ARCHITEW6432%"=="AMD64" set "HAWS_ARCH=amd64"
if not defined HAWS_ARCH if /I "%PROCESSOR_ARCHITECTURE%"=="AMD64" set "HAWS_ARCH=amd64"

if not defined HAWS_ARCH (
	echo Unsupported Windows CPU architecture: %PROCESSOR_ARCHITECTURE% 1>&2
	exit /b 2
)

set "HAWS_BASE_BIN=%~dp0bin\windows-%HAWS_ARCH%\haws.exe"
if not exist "%HAWS_BASE_BIN%" (
	echo HAWS base binary not found at %HAWS_BASE_BIN% 1>&2
	exit /b 1
)
if not defined TEMP (
	echo Windows TEMP directory is unavailable; cannot resolve the active HAWS version. 1>&2
	exit /b 1
)

:choose_resolver_file
set "HAWS_RESOLVE_FILE=%TEMP%\haws-active-%RANDOM%-%RANDOM%.tmp"
if exist "%HAWS_RESOLVE_FILE%" goto choose_resolver_file

"%HAWS_BASE_BIN%" --haws-resolve-active-binary > "%HAWS_RESOLVE_FILE%"
if errorlevel 1 goto resolver_failed
set "HAWS_BIN="
set /p "HAWS_BIN="<"%HAWS_RESOLVE_FILE%"
del /q "%HAWS_RESOLVE_FILE%" >nul 2>&1
if not defined HAWS_BIN (
	echo HAWS active binary resolution returned an empty path. 1>&2
	exit /b 1
)
if not exist "%HAWS_BIN%" (
	echo HAWS active binary not found at %HAWS_BIN% 1>&2
	exit /b 1
)

"%HAWS_BIN%" %*
exit /b %ERRORLEVEL%

:resolver_failed
del /q "%HAWS_RESOLVE_FILE%" >nul 2>&1
exit /b 1
