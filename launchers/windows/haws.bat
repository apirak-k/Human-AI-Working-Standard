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

set "HAWS_BIN=%~dp0bin\windows-%HAWS_ARCH%\haws.exe"
if not exist "%HAWS_BIN%" (
	echo HAWS binary not found at %HAWS_BIN% 1>&2
	exit /b 1
)

"%HAWS_BIN%" %*
exit /b %ERRORLEVEL%
