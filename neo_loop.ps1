# C:\ai_control\NEO_Stack\neo_loop.ps1
# NEO LOOP - MANIFEST DRIVEN (queue_v2) - Windows PowerShell 5.1 SAFE (ASCII)

param(
    [string]$ManifestPath = "C:\ai_control\NEO_Stack\neo_manifest.json",
    [int]$PollMs = 250,
    [int]$IdleSleepMs = 250,
    [switch]$Quiet,
    [ValidateSet("INFO","WARN","ERROR")]
    [string]$LogLevel = "INFO"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ============================
# Constants
# ============================
$script:NEO_ROOT = "C:\ai_control\NEO_Stack"
$script:ADAPTER_PATH = "C:\ai_control\NEO_Stack\adapters\ollama_http.ps1"

$script:SELFREAD_MAX_BYTES_DEFAULT = 131072   # 128 KB
$script:SELFREAD_MAX_BYTES_HARDCAP = 524288   # 512 KB

# ============================
# Utilities
# ============================
function Ensure-Dir {
    param([Parameter(Mandatory=$true)][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Write-Log {
    param(
        [Parameter(Mandatory=$true)][ValidateSet("INFO","WARN","ERROR")][string]$Level,
        [Parameter(Mandatory=$true)][string]$Message
    )
    $order = @{ "INFO"=0; "WARN"=1; "ERROR"=2 }
    if ($order[$Level] -lt $order[$LogLevel]) { return }

    $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss.fff")
    $line = "[$ts][$Level] $Message"
    if (-not $Quiet) { Write-Host $line }
    if ($script:LogFile) {
        try { Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8 } catch { }
    }
}

function Safe-Text {
    param([object]$v)
    if ($null -eq $v) { return "" }
    return [string]$v
}

function Get-PropValue {
    param(
        [Parameter(Mandatory=$true)][object]$Obj,
        [Parameter(Mandatory=$true)][string]$Name
    )
    $p = $Obj.PSObject.Properties[$Name]
    if ($null -eq $p) { return $null }
    return $p.Value
}

function Read-JsonFile {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { throw "JSON_NOT_FOUND: $Path" }
    $raw = Get-Content -LiteralPath $Path -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) { throw "JSON_EMPTY: $Path" }
    try { return ($raw | ConvertFrom-Json) } catch { throw "JSON_PARSE_ERROR: $Path :: $($_.Exception.Message)" }
}

function Write-JsonFile {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)]$Object
    )
    $json = $Object | ConvertTo-Json -Depth 12
    Set-Content -LiteralPath $Path -Value $json -Encoding UTF8
}

