# ============================================================
# Neo-NeuralNetwork.psm1
# Neural network and machine learning functions for Neo
# ============================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ============================================
# Utility: Logging
# ============================================
function Write-NeuralLog {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet("INFO","WARN","ERROR")][string]$Level = "INFO"
    )

    $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $line = "[{0}] [{1}] {2}" -f $ts, $Level, $Message
    Write-Host $line
}

# ============================================
# Data Preparation
# ============================================
function Normalize-InputData {
    param(
        [Parameter(Mandatory=$true)][double[]]$Data
    )

    $minVal = ($Data | Measure-Object -Minimum).Minimum
    $maxVal = ($Data | Measure-Object -Maximum).Maximum

    if ($maxVal -eq $minVal) {
        return ,@(0.0) * $Data.Count
    }

    $norm = foreach ($x in $Data) {
        ($x - $minVal) / ($maxVal - $minVal)
    }

    return ,$norm
}

function Split-TrainTest {
    param(
        [Parameter(Mandatory=$true)][double[]]$Data,
        [double]$TrainRatio = 0.8
    )

    if ($TrainRatio -le 0 -or $TrainRatio -ge 1) {
        throw "TrainRatio must be between 0 and 1."
    }

    $count = $Data.Count
    $trainCount = [int]([Math]::Floor($count * $TrainRatio))

    $train = $Data[0..($trainCount-1)]
    $test  = $Data[$trainCount..($count-1)]

    return @{
        train = $train
        test  = $test
    }
}

# ============================================
# Simple Neural Node
# ============================================
function New-NeuralNode {
    param(
        [int]$InputSize = 1
    )

    $weights = @()
    for ($i=0; $i -lt $InputSize; $i++) {
        # init small random weights
        $weights += ((Get-Random -Minimum 0 -Maximum 1000) / 100000.0)
    }

    return [pscustomobject]@{
        InputSize = $InputSize
        Weights   = $weights
        Bias      = 0.0
    }
}

function Invoke-NeuralForward {
    param(
        [Parameter(Mandatory=$true)]$Node,
        [Parameter(Mandatory=$true)][double[]]$Inputs
    )

    if ($Inputs.Count -ne $Node.InputSize) {
        throw "Input size mismatch. Expected $($Node.InputSize), got $($Inputs.Count)"
    }

    $sum = 0.0
    for ($i=0; $i -lt $Node.InputSize; $i++) {
        $sum += ($Node.Weights[$i] * $Inputs[$i])
    }
    $sum += $Node.Bias

    # sigmoid activation
    $out = 1.0 / (1.0 + [Math]::Exp(-1.0 * $sum))
    return $out
}

function Invoke-NeuralTrainStep {
    param(
        [Parameter(Mandatory=$true)]$Node,
        [Parameter(Mandatory=$true)][double[]]$Inputs,
        [Parameter(Mandatory=$true)][double]$Target,
        [double]$LearningRate = 0.1
    )

    $output = Invoke-NeuralForward -Node $Node -Inputs $Inputs
    $error = $Target - $output

    # derivative sigmoid: output*(1-output)
    $delta = $error * ($output * (1.0 - $output))

    # update weights
    for ($i=0; $i -lt $Node.InputSize; $i++) {
        $Node.Weights[$i] = $Node.Weights[$i] + ($LearningRate * $delta * $Inputs[$i])
    }

    # update bias
    $Node.Bias = $Node.Bias + ($LearningRate * $delta)

    return @{
        output = $output
        error  = $error
        delta  = $delta
    }
}

# ============================================
# Multi-Layer Perceptron (minimal)
# ============================================
function New-MLP {
    param(
        [int]$InputSize = 1,
        [int]$HiddenSize = 4
    )

    $hidden = @()
    for ($i=0; $i -lt $HiddenSize; $i++) {
        $hidden += New-NeuralNode -InputSize $InputSize
    }

    $outputNode = New-NeuralNode -InputSize $HiddenSize

    return [pscustomobject]@{
        InputSize  = $InputSize
        HiddenSize = $HiddenSize
        Hidden     = $hidden
        Output     = $outputNode
    }
}

