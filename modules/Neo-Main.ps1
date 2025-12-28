
# ============================================================
# Neo-Main.ps1
# Main orchestration entrypoint for Neo modules (PS 5.1 SAFE)
# ============================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ----------------------------
# Paths
# ----------------------------
$script:Root      = $PSScriptRoot
$script:LogPath   = Join-Path $script:Root "logs"
$script:DataPath  = Join-Path $script:Root "data"
$script:CfgPath   = Join-Path $script:Root "config"

foreach ($p in @($script:LogPath, $script:DataPath, $script:CfgPath)) {
    if (-not (Test-Path -LiteralPath $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
}

# ----------------------------
# Logging
# ----------------------------
function Write-NeoLog {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet("INFO","WARN","ERROR")][string]$Level = "INFO"
    )
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[{0}] [{1}] {2}" -f $ts, $Level, $Message
    Add-Content -Path (Join-Path $script:LogPath "neo.log") -Value $line
    Write-Host $line
}

# ----------------------------
# Import modules by PATH (no name ambiguity)
# ----------------------------
function Import-NeoModuleFile {
    param([Parameter(Mandatory=$true)][string]$FileName)

    $path = Join-Path $script:Root $FileName
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Module file not found: $path"
    }
    Import-Module $path -Force -ErrorAction Stop
    Write-NeoLog ("Imported module: {0}" -f $FileName) "INFO"
}

try {
    Import-NeoModuleFile "Neo-Database.psm1"
    Import-NeoModuleFile "Neo-Distributed.psm1"
    Import-NeoModuleFile "Neo-NeuralNetwork.psm1"
} catch {
    Write-NeoLog ("Module import failure: {0}" -f $_.Exception.Message) "ERROR"
    exit 1
}

# ----------------------------
# Config (local demo config for Neo-Main only)
# ----------------------------
function Get-NeoConfig {
    $cfgFile = Join-Path $script:CfgPath "neo.config.json"
    if (-not (Test-Path -LiteralPath $cfgFile)) {
        $default = @{
            node_name   = $env:COMPUTERNAME
            mode        = "local"
            max_workers = 2
        } | ConvertTo-Json -Depth 10

        $enc = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($cfgFile, $default, $enc)
        Write-NeoLog "Created default config: $cfgFile" "WARN"
    }
    return (Get-Content -LiteralPath $cfgFile -Raw | ConvertFrom-Json)
}

$cfg = Get-NeoConfig
Write-NeoLog ("Config loaded: node_name={0} mode={1} max_workers={2}" -f $cfg.node_name, $cfg.mode, $cfg.max_workers) "INFO"

# ----------------------------
# Menu
# ----------------------------
function Show-NeoMenu {
    Write-Host ""
    Write-Host "NEO MAIN MENU"
    Write-Host "1) DB: Initialize (Connection + Schema)"
    Write-Host "2) DB: Quick Stats (patterns/anomalies/metrics)"
    Write-Host "3) Distributed: Start Node (demo)"
    Write-Host "4) Neural: Train Demo"
    Write-Host "5) Exit"
    Write-Host ""
}

# ----------------------------
# Helpers for DB
# ----------------------------
function Ensure-DbReady {
    # Your DB module exports these names:
    # Initialize-DatabaseConnection, Initialize-DatabaseSchema, Get-Patterns, Get-Anomalies, Get-MetricsHistory
    if (-not (Get-Command Initialize-DatabaseConnection -ErrorAction SilentlyContinue)) {
        throw "DB module missing Initialize-DatabaseConnection (module not loaded or wrong version)."
    }
    if (-not (Get-Command Initialize-DatabaseSchema -ErrorAction SilentlyContinue)) {
        throw "DB module missing Initialize-DatabaseSchema (module not loaded or wrong version)."
    }
}

# ----------------------------
# Main Loop
# ----------------------------
while ($true) {
    Show-NeoMenu
    $choice = Read-Host "Select"

    switch ($choice) {
        "1" {
            try {
                Ensure-DbReady
                Initialize-DatabaseConnection | Out-Null
                Initialize-DatabaseSchema | Out-Null
                Write-NeoLog "DB initialized: connection + schema OK." "INFO"
            } catch {
                Write-NeoLog ("DB init error: {0}" -f $_.Exception.Message) "ERROR"
            }
        }

        "2" {
            try {
                # If schema not created yet, this will error—so user can run option 1 first.
                $patterns = @()
                $anoms = @()
                $metrics = @()

                if (Get-Command Get-Patterns -ErrorAction SilentlyContinue) {
                    $patterns = @(Get-Patterns)
                }
                if (Get-Command Get-Anomalies -ErrorAction SilentlyContinue) {
                    $anoms = @(Get-Anomalies)
                }
                if (Get-Command Get-MetricsHistory -ErrorAction SilentlyContinue) {
                    $metrics = @(Get-MetricsHistory -LastN 10)
                }

                $out = [pscustomobject]@{
                    provider           = "from DB module config"
                    patterns_count     = $patterns.Count
                    anomalies_count    = $anoms.Count
                    metrics_lastN      = $metrics.Count
                    metrics_sample     = ($metrics | Select-Object -First 3)
                }

                Write-Host ($out | ConvertTo-Json -Depth 10)
            } catch {
                Write-NeoLog ("DB stats error: {0}" -f $_.Exception.Message) "ERROR"
            }
        }

        "3" {
            try {
                # Your current Neo-Distributed exports Start-NeoNode without -MaxWorkers.
                if (-not (Get-Command Start-NeoNode -ErrorAction SilentlyContinue)) {
                    throw "Distributed module missing Start-NeoNode (module not loaded or wrong version)."
                }
                Start-NeoNode -NodeName $cfg.node_name | Out-Null
                Write-NeoLog "Distributed node started (demo)." "INFO"
            } catch {
                Write-NeoLog ("Node start error: {0}" -f $_.Exception.Message) "ERROR"
            }
        }

        "4" {
            try {
                Invoke-NeoNeuralTrainDemo
                Write-NeoLog "Neural demo completed." "INFO"
            } catch {
                Write-NeoLog ("Neural demo error: {0}" -f $_.Exception.Message) "ERROR"
            }
        }

        "5" {
            Write-NeoLog "Exit requested." "INFO"
            break
        }

        default {
            Write-NeoLog "Invalid selection." "WARN"
        }
    }
}

Write-NeoLog "NEO MAIN EXIT" "INFO"
