$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$sourceLauncher = Join-Path $repoRoot 'launchers\windows\haws.bat'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("haws-launcher-test-" + [guid]::NewGuid().ToString('N'))
$launcherDir = Join-Path $tempRoot 'launchers\windows'
$amd64Dir = Join-Path $launcherDir 'bin\windows-amd64'
$arm64Dir = Join-Path $launcherDir 'bin\windows-arm64'
$launcher = Join-Path $launcherDir 'haws.bat'
$originalArchitecture = $env:PROCESSOR_ARCHITECTURE
$originalWowArchitecture = $env:PROCESSOR_ARCHITEW6432

function Assert-True([bool]$condition, [string]$message) {
    if (-not $condition) { throw $message }
}

try {
    New-Item -ItemType Directory -Force -Path $amd64Dir, $arm64Dir | Out-Null
    Copy-Item $sourceLauncher $launcher
    Copy-Item $env:ComSpec (Join-Path $amd64Dir 'haws.exe')
    Copy-Item $env:ComSpec (Join-Path $arm64Dir 'haws.exe')

    Remove-Item Env:PROCESSOR_ARCHITEW6432 -ErrorAction SilentlyContinue
    $env:PROCESSOR_ARCHITECTURE = 'AMD64'
    $output = & $launcher /c echo HAWS_AMD64 2>&1 | Out-String
    Assert-True ($LASTEXITCODE -eq 0) 'AMD64 launcher should exit successfully.'
    Assert-True ($output.Contains('HAWS_AMD64')) 'AMD64 launcher should invoke its package binary.'

    $env:PROCESSOR_ARCHITECTURE = 'x86'
    $env:PROCESSOR_ARCHITEW6432 = 'ARM64'
    $output = & $launcher /c echo HAWS_ARM64 2>&1 | Out-String
    Assert-True ($LASTEXITCODE -eq 0) 'ARM64 launcher should exit successfully.'
    Assert-True ($output.Contains('HAWS_ARM64')) 'ARM64 launcher should invoke the native architecture selected by PROCESSOR_ARCHITEW6432.'

    $env:PROCESSOR_ARCHITECTURE = 'IA64'
    Remove-Item Env:PROCESSOR_ARCHITEW6432 -ErrorAction SilentlyContinue
    $output = & $launcher 2>&1 | Out-String
    Assert-True ($LASTEXITCODE -ne 0) 'Unsupported Windows architecture should fail.'
    Assert-True ($output.Contains('Unsupported Windows CPU architecture')) 'Unsupported architecture should explain the failure.'

    Remove-Item (Join-Path $amd64Dir 'haws.exe')
    $env:PROCESSOR_ARCHITECTURE = 'AMD64'
    $output = & $launcher 2>&1 | Out-String
    Assert-True ($LASTEXITCODE -ne 0) 'A missing package binary should fail.'
    Assert-True ($output.Contains('HAWS binary not found')) 'A missing binary should explain the failure.'

    Write-Output 'PASS: Windows launcher selects AMD64/ARM64 and rejects unsupported or missing binaries.'
}
finally {
    if ($null -eq $originalArchitecture) { Remove-Item Env:PROCESSOR_ARCHITECTURE -ErrorAction SilentlyContinue }
    else { $env:PROCESSOR_ARCHITECTURE = $originalArchitecture }
    if ($null -eq $originalWowArchitecture) { Remove-Item Env:PROCESSOR_ARCHITEW6432 -ErrorAction SilentlyContinue }
    else { $env:PROCESSOR_ARCHITEW6432 = $originalWowArchitecture }
    Remove-Item $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