function Invoke-MLPForward {
    param(
        [Parameter(Mandatory=$true)]$Net,
        [Parameter(Mandatory=$true)][double[]]$Inputs
    )

    if ($Inputs.Count -ne $Net.InputSize) {
        throw "Input size mismatch. Expected $($Net.InputSize), got $($Inputs.Count)"
    }

    $hiddenOut = @()
    foreach ($h in $Net.Hidden) {
        $hiddenOut += (Invoke-NeuralForward -Node $h -Inputs $Inputs)
    }

    $out = Invoke-NeuralForward -Node $Net.Output -Inputs $hiddenOut
    return @{
        hidden = $hiddenOut
        output = $out
    }
}

function Invoke-MLPTrainStep {
    param(
        [Parameter(Mandatory=$true)]$Net,
        [Parameter(Mandatory=$true)][double[]]$Inputs,
        [Parameter(Mandatory=$true)][double]$Target,
        [double]$LearningRate = 0.1
    )

    $fwd = Invoke-MLPForward -Net $Net -Inputs $Inputs
    $hiddenOut = $fwd.hidden
    $out = $fwd.output

    $errorOut = $Target - $out
    $deltaOut = $errorOut * ($out * (1.0 - $out))

    # Update output node weights
    for ($i=0; $i -lt $Net.HiddenSize; $i++) {
        $Net.Output.Weights[$i] = $Net.Output.Weights[$i] + ($LearningRate * $deltaOut * $hiddenOut[$i])
    }
    $Net.Output.Bias = $Net.Output.Bias + ($LearningRate * $deltaOut)

    # Backprop to hidden nodes (single layer)
    for ($h=0; $h -lt $Net.HiddenSize; $h++) {
        $hiddenNode = $Net.Hidden[$h]
        $hiddenVal = $hiddenOut[$h]
        $errorHidden = $deltaOut * $Net.Output.Weights[$h]
        $deltaHidden = $errorHidden * ($hiddenVal * (1.0 - $hiddenVal))

        for ($i=0; $i -lt $Net.InputSize; $i++) {
            $hiddenNode.Weights[$i] = $hiddenNode.Weights[$i] + ($LearningRate * $deltaHidden * $Inputs[$i])
        }
        $hiddenNode.Bias = $hiddenNode.Bias + ($LearningRate * $deltaHidden)
    }

    return @{
        output = $out
        error  = $errorOut
        delta  = $deltaOut
    }
}

# ============================================
# Demo: Train on simple data
# ============================================
function Invoke-NeoNeuralTrainDemo {
    [CmdletBinding()]
    param()

    Write-NeuralLog "Starting Neo Neural Training Demo..." "INFO"

    # Example dataset: learn identity-like mapping
    $raw = @(0.0, 0.2, 0.4, 0.6, 0.8, 1.0)
    $norm = Normalize-InputData -Data $raw

    $split = Split-TrainTest -Data $norm -TrainRatio 0.8
    $train = $split.train
    $test  = $split.test

    $net = New-MLP -InputSize 1 -HiddenSize 4

    $epochs = 200
    $lr = 0.3

    for ($e=1; $e -le $epochs; $e++) {
        $sumErr = 0.0
        foreach ($x in $train) {
            $inputs = @($x)
            $target = $x
            $step = Invoke-MLPTrainStep -Net $net -Inputs $inputs -Target $target -LearningRate $lr
            $sumErr += [Math]::Abs($step.error)
        }

        if ($e % 50 -eq 0) {
            Write-NeuralLog ("Epoch {0} AvgErr={1}" -f $e, ($sumErr / $train.Count)) "INFO"
        }
    }

    Write-NeuralLog "Testing..." "INFO"
    foreach ($x in $test) {
        $pred = (Invoke-MLPForward -Net $net -Inputs @($x)).output
        Write-Host ("x={0:0.00} pred={1:0.00}" -f $x, $pred)
    }

    Write-NeuralLog "Neo Neural Training Demo complete." "INFO"
}

Export-ModuleMember -Function `
    Normalize-InputData, Split-TrainTest, `
    New-NeuralNode, Invoke-NeuralForward, Invoke-NeuralTrainStep, `
    New-MLP, Invoke-MLPForward, Invoke-MLPTrainStep, `
    Invoke-NeoNeuralTrainDemo
