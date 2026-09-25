$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient
$executable = Join-Path $env:ProgramFiles 'DevOS\launcher\DevOS.Launcher.exe'
$process = Start-Process -FilePath $executable -PassThru
$deadline=[DateTime]::UtcNow.AddSeconds(40)
do {
    Start-Sleep -Milliseconds 500
    $process.Refresh()
    if ($process.HasExited) { throw 'Launcher exited during startup.' }
    if ($process.MainWindowHandle -ne [IntPtr]::Zero) {
        $window=[Windows.Automation.AutomationElement]::FromHandle($process.MainWindowHandle)
        $elements=$window.FindAll([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.Condition]::TrueCondition)
        $labels=@($elements | ForEach-Object { $_.Current.Name })
        if ($labels -contains 'Phase 1 environment - encryption not configured.' -and
            @($labels | Where-Object { $_ -like 'Windows: *' }).Count -gt 0) {
            Write-Output 'PASS launcher starts and renders compatibility results.'
            Write-Output 'PASS Phase 1 encryption warning is visible.'
            Write-Output "Launcher PID: $($process.Id)"
            exit 0
        }
    }
} while ([DateTime]::UtcNow -lt $deadline)
throw 'Launcher did not render compatibility results within 40 seconds.'
