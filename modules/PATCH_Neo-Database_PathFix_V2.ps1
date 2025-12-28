# PATCH_Neo-Database_PathFix_V2.ps1
# Marker-free patch for Neo-Database.psm1:
# - Anchor SQLite DB to module directory ($PSScriptRoot\neo_lab.db)
# - Ensure Invoke-NeoQuery never passes null DataSource
# - PS 5.1 safe, UTF-8 no BOM writeback

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$target = "C:\ai_control\NEO_Stack\modules\Neo-Database.psm1"
if (-not (Test-Path -LiteralPath $target)) { throw "Missing: $target" }

$raw = Get-Content -LiteralPath $target -Raw

# 1) Force SQLitePath assignment to be module-local (covers common patterns)
# Replace any line like: SQLitePath = ".\neo_lab.db"
$raw = [regex]::Replace(
  $raw,
  '(^\s*SQLitePath\s*=\s*)"[^"]*neo_lab\.db"\s*$',
  '$1(Join-Path $PSScriptRoot "neo_lab.db")',
  [System.Text.RegularExpressions.RegexOptions]::Multiline
)

# 2) If script:DbConfig exists, ensure it defaults to module-local sqlite path.
# Insert a small helper at the top of file after Set-StrictMode (or near top).
if ($raw -notmatch 'function\s+Resolve-NeoDbPath') {
  $helper = @'
function Resolve-NeoDbPath {
  # Ensure SQLite uses module-local DB file regardless of current working directory
  try {
    if ($script:DbConfig -and $script:DbConfig.Provider -eq "SQLite") {
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
  } catch {
    # fail closed upstream; do not swallow structural errors
    throw
  }
}
'@

  # Insert after Set-StrictMode line if present, else prepend.
  $m = [regex]::Match($raw, 'Set-StrictMode\s+-Version\s+Latest\s*\r?\n')
  if ($m.Success) {
    $idx = $m.Index + $m.Length
    $raw = $raw.Insert($idx, "`r`n$helper`r`n")
  } else {
    $raw = $helper + "`r`n" + $raw
  }
}

# 3) Ensure Initialize-DatabaseConnection calls Resolve-NeoDbPath early
$raw = [regex]::Replace(
  $raw,
  '(function\s+Initialize-DatabaseConnection\b[\s\S]*?\{)',
  '$1' + "`r`n  Resolve-NeoDbPath",
  1
)

# 4) Ensure Invoke-NeoQuery calls Resolve-NeoDbPath AND uses non-null DataSource
# Add Resolve-NeoDbPath at function start
$raw = [regex]::Replace(
  $raw,
  '(function\s+Invoke-NeoQuery\b[\s\S]*?\{)',
  '$1' + "`r`n  Resolve-NeoDbPath",
  1
)

# Replace "-DataSource $something" where $something might be $null, with a safe fallback:
# If DataSource is null/empty, use $script:DbConfig.SQLitePath or ConnectionString.
# We do this by injecting a guard variable right before the first call to Invoke-SqliteQuery.
if ($raw -notmatch '\$neoDbDataSourceGuard') {
  $raw = [regex]::Replace(
    $raw,
    '(Invoke-SqliteQuery)',
    '$neoDbDataSourceGuard = $null' + "`r`n" +
    '  if ($script:DbConfig -and $script:DbConfig.Provider -eq "SQLite") {' + "`r`n" +
    '    if (-not [string]::IsNullOrWhiteSpace($script:DbConfig.SQLitePath)) { $neoDbDataSourceGuard = $script:DbConfig.SQLitePath }' + "`r`n" +
    '    elseif (-not [string]::IsNullOrWhiteSpace($script:DbConfig.ConnectionString)) { $neoDbDataSourceGuard = $script:DbConfig.ConnectionString }' + "`r`n" +
    '  }' + "`r`n" +
    '  if ([string]::IsNullOrWhiteSpace($neoDbDataSourceGuard)) { $neoDbDataSourceGuard = (Join-Path $PSScriptRoot "neo_lab.db") }' + "`r`n" +
    '  Invoke-SqliteQuery',
    1
  )
}

# Replace any "-DataSource $X" inside Invoke-NeoQuery with "-DataSource $neoDbDataSourceGuard"
# Limit replacement to reduce unintended changes.
$raw = [regex]::Replace(
  $raw,
  '(-DataSource\s+)\$[A-Za-z0-9_:]+',
  '${1}$neoDbDataSourceGuard',
  [System.Text.RegularExpressions.RegexOptions]::None,
  3
)

# Write back UTF-8 no BOM
$enc = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($target, $raw, $enc)

Write-Host "PATCH OK: Neo-Database.psm1 hardened for module-local SQLite and non-null DataSource." -ForegroundColor Green

