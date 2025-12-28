# PATCH_Neo-Database_PathFix.ps1
# Fix SQLite path so DB is always module-local (PS 5.1 SAFE)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$target = "C:\ai_control\NEO_Stack\modules\Neo-Database.psm1"
if (-not (Test-Path -LiteralPath $target)) { throw "Missing: $target" }

$raw = Get-Content -LiteralPath $target -Raw

# 1) Replace relative SQLitePath with module-anchored path
$raw = $raw -replace 'SQLitePath\s*=\s*"\.\\neo_lab\.db"', 'SQLitePath       = (Join-Path $PSScriptRoot "neo_lab.db")'

# 2) Insert Resolve-NeoDbPath helper (only if not already present)
if ($raw -notmatch 'function\s+Resolve-NeoDbPath') {
    $marker = "# ============================================================`r`n# DATABASE SCHEMA"
    $i = $raw.IndexOf($marker)
    if ($i -lt 0) { throw "Marker not found: DATABASE SCHEMA" }

    $helper = @'
# ============================================================
# PATH RESOLUTION (deterministic)
# Ensures SQLitePath / ConnectionString are never null and are
# anchored to this module directory (not the current working dir).
# ============================================================
function Resolve-NeoDbPath {
    if ($script:DbConfig.Provider -ne "SQLite") { return }

    if ([string]::IsNullOrWhiteSpace($script:DbConfig.SQLitePath)) {
        $script:DbConfig.SQLitePath = (Join-Path $PSScriptRoot "neo_lab.db")
    }

    if (-not [System.IO.Path]::IsPathRooted($script:DbConfig.SQLitePath)) {
        $script:DbConfig.SQLitePath = (Join-Path $PSScriptRoot $script:DbConfig.SQLitePath)
    }

    if ([string]::IsNullOrWhiteSpace($script:DbConfig.ConnectionString)) {
        $script:DbConfig.ConnectionString = $script:DbConfig.SQLitePath
    }
}
'@

    $raw = $raw.Substring(0, $i) + $helper + "`r`n" + $raw.Substring($i)
}

# 3) Ensure Initialize-DatabaseConnection calls Resolve-NeoDbPath
if ($raw -match 'function\s+Initialize-DatabaseConnection') {
    if ($raw -notmatch 'function\s+Initialize-DatabaseConnection[\s\S]*?Resolve-NeoDbPath') {
        $raw = $raw -replace '(function\s+Initialize-DatabaseConnection[\s\S]*?\r?\n\s*try\s*\{\s*\r?\n)',
                              '$1        Resolve-NeoDbPath' + "`r`n`r`n"
    }
}

# 4) Ensure Invoke-NeoQuery calls Resolve-NeoDbPath
if ($raw -match 'function\s+Invoke-NeoQuery') {
    if ($raw -notmatch 'function\s+Invoke-NeoQuery[\s\S]*?Resolve-NeoDbPath') {
        $raw = $raw -replace '(function\s+Invoke-NeoQuery[\s\S]*?\r?\n\s*try\s*\{\s*\r?\n)',
                              '$1        Resolve-NeoDbPath' + "`r`n`r`n"
    }
}

# Write back UTF-8 (no BOM)
$enc = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($target, $raw, $enc)

Write-Host "PATCH OK: Neo-Database.psm1 path fix applied." -ForegroundColor Green
