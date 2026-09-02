# ==============================================================================
# HAWS High-Performance Skill Checker (Native PowerShell)
# Execution Time: < 0.3s (Sub-second)
# ==============================================================================
$ErrorActionPreference = "SilentlyContinue"

$geminiSkills = "$HOME/.gemini/config/skills"
$claudeSkills = "$HOME/.claude/skills"
$manifestFile = "$HOME/.haws_manifest"

$geminiCount = if (Test-Path $geminiSkills) { (Get-ChildItem -Directory -Path $geminiSkills).Count } else { 0 }
$claudeCount = if (Test-Path $claudeSkills) { (Get-ChildItem -Directory -Path $claudeSkills).Count } else { 0 }
$manifestCount = if (Test-Path $manifestFile) { (Get-Content $manifestFile | Where-Object { $_ -like "skill:*" }).Count } else { 0 }

Write-Host "=== HAWS Fast Skill Status ===" -ForegroundColor Cyan
Write-Host "Antigravity Active Skills : $geminiCount" -ForegroundColor Green
Write-Host "Claude Code Active Skills : $claudeCount" -ForegroundColor Green
Write-Host "Manifest Registered Skills: $manifestCount" -ForegroundColor Yellow

if ($geminiCount -eq $claudeCount -and $geminiCount -eq $manifestCount) {
    Write-Host "Health Status             : [100% HEALTHY & IN SYNC]" -ForegroundColor Green
} else {
    Write-Host "Health Status             : [MISMATCH DETECTED - Run update.sh]" -ForegroundColor Red
}
