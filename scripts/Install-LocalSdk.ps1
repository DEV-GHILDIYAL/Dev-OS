$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$tools = Join-Path $root '.tools'
New-Item -ItemType Directory -Path $tools -Force | Out-Null
$metadata = Invoke-RestMethod 'https://builds.dotnet.microsoft.com/dotnet/release-metadata/10.0/releases.json' -TimeoutSec 60
$sdk = @($metadata.releases | ForEach-Object { $_.sdks } | Where-Object version -eq '10.0.401')[0]
if (!$sdk) { throw 'Pinned SDK 10.0.401 is missing from official metadata.' }
$package = @($sdk.files | Where-Object { $_.rid -eq 'win-x64' -and $_.name -eq 'dotnet-sdk-win-x64.zip' })
if ($package.Count -ne 1) { throw 'No unique SDK archive in official release metadata.' }
$zip = Join-Path $tools 'sdk.zip'
Invoke-WebRequest -Uri $package[0].url -OutFile $zip -TimeoutSec 1200
if ((Get-FileHash $zip -Algorithm SHA512).Hash -ne $package[0].hash) { throw 'SDK checksum mismatch.' }
Expand-Archive -LiteralPath $zip -DestinationPath (Join-Path $tools 'dotnet') -Force
Write-Output "Installed verified SDK $($sdk.version) locally."
