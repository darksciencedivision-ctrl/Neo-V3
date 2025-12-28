# C:\ai_control\NEO_Stack\adapters\ollama_http.ps1
# OLLAMA HTTP ADAPTER (NON-STREAMING) - Windows PowerShell 5.1 SAFE (ASCII)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Invoke-OllamaGenerate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$BaseUrl,
        [Parameter(Mandatory=$true)][string]$Model,
        [Parameter(Mandatory=$true)][string]$Prompt,
        [int]$TimeoutSeconds = 120,
        [int]$NumPredict = 256,
        [double]$Temperature = 0.2
    )

    $uri = ($BaseUrl.TrimEnd('/') + "/api/generate")

    $payload = @{
        model  = $Model
        prompt = $Prompt
        stream = $false
        options = @{
            num_predict = $NumPredict
            temperature = $Temperature
        }
    } | ConvertTo-Json -Depth 6

    Add-Type -AssemblyName System.Net.Http | Out-Null
    $handler = New-Object System.Net.Http.HttpClientHandler
    $client  = New-Object System.Net.Http.HttpClient($handler)
    $client.Timeout = [TimeSpan]::FromSeconds($TimeoutSeconds)

    try {
        $content = New-Object System.Net.Http.StringContent($payload, [System.Text.Encoding]::UTF8, "application/json")
        $resp = $client.PostAsync($uri, $content).GetAwaiter().GetResult()
        $raw  = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult()

        if (-not $resp.IsSuccessStatusCode) {
            return [pscustomobject]@{
                ok     = $false
                status = [int]$resp.StatusCode
                model  = $Model
                url    = $uri
                error  = ("HTTP {0} {1}" -f [int]$resp.StatusCode, $resp.ReasonPhrase)
                raw    = $raw
                text   = ""
            }
        }

        $obj = $null
        try { $obj = $raw | ConvertFrom-Json } catch { $obj = $null }

        $text = ""
        if ($obj -ne $null -and ($obj.PSObject.Properties.Name -contains "response")) {
            $text = [string]$obj.response
        }

        return [pscustomobject]@{
            ok     = $true
            status = 200
            model  = $Model
            url    = $uri
            error  = ""
            raw    = $raw
            text   = $text
            meta   = $obj
        }
    }
    catch {
        return [pscustomobject]@{
            ok     = $false
            status = 0
            model  = $Model
            url    = $uri
            error  = $_.Exception.Message
            raw    = ""
            text   = ""
        }
    }
    finally {
        $client.Dispose()
    }
}
