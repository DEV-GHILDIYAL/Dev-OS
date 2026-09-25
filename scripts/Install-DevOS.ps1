#Requires -RunAsAdministrator
param([switch]$Update, [switch]$RepairEmptyRegistration)
$ErrorActionPreference = 'Stop'
$sourceRoot = Split-Path $PSScriptRoot -Parent
trap {
    @{Success=$false; ErrorType=$_.Exception.GetType().Name; ErrorId=$_.FullyQualifiedErrorId;
      Line=$_.InvocationInfo.ScriptLineNumber; Time=[DateTimeOffset]::UtcNow.ToString('o')} |
      ConvertTo-Json | Set-Content (Join-Path $sourceRoot 'artifacts\install-result.json')
    exit 1
}
$destination = Join-Path $env:ProgramFiles 'DevOS'
$data = Join-Path $env:ProgramData 'DevOS'
$owner = [Security.Principal.WindowsIdentity]::GetCurrent().User
function AssertNoReparse([string]$path) {
    while ($path) {
        if ((Test-Path -LiteralPath $path) -and ((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Reparse point rejected.' }
        $path = [IO.Path]::GetDirectoryName($path)
    }
}
AssertNoReparse $destination
AssertNoReparse $data
if ($RepairEmptyRegistration) {
    if (!$Update -or !(Test-Path -LiteralPath $data) -or (Test-Path (Join-Path $data 'registration.json')) -or
        (Test-Path (Join-Path $data 'vm'))) { throw 'Only an empty incomplete installation can be repaired.' }
    $dataAcl=Get-Acl -LiteralPath $data
    if ($dataAcl.Owner -ne 'BUILTIN\Administrators' -or
        !@($dataAcl.Access | Where-Object { $_.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value -eq $owner.Value -and
            $_.AccessControlType -eq 'Allow' -and $_.FileSystemRights -eq 'ReadAndExecute, Synchronize' }).Count) { throw 'Existing ACL does not identify this installation owner.' }
    $key=[Microsoft.Win32.Registry]::LocalMachine.CreateSubKey('SOFTWARE\DevOS')
    if ($key.GetValue('OwnerSid')) { $key.Dispose(); throw 'Owner registration already exists.' }
    $key.SetValue('OwnerSid',$owner.Value,[Microsoft.Win32.RegistryValueKind]::String)
    $key.Dispose()
}
if (!$Update -and (Test-Path -LiteralPath $data)) { throw 'DevOS data already exists. Review the existing installation; this installer does not overwrite it.' }
if (!$Update -and (Test-Path -LiteralPath $destination)) { throw 'DevOS installation already exists. Use -Update only for a reviewed build.' }
if ($Update) {
    if (!(Test-Path -LiteralPath $destination) -or !(Test-Path -LiteralPath $data) -or
        (Get-ItemProperty 'HKLM:\SOFTWARE\DevOS').OwnerSid -ne $owner.Value) { throw 'Installation owner mismatch.' }
    if (Get-Process DevOS.Launcher,DevOS.Broker -ErrorAction SilentlyContinue) { throw 'Close DevOS processes before updating.' }
    foreach ($file in Get-ChildItem -LiteralPath $destination -Recurse -Force) { AssertNoReparse $file.FullName }
}
foreach ($component in @('broker','launcher')) {
    $source = Join-Path $sourceRoot "artifacts\$component"
    if (!(Test-Path -LiteralPath $source)) { throw "Publish $component before installation." }
    foreach ($file in Get-ChildItem -LiteralPath $source -Recurse -Force) { AssertNoReparse $file.FullName }
}
if (!$Update) { New-Item -ItemType Directory -Path $destination | Out-Null }
foreach ($component in @('broker','launcher')) {
    if ($Update) {
        Get-ChildItem -LiteralPath (Join-Path $sourceRoot "artifacts\$component") | Copy-Item -Destination (Join-Path $destination $component) -Recurse -Force
    } else {
        Copy-Item -LiteralPath (Join-Path $sourceRoot "artifacts\$component") -Destination $destination -Recurse
    }
}
if ($Update) {
    @{Success=$true; Updated=$true; Time=[DateTimeOffset]::UtcNow.ToString('o')} | ConvertTo-Json | Set-Content (Join-Path $sourceRoot 'artifacts\install-result.json')
    Write-Output 'Updated DevOS binaries; existing VM data preserved.'; exit 0
}
$acl = [Security.AccessControl.DirectorySecurity]::new()
$acl.SetAccessRuleProtection($true,$false)
$acl.SetOwner([Security.Principal.SecurityIdentifier]::new('S-1-5-32-544'))
foreach ($sid in @('S-1-5-18','S-1-5-32-544')) {
    $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($sid),'FullControl','ContainerInherit,ObjectInherit','None','Allow'))
}
$acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($owner,'ReadAndExecute','ContainerInherit,ObjectInherit','None','Allow'))
Set-Acl -LiteralPath $destination -AclObject $acl
New-Item -ItemType Directory -Path $data | Out-Null
Set-Acl -LiteralPath $data -AclObject $acl
(Get-Item -LiteralPath $data).Attributes = (Get-Item -LiteralPath $data).Attributes -bor [IO.FileAttributes]::NotContentIndexed
$key=[Microsoft.Win32.Registry]::LocalMachine.CreateSubKey('SOFTWARE\DevOS')
$key.SetValue('OwnerSid',$owner.Value,[Microsoft.Win32.RegistryValueKind]::String)
$key.Dispose()
Write-Output 'Installed DevOS. Start Program Files\DevOS\launcher\DevOS.Launcher.exe as the normal user.'
@{Success=$true; Updated=$false; Time=[DateTimeOffset]::UtcNow.ToString('o')} | ConvertTo-Json | Set-Content (Join-Path $sourceRoot 'artifacts\install-result.json')
