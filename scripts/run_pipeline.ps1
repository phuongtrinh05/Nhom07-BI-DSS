# Nhom07 forecasting pipeline (G24) - run by Windows Task Scheduler every morning before the
# Power BI scheduled refresh (07:00).
#   1. make sure the MaterialDW SQL Server container is running
#   2. execute the forecasting notebooks G06 -> G09 -> G10 -> G11 (headless)
#   3. load the official forecast + evaluation (incl. Naive benchmark) into MaterialDW
# The SQL password is never stored here: it is read from the MATERIALDW_SA_PASSWORD user variable.
# Each run writes logs\pipeline_yyyyMMdd_HHmm.log; exit code 0 = success, 1 = a step failed.

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$python = Join-Path $root '.venv\Scripts\python.exe'
$logDir = Join-Path $root 'logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$log = Join-Path $logDir ("pipeline_{0}.log" -f (Get-Date -Format 'yyyyMMdd_HHmm'))

function Write-Log([string]$msg) {
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
    Add-Content -Path $log -Value $line -Encoding UTF8
    Write-Output $line
}
function Invoke-Step([string]$name, [scriptblock]$body) {
    Write-Log "START  $name"
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $global:LASTEXITCODE = 0
    # Native tools write warnings to stderr; in Windows PowerShell 5.1 that would stop the script under
    # ErrorActionPreference=Stop. Inside a step we log stderr and judge success by the exit code only.
    $ErrorActionPreference = 'Continue'
    & $body 2>&1 | ForEach-Object { Add-Content -Path $log -Value "         $_" -Encoding UTF8 }
    $code = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($code -ne 0) { throw "$name exited with code $code" }
    Write-Log ("OK     {0} ({1:n0}s)" -f $name, $sw.Elapsed.TotalSeconds)
}

try {
    Write-Log "Pipeline started on $env:COMPUTERNAME"
    if (-not $env:MATERIALDW_SA_PASSWORD) {
        $env:MATERIALDW_SA_PASSWORD = [Environment]::GetEnvironmentVariable('MATERIALDW_SA_PASSWORD', 'User')
    }
    if (-not $env:MATERIALDW_SA_PASSWORD) { throw 'MATERIALDW_SA_PASSWORD is not set (see README, section Automation)' }

    Invoke-Step 'Step 1 - SQL Server container sql2025' {
        $state = docker inspect -f '{{.State.Running}}' sql2025
        if ($state -ne 'true') { docker start sql2025; Start-Sleep -Seconds 20 } else { 'already running' }
    }
    Invoke-Step 'Step 2 - forecasting notebooks G06-G11' { & $python (Join-Path $root 'scripts\run_notebooks.py') }
    Invoke-Step 'Step 3 - load forecast into MaterialDW' {
        & $python (Join-Path $root 'notebooks\load_g11_to_dw.py')
    }
    Write-Log 'Pipeline finished OK - Power BI Service refreshes from the gateway at 07:00'
    exit 0
}
catch {
    Write-Log "FAILED: $($_.Exception.Message)"
    exit 1
}
