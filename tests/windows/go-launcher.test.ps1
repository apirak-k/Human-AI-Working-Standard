$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$sourceLauncher = Join-Path $repoRoot 'launchers\windows\haws.bat'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("haws-launcher-test-" + [guid]::NewGuid().ToString('N'))
$launcherDir = Join-Path $tempRoot 'launchers\windows'
$amd64Dir = Join-Path $launcherDir 'bin\windows-amd64'
$arm64Dir = Join-Path $launcherDir 'bin\windows-arm64'
$launcher = Join-Path $launcherDir 'haws.bat'
$buildDir = Join-Path $tempRoot 'build'
$originalArchitecture = $env:PROCESSOR_ARCHITECTURE
$originalWowArchitecture = $env:PROCESSOR_ARCHITEW6432
$originalGoOs = $env:GOOS
$originalGoArch = $env:GOARCH

function Assert-True([bool]$condition, [string]$message) {
    if (-not $condition) { throw $message }
}

function Build-Haws([string]$binaryPath, [string]$arch, [string]$version) {
    $env:GOOS = 'windows'
    $env:GOARCH = $arch
    & go build -trimpath -buildvcs=false -ldflags "-X main.version=$version" -o $binaryPath ./cmd/haws
    if ($LASTEXITCODE -ne 0) { throw "go build windows/$arch failed for $version." }
}

