$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$dotnet = Join-Path $root '.tools\dotnet\dotnet.exe'
if (!(Test-Path -LiteralPath $dotnet)) { $dotnet = 'dotnet' }
& $dotnet build (Join-Path $root 'DevOS.sln') -c Release
if ($LASTEXITCODE -ne 0) { throw 'Build failed.' }
& $dotnet run --project (Join-Path $root 'tests\DevOS.Tests') -c Release --no-build
if ($LASTEXITCODE -ne 0) { throw 'Unit tests failed.' }
& (Join-Path $root 'tests\PowerShellPolicy.Tests.ps1')
foreach ($component in @('Broker','Launcher')) {
    & $dotnet publish (Join-Path $root "launcher\DevOS.$component") -c Release -r win-x64 --self-contained true -o (Join-Path $root "artifacts\$($component.ToLowerInvariant())")
    if ($LASTEXITCODE -ne 0) { throw "Publish failed: $component" }
}
