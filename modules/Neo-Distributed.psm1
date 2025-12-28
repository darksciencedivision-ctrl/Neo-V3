# ============================================================
# Neo-Distributed.psm1
# Distributed processing and node management (SAFE / PS 5.1)
# ============================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ----------------------------
# Internal State
# ----------------------------
$script:NeoNodeRegistry = @{}
$script:NeoWorkQueue = New-Object System.Collections.ArrayList

function Write-DistributedLog {
    param(
        [string]$Message,
        [ValidateSet("INFO","WARN","ERROR")]$Level = "INFO"
    )
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$ts][$Level] $Message"
}

# ----------------------------
# Node Registry
# ----------------------------
function Register-NeoNode {
    param(
        [Parameter(Mandatory)][string]$NodeName,
        [string]$Address = "localhost",
        [int]$Port = 0,
        [int]$MaxWorkers = 1
    )

    $node = [pscustomobject]@{
        NodeName   = $NodeName
        Address    = $Address
        Port       = $Port
        Status     = "online"
        MaxWorkers = $MaxWorkers
        LastSeen   = Get-Date
    }

    $script:NeoNodeRegistry[$NodeName] = $node
    Write-DistributedLog "Registered node $NodeName"
    return $node
}

function Get-NeoNodes {
    return $script:NeoNodeRegistry.Values
}

# ----------------------------
# Work Queue
# ----------------------------
function Enqueue-NeoWork {
    param(
        [Parameter(Mandatory)][string]$WorkType,
        [Parameter(Mandatory)][hashtable]$Payload,
        [string]$TargetNode = ""
    )

    $item = [pscustomobject]@{
        Id         = [Guid]::NewGuid().ToString("N")
        WorkType   = $WorkType
        Payload    = $Payload
        TargetNode = $TargetNode
        Status     = "queued"
        CreatedAt = Get-Date
        Result     = $null
        Error      = $null
    }

    [void]$script:NeoWorkQueue.Add($item)
    Write-DistributedLog "Queued work $($item.Id) type=$WorkType"
    return $item
}

function Get-NeoWorkQueue {
    return $script:NeoWorkQueue
}

# ----------------------------
# Dispatcher (Demo)
# ----------------------------
function Invoke-NeoWorkDispatcher {
    foreach ($item in $script:NeoWorkQueue | Where-Object { $_.Status -eq "queued" }) {
        try {
            $item.Status = "running"
            switch ($item.WorkType) {
                "echo" {
                    $item.Result = $item.Payload.message
                }
                "add" {
                    $item.Result = ($item.Payload.a + $item.Payload.b)
                }
                default {
                    throw "Unknown work type"
                }
            }
            $item.Status = "completed"
            Write-DistributedLog "Completed work $($item.Id)"
        }
        catch {
            $item.Status = "failed"
            $item.Error  = $_.Exception.Message
            Write-DistributedLog "Work failed $($item.Id)" "ERROR"
        }
    }
}

function Start-NeoNode {
    param(
        [Parameter(Mandatory)][string]$NodeName
    )

    Register-NeoNode -NodeName $NodeName | Out-Null
    Enqueue-NeoWork -WorkType "echo" -Payload @{ message = "hello from $NodeName" } | Out-Null
    Enqueue-NeoWork -WorkType "add"  -Payload @{ a = 1; b = 2 } | Out-Null
    Invoke-NeoWorkDispatcher
}

Export-ModuleMember -Function `
    Register-NeoNode, Get-NeoNodes, `
    Enqueue-NeoWork, Get-NeoWorkQueue, `
    Invoke-NeoWorkDispatcher, Start-NeoNode
