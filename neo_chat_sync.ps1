# C:\ai_control\NEO_Stack\neo_chat_sync.ps1
# NEO CHAT SYNC (queue_v2) - Windows PowerShell 5.1 SAFE (ASCII)
# Purpose:
# - Operator CLI that writes inbound message JSON files to queue_v2\inbox
# - Waits for reply JSON files in queue_v2\outbox
# - Zero model logic; routing is only /chat /coder /reasoner /retrieval command prefix
#
# Fix in this version:
# - Supports BOTH manifest schemas:
#   - paths.queue_inbox / paths.queue_outbox (new)
#   - paths.inbox / paths.outbox (legacy)
# - Correctly tracks whether a reply was received; does NOT print timeout warning after success

param(
    [string]$ManifestPath = "C:\ai_control\NEO_Stack\neo_manifest.json",
    [int]$WaitSeconds = 300,
    [int]$PollMs = 250
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Read-Json {
    param([string]$Path)
    $raw = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
    return ($raw | ConvertFrom-Json)
}

function Write-JsonUtf8NoBom {
    param([string]$Path, [object]$Obj)
    $json = $Obj | ConvertTo-Json -Depth 25
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $json, $enc)
}

function Ensure-Dir {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path | Out-Null
    }
}

function Now-UTC {
    (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
}

function New-StableId {
    param([string]$Prefix = "msg")
    $ts = (Get-Date).ToString("yyyyMMdd_HHmmss_fff")
    $rand = [Guid]::NewGuid().ToString("N").Substring(0,12)
    return ("{0}_{1}_{2}" -f $Prefix, $ts, $rand)
}

function Get-PathValue {
    param([object]$Manifest, [string]$Key)
    try {
        if ($Manifest -and $Manifest.paths) {
            $p = $Manifest.paths
            $v = $p.PSObject.Properties[$Key]
            if ($v -and $v.Value) { return [string]$v.Value }
        }
    } catch { }
    return ""
}

function Resolve-QueuePaths {
    param([object]$Manifest)

    $inbox  = Get-PathValue -Manifest $Manifest -Key "queue_inbox"
    $outbox = Get-PathValue -Manifest $Manifest -Key "queue_outbox"

    if ([string]::IsNullOrWhiteSpace($inbox))  { $inbox  = Get-PathValue -Manifest $Manifest -Key "inbox" }
    if ([string]::IsNullOrWhiteSpace($outbox)) { $outbox = Get-PathValue -Manifest $Manifest -Key "outbox" }

    if ([string]::IsNullOrWhiteSpace($inbox))  { $inbox  = "C:\ai_control\NEO_Stack\queue_v2\inbox" }
    if ([string]::IsNullOrWhiteSpace($outbox)) { $outbox = "C:\ai_control\NEO_Stack\queue_v2\outbox" }

    return @($inbox, $outbox)
}

# ---- Load manifest
if (-not (Test-Path -LiteralPath $ManifestPath)) {
    throw ("Manifest not found: {0}" -f $ManifestPath)
}
$manifest = Read-Json -Path $ManifestPath

# ---- Resolve queue paths
$paths = Resolve-QueuePaths -Manifest $manifest
$INBOX  = $paths[0]
$OUTBOX = $paths[1]

Ensure-Dir $INBOX
Ensure-Dir $OUTBOX

Write-Host "NEO CHAT SYNC (queue_v2)"
Write-Host ("INBOX:  {0}" -f $INBOX)
Write-Host ("OUTBOX: {0}" -f $OUTBOX)
Write-Host "Commands: /exit /help | /chat /coder /reasoner /retrieval"

$route = "chat"

while ($true) {
    $line = Read-Host "YOU"
    if ($null -eq $line) { continue }
    $t = [string]$line

    if ($t.Trim().Length -eq 0) { continue }

    if ($t -ieq "/exit") { break }
    if ($t -ieq "/help") {
        Write-Host "Commands: /exit /help | /chat /coder /reasoner /retrieval"
        Write-Host "Tip: Prefix with /chat etc, or set route then type message."
        continue
    }

    if ($t.StartsWith("/chat", [System.StringComparison]::OrdinalIgnoreCase)) {
        $route = "chat"
        $rest = ($t -replace '^\s*/chat\s*', '')
        Write-Host "ROUTE SET: chat"
        if ($rest.Trim().Length -eq 0) { continue }
        $t = $rest
    }
    elseif ($t.StartsWith("/coder", [System.StringComparison]::OrdinalIgnoreCase)) {
        $route = "coder"
        $rest = ($t -replace '^\s*/coder\s*', '')
        Write-Host "ROUTE SET: coder"
        if ($rest.Trim().Length -eq 0) { continue }
        $t = $rest
    }
    elseif ($t.StartsWith("/reasoner", [System.StringComparison]::OrdinalIgnoreCase)) {
        $route = "reasoner"
        $rest = ($t -replace '^\s*/reasoner\s*', '')
        Write-Host "ROUTE SET: reasoner"
        if ($rest.Trim().Length -eq 0) { continue }
        $t = $rest
    }
    elseif ($t.StartsWith("/retrieval", [System.StringComparison]::OrdinalIgnoreCase)) {
        $route = "retrieval"
        $rest = ($t -replace '^\s*/retrieval\s*', '')
        Write-Host "ROUTE SET: retrieval"
        if ($rest.Trim().Length -eq 0) { continue }
        $t = $rest
    }

    $id = New-StableId -Prefix "msg"
    $msgObj = [ordered]@{
        id     = $id
        ts_utc = (Now-UTC)
        route  = $route
        text   = $t
    }

    $msgName = ("{0}.json" -f $id)
    $msgPath = Join-Path $INBOX $msgName
    Write-JsonUtf8NoBom -Path $msgPath -Obj $msgObj

    $deadline = (Get-Date).AddSeconds($WaitSeconds)
    $replyPath = Join-Path $OUTBOX ("reply_{0}.json" -f $id)

    $gotReply = $false

    while ((Get-Date) -lt $deadline) {
        if (Test-Path -LiteralPath $replyPath) {
            try {
                $reply = Read-Json -Path $replyPath

                if ($reply -and ($reply.ok -eq $false) -and $reply.error) {
                    Write-Host ("ERROR: {0}" -f [string]$reply.error)
                }

                if ($reply -and $reply.text) {
                    Write-Host ("NEO: {0}" -f [string]$reply.text)
                } else {
                    if ($reply -and ($reply.ok -eq $true)) {
                        Write-Host "NEO: (empty reply)"
                    }
                }

                Remove-Item -LiteralPath $replyPath -Force -ErrorAction SilentlyContinue
                $gotReply = $true
                break
            } catch {
                Write-Host ("WARN: reply read failed: {0}" -f $_.Exception.Message)
                Start-Sleep -Milliseconds $PollMs
                continue
            }
        }
        Start-Sleep -Milliseconds $PollMs
    }

    if (-not $gotReply) {
        Write-Host ("WARNING: (no reply found yet - timeout after {0} s)" -f $WaitSeconds)
    }
}

Write-Host "EXIT"

