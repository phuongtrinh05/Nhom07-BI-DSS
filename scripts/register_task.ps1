# Registers the daily Windows Task Scheduler job for the forecasting pipeline (G24).
# Run once, in PowerShell, as the user who owns the gateway and the SQL password variable:
#   powershell -ExecutionPolicy Bypass -File scripts\register_task.ps1
# Remove later with:  Unregister-ScheduledTask -TaskName 'Nhom07 Forecast Pipeline' -Confirm:$false

param([string]$At = '06:30')

$script = Join-Path $PSScriptRoot 'run_pipeline.ps1'
$action = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$script`"" -WorkingDirectory (Split-Path -Parent $PSScriptRoot)
$trigger = New-ScheduledTaskTrigger -Daily -At $At
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 2)
Register-ScheduledTask -TaskName 'Nhom07 Forecast Pipeline' -Action $action -Trigger $trigger -Settings $settings `
    -Description 'Nhom07 BI&DSS: run forecast notebooks G06-G11 and load MaterialDW before the 07:00 Power BI refresh' -Force |
    Select-Object TaskName, State
