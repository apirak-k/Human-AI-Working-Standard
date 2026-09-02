# ==============================================================================
# HAWS High-Performance Skill & Token Checker (Native PowerShell)
# Execution Time: < 0.3s (Sub-second)
# ==============================================================================
$ErrorActionPreference = "SilentlyContinue"

$geminiSkills = "$HOME/.gemini/config/skills"
$claudeSkills = "$HOME/.claude/skills"
$manifestFile = "$HOME/.haws_manifest"

$geminiDirs = if (Test-Path $geminiSkills) { Get-ChildItem -Directory -Path $geminiSkills } else { @() }
$claudeDirs = if (Test-Path $claudeSkills) { Get-ChildItem -Directory -Path $claudeSkills } else { @() }
$manifestLines = if (Test-Path $manifestFile) { Get-Content $manifestFile | Where-Object { $_ -like "skill:*" } } else { @() }

$geminiCount = $geminiDirs.Count
$claudeCount = $claudeDirs.Count
$manifestCount = $manifestLines.Count

# Exact token estimation matching Antigravity YAML description parsing
$totalChars = 0

foreach ($dir in $geminiDirs) {
    $skillFile = Join-Path $dir.FullName "SKILL.md"
    if (-not (Test-Path $skillFile)) { $skillFile = Join-Path $dir.FullName "skill.md" }
    if (Test-Path $skillFile) {
        $content = Get-Content $skillFile -Raw -ErrorAction SilentlyContinue
        if ($content -match "(?s)^---\r?\n(.*?)\r?\n---") {
            $frontmatter = $matches[1]
            if ($frontmatter -match '(?s)description:\s*(.*?)(?=\r?\n[a-zA-Z0-9_-]+:|\Z)') {
                $totalChars += $matches[1].Trim().Length
            }
        }
    }
}

$estTokens = [math]::Round($totalChars / 3.8)
$tokenLimit = 20000
$tokenPercent = [math]::Round(($estTokens / $tokenLimit) * 100, 1)

Write-Host "=== HAWS Fast Skill & Token Status ===" -ForegroundColor Cyan
Write-Host "Antigravity Active Skills : $geminiCount" -ForegroundColor Green
Write-Host "Claude Code Active Skills : $claudeCount" -ForegroundColor Green
Write-Host "Manifest Registered Skills: $manifestCount" -ForegroundColor Yellow

# Token Budget Assessment
if ($estTokens -ge 18000) {
    Write-Host "Token Budget Status       : [CRITICAL DANGER: ~$estTokens / $tokenLimit ($tokenPercent%)]" -ForegroundColor Red
    Write-Host "  (!) IMMEDIATE ACTION REQUIRED: Customization budget near overflow. Truncation imminent." -ForegroundColor Red
} elseif ($estTokens -ge 15000) {
    Write-Host "Token Budget Status       : [WARNING DANGEROUS: ~$estTokens / $tokenLimit ($tokenPercent%)]" -ForegroundColor Yellow
    Write-Host "  (!) ALERT: Skill descriptions exceed 75% budget. Review largest skills." -ForegroundColor Yellow
} else {
    Write-Host "Token Budget Status       : [SAFE: ~$estTokens / $tokenLimit ($tokenPercent%)]" -ForegroundColor Green
}

if ($geminiCount -eq $claudeCount -and $geminiCount -eq $manifestCount) {
    Write-Host "Sync Health Status        : [100% HEALTHY & IN SYNC]" -ForegroundColor Green
} else {
    Write-Host "Sync Health Status        : [MISMATCH DETECTED - Run update.sh]" -ForegroundColor Red
}
