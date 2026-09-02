<#
.SYNOPSIS
    HAWS Unified CLI Entrypoint (PowerShell)
.DESCRIPTION
    Dispatcher for HAWS CLI subcommands:
      haws status   - Fast skill and token check
      haws doctor   - Comprehensive system diagnostics
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Command = "status",
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArgs
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

switch ($Command.ToLower()) {
    "doctor" {
        $doctorScript = Join-Path $scriptDir "haws-doctor.ps1"
        & $doctorScript @RemainingArgs
        exit $LASTEXITCODE
    }
    { $_ -in @("status", "health", "check") } {
        $statusScript = Join-Path $scriptDir "check-skills.ps1"
        & $statusScript @RemainingArgs
        exit $LASTEXITCODE
    }
    default {
        Write-Host "Usage: .\scripts\haws.ps1 [status|doctor] [options]" -ForegroundColor Cyan
        Write-Host "  status        Instant sub-second check of skill counts and tokens"
        Write-Host "  doctor        Comprehensive system diagnostics (core files, subagents, git, scripts)"
        Write-Host "  doctor -Json  Output diagnostics in JSON format"
        exit 1
    }
}