try {
    New-Item -ItemType Directory -Force -Path $amd64Dir, $arm64Dir, $buildDir | Out-Null
    Copy-Item $sourceLauncher $launcher
    Push-Location $repoRoot
    try {
        $baseAmd64 = Join-Path $buildDir 'base-amd64.exe'
        $baseArmSelection = Join-Path $buildDir 'base-arm-selection.exe'
        $activeAmd64 = Join-Path $buildDir 'active-amd64.exe'
        $activeArm64 = Join-Path $buildDir 'active-arm64.exe'
        Build-Haws $baseAmd64 'amd64' 'launcher-amd64'
        Build-Haws $baseArmSelection 'amd64' 'launcher-arm-selection'
        Build-Haws $activeAmd64 'amd64' 'active-amd64'
        Build-Haws $activeArm64 'arm64' 'active-arm64'
    }
    finally {
        Pop-Location
    }

    Copy-Item $baseAmd64 (Join-Path $amd64Dir 'haws.exe')
    Copy-Item $baseArmSelection (Join-Path $arm64Dir 'haws.exe')
    Remove-Item Env:PROCESSOR_ARCHITEW6432 -ErrorAction SilentlyContinue
    $env:PROCESSOR_ARCHITECTURE = 'AMD64'
    $output = & $launcher --version 2>&1 | Out-String
    Assert-True ($LASTEXITCODE -eq 0) 'AMD64 launcher should exit successfully.'
    Assert-True ($output.Contains('HAWS launcher-amd64')) 'AMD64 launcher should select its base binary.'

    $env:PROCESSOR_ARCHITECTURE = 'x86'
    $env:PROCESSOR_ARCHITEW6432 = 'ARM64'
    $output = & $launcher --version 2>&1 | Out-String
    Assert-True ($LASTEXITCODE -eq 0) 'ARM64 launcher selection should exit successfully.'
    Assert-True ($output.Contains('HAWS launcher-arm-selection')) 'Windows launcher should select the ARM64 package directory when PROCESSOR_ARCHITEW6432 is ARM64.'

    $versionDir = Join-Path $launcherDir 'versions\v1.2.3'
    $versionAmd64Dir = Join-Path $versionDir 'bin\windows-amd64'
    $versionArm64Dir = Join-Path $versionDir 'bin\windows-arm64'
    New-Item -ItemType Directory -Force -Path $versionAmd64Dir, $versionArm64Dir | Out-Null
    Copy-Item $activeAmd64 (Join-Path $versionAmd64Dir 'haws.exe')
    Copy-Item $activeArm64 (Join-Path $versionArm64Dir 'haws.exe')
    $versionManifest = @{
        version = 'v1.2.3'
        platform = 'windows'
        archive_sha256 = ('0' * 64)
        binaries = @{
            amd64 = (Get-FileHash -Algorithm SHA256 (Join-Path $versionAmd64Dir 'haws.exe')).Hash.ToLowerInvariant()
            arm64 = (Get-FileHash -Algorithm SHA256 (Join-Path $versionArm64Dir 'haws.exe')).Hash.ToLowerInvariant()
        }
    } | ConvertTo-Json -Depth 4
    Set-Content -Encoding ascii -Path (Join-Path $versionDir 'install.json') -Value $versionManifest
    Set-Content -Encoding ascii -Path (Join-Path $launcherDir 'active-version') -Value @('HAWS_GO_ACTIVE_V1', 'active=v1.2.3', 'previous=base')

    $env:PROCESSOR_ARCHITECTURE = 'AMD64'
    Remove-Item Env:PROCESSOR_ARCHITEW6432 -ErrorAction SilentlyContinue
    $output = & $launcher --version 2>&1 | Out-String
    Assert-True ($LASTEXITCODE -eq 0) 'Windows launcher should run the validated active version.'
    Assert-True ($output.Contains('HAWS active-amd64')) 'Windows launcher should select the current-architecture binary from the active version.'

    Set-Content -Encoding ascii -Path (Join-Path $launcherDir 'active-version') -Value @('HAWS_GO_ACTIVE_V1', 'active=..\..\outside', 'previous=base')
    $output = & $launcher --version 2>&1 | Out-String
    Assert-True ($LASTEXITCODE -ne 0) 'Windows launcher should reject a path-like active version.'
    Assert-True ($output.Contains('active version marker')) 'Windows launcher should explain an invalid active version marker.'

    Set-Content -Encoding ascii -Path (Join-Path $launcherDir 'active-version') -Value @('HAWS_GO_ACTIVE_V1', 'active=v1.2.3', 'previous=base')
    Remove-Item (Join-Path $launcherDir 'versions') -Recurse -Force
    $outsideVersions = Join-Path $tempRoot 'outside-versions'
    New-Item -ItemType Directory -Force -Path $outsideVersions | Out-Null
    New-Item -ItemType Junction -Path (Join-Path $launcherDir 'versions') -Target $outsideVersions | Out-Null
    $output = & $launcher --version 2>&1 | Out-String
    Assert-True ($LASTEXITCODE -ne 0) 'Windows launcher should reject a junction in the active-version path.'
    Assert-True ($output.Contains('active HAWS app version is invalid')) 'Windows launcher should explain that the active package path is not owned.'
    Remove-Item -LiteralPath (Join-Path $launcherDir 'versions') -Force

    Set-Content -Encoding ascii -Path (Join-Path $launcherDir 'active-version') -Value @('HAWS_GO_ACTIVE_V1', 'active=v1.2.3', 'previous=base')
    $env:PROCESSOR_ARCHITECTURE = 'IA64'
    $output = & $launcher --version 2>&1 | Out-String
    Assert-True ($LASTEXITCODE -ne 0) 'Unsupported Windows architecture should fail.'
    Assert-True ($output.Contains('Unsupported Windows CPU architecture')) 'Unsupported architecture should explain the failure.'

    Remove-Item (Join-Path $amd64Dir 'haws.exe')
    $env:PROCESSOR_ARCHITECTURE = 'AMD64'
    $output = & $launcher --version 2>&1 | Out-String
    Assert-True ($LASTEXITCODE -ne 0) 'A missing base package binary should fail.'
    Assert-True ($output.Contains('HAWS base binary not found')) 'A missing base binary should explain the failure.'

    Write-Output 'PASS: Windows launcher selects CPU packages, resolves verified active versions, and rejects invalid or junction-based paths.'
}
finally {
    if ($null -eq $originalArchitecture) { Remove-Item Env:PROCESSOR_ARCHITECTURE -ErrorAction SilentlyContinue }
    else { $env:PROCESSOR_ARCHITECTURE = $originalArchitecture }
    if ($null -eq $originalWowArchitecture) { Remove-Item Env:PROCESSOR_ARCHITEW6432 -ErrorAction SilentlyContinue }
    else { $env:PROCESSOR_ARCHITEW6432 = $originalWowArchitecture }
    if ($null -eq $originalGoOs) { Remove-Item Env:GOOS -ErrorAction SilentlyContinue }
    else { $env:GOOS = $originalGoOs }
    if ($null -eq $originalGoArch) { Remove-Item Env:GOARCH -ErrorAction SilentlyContinue }
    else { $env:GOARCH = $originalGoArch }
    Remove-Item $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

# Several launcher checks above intentionally expect a nonzero native exit.
# Return a successful script status after all assertions and cleanup pass.
$global:LASTEXITCODE = 0