function New-GuidNoHyphen { return ([Guid]::NewGuid().ToString("N")) }
function Get-NowUtcIso { return ([DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")) }

function Move-Atomic {
    param([Parameter(Mandatory=$true)][string]$From, [Parameter(Mandatory=$true)][string]$To)
    Move-Item -LiteralPath $From -Destination $To -Force
}

# ============================
# Adapter Load (SCRIPT SCOPE)
# ============================
if (-not (Test-Path -LiteralPath $script:ADAPTER_PATH)) {
    throw "ADAPTER_NOT_FOUND: $script:ADAPTER_PATH"
}

# Dot-source at script scope so Invoke-OllamaGenerate persists
. $script:ADAPTER_PATH

if (-not (Get-Command -Name Invoke-OllamaGenerate -ErrorAction SilentlyContinue)) {
    throw "ADAPTER_INVALID: Invoke-OllamaGenerate not found after dot-sourcing $script:ADAPTER_PATH"
}

function Reload-AdapterIfMissing {
    if (-not (Get-Command -Name Invoke-OllamaGenerate -ErrorAction SilentlyContinue)) {
        . $script:ADAPTER_PATH
        if (-not (Get-Command -Name Invoke-OllamaGenerate -ErrorAction SilentlyContinue)) {
            throw "ADAPTER_INVALID: Invoke-OllamaGenerate missing even after reload"
        }
    }
}

# ============================
# Controlled Self-Read
# ============================
function Read-SafeTextFile {
    param(
        [Parameter(Mandatory=$true)][string]$Root,
        [Parameter(Mandatory=$true)][string]$RelativePath,
        [int]$MaxBytes
    )

    if ($null -eq $MaxBytes -or $MaxBytes -le 0) { $MaxBytes = 65536 }
    if ($MaxBytes -gt $script:SELFREAD_MAX_BYTES_HARDCAP) {
        throw "SELFREAD_DENIED: MaxBytes exceeds hard cap ($script:SELFREAD_MAX_BYTES_HARDCAP)"
    }

    $rootFull = [IO.Path]::GetFullPath($Root)
    $target   = [IO.Path]::GetFullPath((Join-Path $rootFull $RelativePath))

    if (-not $target.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)) {
        throw "SELFREAD_DENIED: Path escapes root. rel='$RelativePath'"
    }

    $ext = [IO.Path]::GetExtension($target).ToLowerInvariant()
    $allowed = @(".ps1",".json",".md",".txt",".log")
    if ($allowed -notcontains $ext) { throw "SELFREAD_DENIED: Extension not allowed: $ext" }
    if (-not (Test-Path -LiteralPath $target)) { throw "SELFREAD_NOTFOUND: $RelativePath" }

    $fi = Get-Item -LiteralPath $target
    if ($fi.Length -gt $MaxBytes) {
        throw ("SELFREAD_TOO_LARGE: {0} bytes={1} max={2}" -f $RelativePath, $fi.Length, $MaxBytes)
    }

    return (Get-Content -LiteralPath $target -Raw)
}

# ============================
# Manifest Validate
# ============================
function Validate-Manifest {
    param([Parameter(Mandatory=$true)]$m)

    $paths = Get-PropValue -Obj $m -Name "paths"
    if ($null -eq $paths) { throw "MANIFEST_INVALID: missing paths" }

    foreach ($k in @(
        "queue_inbox","queue_processing","queue_outbox","queue_processed","queue_deadletter",
        "kb_root","artifacts_root","log_file"
    )) {
        $v = Get-PropValue -Obj $paths -Name $k
        if ($null -eq $v -or [string]::IsNullOrWhiteSpace([string]$v)) {
            throw "MANIFEST_INVALID: missing/empty paths.$k"
        }
    }

    $modelMap = Get-PropValue -Obj $m -Name "model_map"
    if ($null -eq $modelMap) { throw "MANIFEST_INVALID: missing model_map" }

    foreach ($r in @("chat","coder","reasoner","retrieval")) {
        $mv = Get-PropValue -Obj $modelMap -Name $r
        if ($null -eq $mv -or [string]::IsNullOrWhiteSpace([string]$mv)) {
            throw "MANIFEST_INVALID: missing/empty model_map.$r"
        }
    }

    $oll = Get-PropValue -Obj $m -Name "ollama"
    if ($null -eq $oll) { throw "MANIFEST_INVALID: missing ollama" }

    $bu = Get-PropValue -Obj $oll -Name "base_url"
    if ($null -eq $bu -or [string]::IsNullOrWhiteSpace([string]$bu)) {
        throw "MANIFEST_INVALID: missing/empty ollama.base_url"
    }
}

# ============================
# Message Helpers
# ============================
function Normalize-Route {
    param([string]$Route)
    $r = (Safe-Text $Route).Trim().ToLowerInvariant()
    switch ($r) {
        "" { "chat" }
        "analysis" { "reasoner" }
        "reason" { "reasoner" }
        "/chat" { "chat" }
        "/coder" { "coder" }
        "/reasoner" { "reasoner" }
        "/retrieval" { "retrieval" }
        "chat" { "chat" }
        "coder" { "coder" }
        "reasoner" { "reasoner" }
        "retrieval" { "retrieval" }
        default { $r }
    }
}

function Validate-Message {
    param([Parameter(Mandatory=$true)]$msg)

    $idv = Get-PropValue -Obj $msg -Name "id"
    if ($null -eq $idv -or [string]::IsNullOrWhiteSpace([string]$idv)) {
        throw "MSG_INVALID: missing id"
    }

    $t = Get-PropValue -Obj $msg -Name "user_text"
    if ($null -eq $t) { $t = Get-PropValue -Obj $msg -Name "userText" }
    if ($null -eq $t) { $t = Get-PropValue -Obj $msg -Name "text" }
    if ($null -eq $t) { $t = Get-PropValue -Obj $msg -Name "message" }

    if ($null -eq $t -or [string]::IsNullOrWhiteSpace([string]$t)) {
        throw "MSG_INVALID: missing user_text/userText/text/message"
    }

    $msg | Add-Member -NotePropertyName "_userText" -NotePropertyValue (Safe-Text $t) -Force

    $routeRaw = Get-PropValue -Obj $msg -Name "route"
    if ($null -eq $routeRaw) { $routeRaw = Get-PropValue -Obj $msg -Name "mode" }

    $norm = Normalize-Route (Safe-Text $routeRaw)
    if ($norm -notin @("chat","coder","reasoner","retrieval")) {
        throw "MSG_INVALID: invalid route '$norm'"
    }

    $msg | Add-Member -NotePropertyName "_route" -NotePropertyValue $norm -Force
}

function Build-SystemPreamble {
@"
You are NEO-LAB, a local, offline, file-governed assistant invoked through a deterministic control plane.
You do not have OS access. You only know what the operator provides in the prompt.
Never claim you can see files unless the content is included.
"@
}

function Build-Prompt {
    param(
        [Parameter(Mandatory=$true)][string]$UserText,
        [Parameter(Mandatory=$true)][string]$Route,
        [Parameter(Mandatory=$true)][string]$StackPreamble
    )

    $roleInstr = switch ($Route) {
        "coder" { "Role: CODE. Produce correct code and file edits. Prefer PowerShell 5.1 compatibility." }
        "reasoner" { "Role: ANALYSIS. Explain architecture, diagnose issues, propose tests and improvements." }
        "retrieval" { "Role: RETRIEVAL. Use only provided context; if insufficient, request specific file names or data." }
        default { "Role: CHAT. Be concise and helpful." }
    }

@"
$StackPreamble

$roleInstr

USER:
$UserText
"@
}

function Deadletter {
    param(
        [Parameter(Mandatory=$true)][string]$DeadDir,
        [Parameter(Mandatory=$true)][string]$MsgPath,
        [Parameter(Mandatory=$true)][string]$ErrorText
    )

    Ensure-Dir $DeadDir

    $base = Split-Path -Leaf $MsgPath
    $dst  = Join-Path $DeadDir $base

    try {
        if (Test-Path -LiteralPath $MsgPath) { Move-Atomic -From $MsgPath -To $dst }
    } catch {
        try { Copy-Item -LiteralPath $MsgPath -Destination $dst -Force } catch { }
        try { Remove-Item -LiteralPath $MsgPath -Force -ErrorAction SilentlyContinue } catch { }
    }

    $exPath = ($dst + ".exception")
    try { Set-Content -LiteralPath $exPath -Value $ErrorText -Encoding UTF8 } catch { }

    Write-Log -Level "ERROR" -Message ("DEADLETTER: {0} :: {1}" -f $base, $ErrorText)
}

# ============================
# Main
# ============================
$manifest = Read-JsonFile -Path $ManifestPath
Validate-Manifest -m $manifest

$paths = Get-PropValue -Obj $manifest -Name "paths"

$inbox      = [string](Get-PropValue -Obj $paths -Name "queue_inbox")
$processing = [string](Get-PropValue -Obj $paths -Name "queue_processing")
$outbox     = [string](Get-PropValue -Obj $paths -Name "queue_outbox")
$processed  = [string](Get-PropValue -Obj $paths -Name "queue_processed")
$deadletter = [string](Get-PropValue -Obj $paths -Name "queue_deadletter")

$kbRoot     = [string](Get-PropValue -Obj $paths -Name "kb_root")
$artRoot    = [string](Get-PropValue -Obj $paths -Name "artifacts_root")
$script:LogFile = [string](Get-PropValue -Obj $paths -Name "log_file")

Ensure-Dir $inbox; Ensure-Dir $processing; Ensure-Dir $outbox; Ensure-Dir $processed; Ensure-Dir $deadletter
Ensure-Dir $kbRoot; Ensure-Dir $artRoot

$stopFile = Join-Path $artRoot "STOP"

$oll = Get-PropValue -Obj $manifest -Name "ollama"
$baseUrl = [string](Get-PropValue -Obj $oll -Name "base_url")
$modelMap = Get-PropValue -Obj $manifest -Name "model_map"

Write-Log -Level "INFO" -Message ("NEO LOOP START :: manifest={0}" -f $ManifestPath)
Write-Log -Level "INFO" -Message ("INBOX={0}" -f $inbox)
Write-Log -Level "INFO" -Message ("OUTBOX={0}" -f $outbox)
Write-Log -Level "INFO" -Message ("ADAPTER={0}" -f $script:ADAPTER_PATH)
Write-Log -Level "INFO" -Message ("SELFREAD_MAX_BYTES_DEFAULT={0} HARD_CAP={1}" -f $script:SELFREAD_MAX_BYTES_DEFAULT, $script:SELFREAD_MAX_BYTES_HARDCAP)

while ($true) {

    if (Test-Path -LiteralPath $stopFile) {
        Write-Log -Level "WARN" -Message "STOP file detected. Exiting cleanly."
        break
    }

    $next = Get-ChildItem -LiteralPath $inbox -File -Filter "*.json" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime |
        Select-Object -First 1

    if (-not $next) {
        Start-Sleep -Milliseconds $IdleSleepMs
        continue
    }

    $msgFile  = $next.FullName
    $procFile = Join-Path $processing ($next.Name)

    try { Move-Atomic -From $msgFile -To $procFile }
    catch { Start-Sleep -Milliseconds $PollMs; continue }

    try {
        $msg = Read-JsonFile -Path $procFile
        Validate-Message -msg $msg

        $id       = Safe-Text (Get-PropValue -Obj $msg -Name "id")
        $userText = Safe-Text (Get-PropValue -Obj $msg -Name "_userText")
        $route    = Safe-Text (Get-PropValue -Obj $msg -Name "_route")

        $model = Safe-Text (Get-PropValue -Obj $modelMap -Name $route)
        if ([string]::IsNullOrWhiteSpace($model)) { throw "MODEL_MAP_MISSING: route=$route" }

        $preamble = Build-SystemPreamble
        $prompt   = Build-Prompt -UserText $userText -Route $route -StackPreamble $preamble

        # /self
        if ($userText -match '^\s*/self\s+(.+?)(?:\s+(\d+))?\s*$') {
            $rel = $Matches[1].Trim()
            $reqMax = $Matches[2]

            if ($rel -match '^[A-Za-z]:\\' -or $rel -match '^\\') {
                throw "SELFREAD_DENIED: Absolute paths not allowed."
            }

            $maxBytes = $script:SELFREAD_MAX_BYTES_DEFAULT
            if (-not [string]::IsNullOrWhiteSpace($reqMax)) { $maxBytes = [int]$reqMax }

            $content = Read-SafeTextFile -Root $script:NEO_ROOT -RelativePath $rel -MaxBytes $maxBytes

            $prompt = @"
You are NEO-LAB running in analysis mode. The operator explicitly provided internal system file content.

FILE: $rel
MAX_BYTES: $maxBytes
================ BEGIN FILE ================
$content
================= END FILE =================

TASK:
1) Explain what this file does
2) Describe its role in the NEO architecture
3) Identify risks/bugs (be specific)
4) Propose concrete improvements (patches/instructions; do NOT auto-modify)
"@
            $route = "reasoner"
            $model = Safe-Text (Get-PropValue -Obj $modelMap -Name $route)
        }

        # Ensure adapter still exists (script scope reload)
        Reload-AdapterIfMissing

        $timeout = 120
        $numPredict = 512
        $temp = 0.2

        $t2 = Get-PropValue -Obj $oll -Name "timeout_seconds"
        $n2 = Get-PropValue -Obj $oll -Name "num_predict"
        $p2 = Get-PropValue -Obj $oll -Name "temperature"
        if ($null -ne $t2) { $timeout = [int]$t2 }
        if ($null -ne $n2) { $numPredict = [int]$n2 }
        if ($null -ne $p2) { $temp = [double]$p2 }

        Write-Log -Level "INFO" -Message ("PROCESS id={0} route={1} model={2}" -f $id, $route, $model)

        $raw = Invoke-OllamaGenerate -BaseUrl $baseUrl -Model $model -Prompt $prompt -TimeoutSeconds $timeout -NumPredict $numPredict -Temperature $temp

        # --- Extract clean assistant text from adapter result (prevents huge JSON/context spam) ---
        $text = ""

        if ($null -eq $raw) {
            $text = ""
        }
        elseif ($raw -is [string]) {
            $text = [string]$raw
        }
        else {
            # Prefer adapter's clean 'text' field
            $pText = $raw.PSObject.Properties["text"]
            if ($pText -and -not [string]::IsNullOrWhiteSpace([string]$pText.Value)) {
                $text = [string]$pText.Value
            }
            else {
                # Fallback: raw JSON -> response
                $pRaw = $raw.PSObject.Properties["raw"]
                if ($pRaw -and -not [string]::IsNullOrWhiteSpace([string]$pRaw.Value)) {
                    try {
                        $rawObj = $pRaw.Value | ConvertFrom-Json
                        if ($rawObj.PSObject.Properties["response"]) {
                            $text = [string]$rawObj.response
                        }
                    } catch { }
                }

                # Final fallback: response field
                if ([string]::IsNullOrWhiteSpace($text)) {
                    $pResp = $raw.PSObject.Properties["response"]
                    if ($pResp) { $text = [string]$pResp.Value }
                }
            }
        }

        $text = ($text | Out-String).Trim()
        # -------------------------------------------------------------------------------

        $reply = [ordered]@{
            id          = ("reply_" + (New-GuidNoHyphen))
            in_reply_to = $id
            created_utc = (Get-NowUtcIso)
            route       = $route
            model       = $model
            ok          = $true
            text        = $text
        }

        $replyName = ("reply_{0}.json" -f $id)
        $replyPath = Join-Path $outbox $replyName
        Write-JsonFile -Path $replyPath -Object $reply

        $donePath = Join-Path $processed ($next.Name)
        Move-Atomic -From $procFile -To $donePath

        Write-Log -Level "INFO" -Message ("OK id={0} -> {1}" -f $id, $replyName)
    }
    catch {
        $err = $_.Exception.Message
        $detail = $err
        if ($_.Exception.StackTrace) { $detail = ($detail + "`n" + $_.Exception.StackTrace) }
        Deadletter -DeadDir $deadletter -MsgPath $procFile -ErrorText $detail
    }

    Start-Sleep -Milliseconds $PollMs
}

Write-Log -Level "INFO" -Message "NEO LOOP STOP"

