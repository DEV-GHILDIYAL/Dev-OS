#Requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'
$output = Join-Path (Split-Path $PSScriptRoot -Parent) 'artifacts\hyperv-setup.json'
try {
    # Explicit user-approved setup action; never invoked by compatibility detection.
    $result = Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -All -NoRestart
    @{Success=$true; RestartNeeded=[bool]$result.RestartNeeded; Feature='Microsoft-Hyper-V-All'; Time=[DateTimeOffset]::UtcNow.ToString('o')} |
        ConvertTo-Json | Set-Content -LiteralPath $output -Encoding UTF8
} catch {
    @{Success=$false; Code='FEATURE_ENABLE_FAILED'; Time=[DateTimeOffset]::UtcNow.ToString('o')} |
        ConvertTo-Json | Set-Content -LiteralPath $output -Encoding UTF8
    exit 1
}
