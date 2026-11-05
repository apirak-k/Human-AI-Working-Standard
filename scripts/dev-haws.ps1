$ErrorActionPreference = 'Stop'

$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$GoVersion = '1.27.3'
$GoCommand = $null

function Test-GoVersion($CommandPath) {
    try {
        $VersionText = & $CommandPath version 2>$null
        if ($VersionText -match 'go([0-9]+)\.([0-9]+)') {
            return ([int]$Matches[1] -gt 1) -or ([int]$Matches[1] -eq 1 -and [int]$Matches[2] -ge 26)
        }
    } catch {}
    return $false
}

if ($env:HAWS_DEV_GO) {
    $GoCommand = $env:HAWS_DEV_GO
} else {
    $ExistingGo = Get-Command go -ErrorAction SilentlyContinue
    if ($ExistingGo -and (Test-GoVersion $ExistingGo.Source)) {
        $GoCommand = $ExistingGo.Source
    }
}

if (-not $GoCommand -or -not (Test-GoVersion $GoCommand)) {
    $Architecture = $env:PROCESSOR_ARCHITECTURE
    if ($env:PROCESSOR_ARCHITEW6432) { $Architecture = $env:PROCESSOR_ARCHITEW6432 }
    switch ($Architecture.ToUpperInvariant()) {
        'AMD64' { $GoArch = 'amd64'; $ExpectedHash = 'f26081f438319757f8a1b46d7d0b2c5ec7583d4038e485e0aa725cfde7885fff' }
        'ARM64' { $GoArch = 'arm64'; $ExpectedHash = 'c507872ff21f8a7cd3c1c217b059c6f7271a4a9d8e692810ef9dd3e1f601197c' }
        default { throw "Unsupported Windows CPU architecture: $Architecture" }
    }
    $CacheRoot = Join-Path $env:LOCALAPPDATA 'HAWS\dev\toolchains'
    $GoRoot = Join-Path $CacheRoot "go$GoVersion"
    $GoCommand = Join-Path $GoRoot 'bin\go.exe'
    if (-not (Test-Path $GoCommand -PathType Leaf)) {
        New-Item -ItemType Directory -Force -Path $CacheRoot | Out-Null
        $DownloadRoot = Join-Path $CacheRoot ([System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $DownloadRoot | Out-Null
        try {
            $Archive = Join-Path $DownloadRoot "go$GoVersion.windows-$GoArch.zip"
            $Url = "https://go.dev/dl/go$GoVersion.windows-$GoArch.zip"
            Write-Host "[HAWS dev] Downloading Go $GoVersion for Windows/$GoArch into the user cache."
            Invoke-WebRequest -Uri $Url -OutFile $Archive
            $ActualHash = (Get-FileHash -Algorithm SHA256 $Archive).Hash.ToLowerInvariant()
            if ($ActualHash -ne $ExpectedHash) { throw "Go archive SHA-256 mismatch for $(Split-Path $Archive -Leaf)" }
            Expand-Archive -LiteralPath $Archive -DestinationPath $DownloadRoot
            if (Test-Path $GoRoot) { throw "Go toolchain cache appeared during installation; inspect $GoRoot and retry" }
            Move-Item -LiteralPath (Join-Path $DownloadRoot 'go') -Destination $GoRoot
        } finally {
            Remove-Item -LiteralPath $DownloadRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

$Sandbox = $env:HAWS_DEV_HOME
if (-not $Sandbox) { $Sandbox = Join-Path $env:LOCALAPPDATA 'HAWS\development-sandbox-live' }
$env:PATH = (Split-Path $GoCommand -Parent) + ';' + $env:PATH
Push-Location $Root
try {
    & $GoCommand run ./cmd/haws-dev --source-root $Root --sandbox-root $Sandbox -- @args
    exit $LASTEXITCODE
} finally {
    Pop-Location
}
