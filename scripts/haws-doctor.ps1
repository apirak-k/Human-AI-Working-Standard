<#
.SYNOPSIS
    HAWS Doctor PowerShell Wrapper (Windows)
.DESCRIPTION
    Runs the HAWS system diagnostics utility (haws_doctor.py) using the local Python 3 interpreter.
#>
[CmdletBinding()]
param(
    [switch]$Json,
    [switch]$VerboseOutput,
    [switch]$NoColor,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArgs
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptDir
$pythonScript = Join-Path $scriptDir "haws_doctor.py"

# Locate Python 3 interpreter
$pythonCmd = $null
if (Get-Command py -ErrorAction SilentlyContinue) {
    $pythonCmd = "py"
    $pythonArgs = @("-3", $pythonScript, "--repo-root", $repoRoot)
} elseif (Get-Command python3 -ErrorAction SilentlyContinue) {
    $pythonCmd = "python3"
    $pythonArgs = @($pythonScript, "--repo-root", $repoRoot)
} elseif (Get-Command python -ErrorAction SilentlyContinue) {
    $isPy3 = & python -c "import sys; sys.exit(0 if sys.version_info[0] >= 3 else 1)" 2>$null
    if ($LASTEXITCODE -eq 0) {
        $pythonCmd = "python"
        $pythonArgs = @($pythonScript, "--repo-root", $repoRoot)
    }
}

if (-not $pythonCmd) {
    Write-Error "Python 3 is required to run haws doctor but was not found in PATH."
    exit 1
}

if ($Json) { $pythonArgs += "--json" }
if ($VerboseOutput) { $pythonArgs += "--verbose" }
if ($NoColor) { $pythonArgs += "--no-color" }

if ($RemainingArgs) {
    foreach ($arg in $RemainingArgs) {
        if ($arg -in @("-Json", "-json", "--json", "-j")) {
            if ("--json" -notin $pythonArgs) { $pythonArgs += "--json" }
        } elseif ($arg -in @("-VerboseOutput", "-verbose", "--verbose", "-v")) {
            if ("--verbose" -notin $pythonArgs) { $pythonArgs += "--verbose" }
        } elseif ($arg -in @("-NoColor", "-no-color", "--no-color")) {
            if ("--no-color" -notin $pythonArgs) { $pythonArgs += "--no-color" }
        } else {
            $pythonArgs += $arg
        }
    }
}

& $pythonCmd @pythonArgs
exit $LASTEXITCODE
