# neolab_bridge.ps1
# Deterministic bridge: NEO -> NEO-LAB modules (PS 5.1 SAFE)
# Fixes:
# - Push-Location to ModulesRoot so relative paths (.\neo_lab.db) resolve correctly
# - Always initialize DB connection before any db_* query to avoid null DataSource
# - Safe payload property checks (no missing-property crashes)

param(
  [Parameter(Mandatory=$true)][string]$Task,            # db_init | db_stats | dist_start | neural_demo
  [string]$PayloadJson = "{}",                           # optional JSON payload
  [string]$ModulesRoot = "C:\ai_control\NEO_Stack\modules"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Load-ModuleFile {
  param([Parameter(Mandatory=$true)][string]$FileName)
  $p = Join-Path $ModulesRoot $FileName
  if (-not (Test-Path -LiteralPath $p)) { throw "Missing module file: $p" }
  Import-Module $p -Force -ErrorAction Stop
}

function Out-Json {
  param([Parameter(Mandatory=$true)]$Obj)
  $enc = New-Object System.Text.UTF8Encoding($false)
  [Console]::OutputEncoding = $enc
  Write-Output ($Obj | ConvertTo-Json -Depth 10)
}

function Parse-JsonLoose {
  param([string]$JsonText)
  if ([string]::IsNullOrWhiteSpace($JsonText)) { return $null }
  try { return ($JsonText | ConvertFrom-Json) } catch { return $null }
}

function Has-Prop {
  param(
    [Parameter(Mandatory=$true)]$Obj,
    [Parameter(Mandatory=$true)][string]$Name
  )
  if ($null -eq $Obj) { return $false }
  return ($Obj.PSObject.Properties.Match($Name).Count -gt 0)
}

try {
  if (-not (Test-Path -LiteralPath $ModulesRoot)) { throw "ModulesRoot not found: $ModulesRoot" }

  Push-Location -LiteralPath $ModulesRoot
  try {
    Load-ModuleFile "Neo-Database.psm1"
    Load-ModuleFile "Neo-Distributed.psm1"
    Load-ModuleFile "Neo-NeuralNetwork.psm1"

    $payload = Parse-JsonLoose $PayloadJson

    switch ($Task.ToLowerInvariant()) {

      "db_init" {
        if (-not (Get-Command Initialize-DatabaseConnection -ErrorAction SilentlyContinue)) {
          throw "DB function missing: Initialize-DatabaseConnection"
        }
        if (-not (Get-Command Initialize-DatabaseSchema -ErrorAction SilentlyContinue)) {
          throw "DB function missing: Initialize-DatabaseSchema"
        }

        Initialize-DatabaseConnection | Out-Null
        Initialize-DatabaseSchema | Out-Null

        Out-Json @{ ok=$true; task="db_init"; msg="DB initialized (connection + schema)"; cwd=(Get-Location).Path }
        exit 0
      }

      "db_stats" {
        # Ensure connection exists so DataSource is never null.
        if (Get-Command Initialize-DatabaseConnection -ErrorAction SilentlyContinue) {
          Initialize-DatabaseConnection | Out-Null
        }

        $patterns = @()
        $anoms = @()
        $metrics = @()

        if (Get-Command Get-Patterns -ErrorAction SilentlyContinue) { $patterns = @(Get-Patterns) }
        if (Get-Command Get-Anomalies -ErrorAction SilentlyContinue) { $anoms = @(Get-Anomalies) }
        if (Get-Command Get-MetricsHistory -ErrorAction SilentlyContinue) {
          $n = 10
          if (Has-Prop $payload "lastN") { $n = [int]$payload.lastN }
          $metrics = @(Get-MetricsHistory -LastN $n)
        }

        Out-Json @{
          ok = $true
          task = "db_stats"
          cwd = (Get-Location).Path
          patterns_count = $patterns.Count
          anomalies_count = $anoms.Count
          metrics_count = $metrics.Count
          metrics_sample = ($metrics | Select-Object -First 3)
        }
        exit 0
      }

      "dist_start" {
        if (-not (Get-Command Start-NeoNode -ErrorAction SilentlyContinue)) {
          throw "Distributed function missing: Start-NeoNode"
        }
        $node = $env:COMPUTERNAME
        if (Has-Prop $payload "node_name") { $node = [string]$payload.node_name }

        Start-NeoNode -NodeName $node | Out-Null

        Out-Json @{ ok=$true; task="dist_start"; node_name=$node; msg="Distributed demo executed"; cwd=(Get-Location).Path }
        exit 0
      }

      "neural_demo" {
        if (-not (Get-Command Invoke-NeoNeuralTrainDemo -ErrorAction SilentlyContinue)) {
          throw "Neural function missing: Invoke-NeoNeuralTrainDemo"
        }
        Invoke-NeoNeuralTrainDemo | Out-Null
        Out-Json @{ ok=$true; task="neural_demo"; msg="Neural demo executed"; cwd=(Get-Location).Path }
        exit 0
      }

      default {
        throw "Unknown Task: $Task (allowed: db_init, db_stats, dist_start, neural_demo)"
      }
    }

  } finally {
    Pop-Location
  }

} catch {
  Out-Json @{
    ok = $false
    task = $Task
    error = $_.Exception.Message
  }
  exit 1
}

