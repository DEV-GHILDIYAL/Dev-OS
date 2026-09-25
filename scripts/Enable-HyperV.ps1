#Requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'
$output = Join-Path (Split-Path $PSScriptRoot -Parent) 'artifacts\hyperv-setup.json'
try {
    $edition = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').EditionID
    if ($edition -match '^Core') { throw 'WINDOWS_EDITION_UNSUPPORTED' }
    # Explicit user-approved setup action; never invoked by compatibility detection.
    $result = Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -All -NoRestart
    @{Success=$true; RestartNeeded=[bool]$result.RestartNeeded; Feature='Microsoft-Hyper-V-All'; Time=[DateTimeOffset]::UtcNow.ToString('o')} |
        ConvertTo-Json | Set-Content -LiteralPath $output -Encoding UTF8
} catch {
    $code = if ($_.Exception.Message -eq 'WINDOWS_EDITION_UNSUPPORTED') { 'WINDOWS_EDITION_UNSUPPORTED' } else { 'FEATURE_ENABLE_FAILED' }
    @{Success=$false; Code=$code; Time=[DateTimeOffset]::UtcNow.ToString('o')} |
        ConvertTo-Json | Set-Content -LiteralPath $output -Encoding UTF8
    exit 1
}
